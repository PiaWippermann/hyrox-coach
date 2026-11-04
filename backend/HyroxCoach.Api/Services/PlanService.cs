using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Ai;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

/// <summary>Erzeugt und passt Trainingspläne per KI an. Das ist der einzige Ort, der Claude aufruft.</summary>
public sealed class PlanService
{
    private static readonly JsonNode Schema = LoadSchema();

    private readonly MongoContext _db;
    private readonly AnthropicClient _ai;
    private readonly AppOptions _options;

    public PlanService(MongoContext db, AnthropicClient ai, AppOptions options)
    {
        _db = db;
        _ai = ai;
        _options = options;
    }

    internal static JsonNode LoadSchema()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "contracts", "plan.schema.json");
        return JsonNode.Parse(File.ReadAllText(path))!;
    }

    /// <summary>
    /// Erstellt einen Block. Ohne [startDate]/[weeks] bestimmt BlockPlanner beides: Folgeblock direkt im Anschluss an den
    /// aktiven Plan, Erstplan ab dem nächsten Montag, [startNow] ab dem Montag dieser Woche (ersetzt den aktiven Plan).
    /// Liegt der Start in der Zukunft und gibt es einen aktiven Plan, wird der Block als „upcoming“ gespeichert.
    /// </summary>
    public async Task<PlanDoc> CreateAsync(
        User user, string kind, string? startDate, int? weeks, string? userNotes, CancellationToken ct, bool startNow = false)
    {
        var anamnese = await _db.Anamneses.Find(a => a.UserId == user.Id).FirstOrDefaultAsync(ct)
                       ?? throw new ApiException(400, "Bitte zuerst die Anamnese ausfüllen.");
        var active = await _db.Plans.Find(p => p.UserId == user.Id && p.Status == "active")
            .SortByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct);
        var today = BlockPlanner.Today(_options.TimeZone);

        DateOnly start;
        if (startDate is not null)
        {
            if (!DateOnly.TryParseExact(startDate, "yyyy-MM-dd", out start))
                throw new ApiException(400, "startDate muss das Format yyyy-MM-dd haben.");
        }
        else if (startNow)
        {
            start = BlockPlanner.MondayOf(today);
        }
        else if (kind == "adapted" && active is not null)
        {
            // Folgeblock: nahtlos im Anschluss an den aktiven Block
            start = DateOnly.ParseExact(active.StartDate, "yyyy-MM-dd").AddDays(active.Weeks * 7);
        }
        else
        {
            // Neuer Plan (z. B. nach der Anamnese): ab nächstem Montag; ein laufender Plan gilt bis dahin weiter
            start = BlockPlanner.NextMonday(today);
        }
        var blockWeeks = weeks ?? BlockPlanner.Weeks(start, BlockPlanner.Peak(anamnese, start));
        if (blockWeeks < 2 || blockWeeks > 4)
            throw new ApiException(400, "weeks muss zwischen 2 und 4 liegen.");
        startDate = start.ToString("yyyy-MM-dd");
        // Startet der Block später, bleibt der aktive Plan bis dahin gültig; PlanLifecycle schaltet am Starttag um
        var upcoming = active is not null && start > today && !startNow;

        var latestResult = await _db.Results.Find(r => r.UserId == user.Id)
            .SortByDescending(r => r.Date).FirstOrDefaultAsync(ct);

        var previous = await _db.Plans.Find(p => p.UserId == user.Id && p.Status == "active")
            .SortByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct);

        object? adaptation = null;
        if (kind == "adapted")
        {
            if (previous is null)
                throw new ApiException(400, "Es gibt noch keinen Plan, der angepasst werden könnte.");

            var filter = Builders<WorkoutLog>.Filter.And(
                Builders<WorkoutLog>.Filter.Eq(w => w.UserId, user.Id),
                Builders<WorkoutLog>.Filter.Gte(w => w.Date, previous.StartDate));
            var logs = await _db.Workouts.Find(filter).ToListAsync(ct);
            adaptation = AdaptationSummary.Build(previous.PlanJson, logs, startDate);
        }
        var weeksCount = blockWeeks;

        var userMessage = PlanPrompts.BuildUserMessage(
            startDate, weeksCount, kind, anamnese, latestResult, previous, adaptation, userNotes);

        string? lastError = null;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            await EnforceLimitsAsync(user.Id, ct);

            var message = lastError is null
                ? userMessage
                : userMessage + $"\n\nDein vorheriger Plan war ungültig: {lastError} Erzeuge den Plan neu und korrigiere das.";

            var result = await _ai.CallToolAsync(
                PlanPrompts.SystemPrompt, message, PlanPrompts.ToolName, PlanPrompts.ToolDescription,
                Schema, _options.PlanMaxTokens, ct);

            await _db.Usage.InsertOneAsync(new AiUsage
            {
                UserId = user.Id,
                Kind = kind,
                Model = _options.AnthropicModel,
                InputTokens = result.InputTokens,
                OutputTokens = result.OutputTokens
            }, cancellationToken: ct);

            if (result.StopReason == "max_tokens")
            {
                lastError = "Die Antwort wurde abgeschnitten. Plane kompakter (weniger Übungen pro Block, sehr kurze Notizen).";
                continue;
            }

            var error = PlanValidator.Validate(result.ToolInput, startDate, weeksCount, PlanValidator.RaceDays(anamnese));
            if (error is not null)
            {
                lastError = error;
                continue;
            }

            // Ein vorhandener Folgeblock wird immer ersetzt; der aktive Plan nur, wenn der neue sofort gilt
            await _db.Plans.UpdateManyAsync(
                p => p.UserId == user.Id && (p.Status == "upcoming" || (!upcoming && p.Status == "active")),
                Builders<PlanDoc>.Update.Set(p => p.Status, "archived"),
                cancellationToken: ct);

            var doc = new PlanDoc
            {
                UserId = user.Id,
                Status = upcoming ? "upcoming" : "active",
                StartDate = startDate,
                Weeks = weeksCount,
                Kind = kind,
                PlanJson = result.ToolInput.GetRawText(),
                Model = _options.AnthropicModel
            };
            await _db.Plans.InsertOneAsync(doc, cancellationToken: ct);
            return doc;
        }

        throw new ApiException(502, "Die KI hat keinen gültigen Plan geliefert: " + lastError);
    }

    private async Task EnforceLimitsAsync(string userId, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var dayStart = now.Date;
        var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);

        // Coach-Chat hat ein eigenes Limit (PlanChatService)
        var today = await _db.Usage.CountDocumentsAsync(u => u.UserId == userId && u.Kind != "chat" && u.Kind != "extract" && u.Kind != "feedback" && u.At >= dayStart, cancellationToken: ct);
        if (today >= _options.AiMaxCallsPerDay)
            throw new ApiException(429, $"Tageslimit für KI-Aufrufe erreicht ({_options.AiMaxCallsPerDay}).");

        var month = await _db.Usage.CountDocumentsAsync(u => u.UserId == userId && u.Kind != "chat" && u.Kind != "extract" && u.Kind != "feedback" && u.At >= monthStart, cancellationToken: ct);
        if (month >= _options.AiMaxCallsPerMonth)
            throw new ApiException(429, $"Monatslimit für KI-Aufrufe erreicht ({_options.AiMaxCallsPerMonth}).");
    }
}
