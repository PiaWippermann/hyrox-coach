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

    private static JsonNode LoadSchema()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "contracts", "plan.schema.json");
        return JsonNode.Parse(File.ReadAllText(path))!;
    }

    public async Task<PlanDoc> CreateAsync(
        User user, string kind, string startDate, int weeks, string? userNotes, CancellationToken ct)
    {
        if (weeks < 2 || weeks > 4)
            throw new ApiException(400, "weeks muss zwischen 2 und 4 liegen.");
        if (!DateOnly.TryParseExact(startDate, "yyyy-MM-dd", out _))
            throw new ApiException(400, "startDate muss das Format yyyy-MM-dd haben.");

        var anamnese = await _db.Anamneses.Find(a => a.UserId == user.Id).FirstOrDefaultAsync(ct)
                       ?? throw new ApiException(400, "Bitte zuerst die Anamnese ausfüllen.");

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

        var userMessage = PlanPrompts.BuildUserMessage(
            startDate, weeks, kind, anamnese, latestResult, previous, adaptation, userNotes);

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

            var error = PlanValidator.Validate(result.ToolInput, startDate, weeks);
            if (error is not null)
            {
                lastError = error;
                continue;
            }

            await _db.Plans.UpdateManyAsync(
                p => p.UserId == user.Id && p.Status == "active",
                Builders<PlanDoc>.Update.Set(p => p.Status, "archived"),
                cancellationToken: ct);

            var doc = new PlanDoc
            {
                UserId = user.Id,
                StartDate = startDate,
                Weeks = weeks,
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

        var today = await _db.Usage.CountDocumentsAsync(u => u.UserId == userId && u.At >= dayStart, cancellationToken: ct);
        if (today >= _options.AiMaxCallsPerDay)
            throw new ApiException(429, $"Tageslimit für KI-Aufrufe erreicht ({_options.AiMaxCallsPerDay}).");

        var month = await _db.Usage.CountDocumentsAsync(u => u.UserId == userId && u.At >= monthStart, cancellationToken: ct);
        if (month >= _options.AiMaxCallsPerMonth)
            throw new ApiException(429, $"Monatslimit für KI-Aufrufe erreicht ({_options.AiMaxCallsPerMonth}).");
    }
}
