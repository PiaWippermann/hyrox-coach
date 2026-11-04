using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Ai;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

public sealed record ChatResult(ChatMessage Reply, PlanDoc Plan, bool PlanChanged);

/// <summary>
/// Coach-Chat zum aktuellen Plan. Die KI antwortet frei oder ersetzt einzelne Tage über das Tool "update_plan_days".
/// Der Plan wird in place geändert (gleiche Id), damit protokollierte Trainings ihre planId behalten.
/// </summary>
public sealed class PlanChatService
{
    private const int MaxHistory = 20;     // Nachrichten, die an die KI gehen
    private const int ChatMaxTokens = 24000;

    private static readonly JsonNode DayToolSchema = BuildToolSchema();

    private readonly MongoContext _db;
    private readonly AnthropicClient _ai;
    private readonly AppOptions _options;

    public PlanChatService(MongoContext db, AnthropicClient ai, AppOptions options)
    {
        _db = db;
        _ai = ai;
        _options = options;
    }

    private static JsonNode BuildToolSchema()
    {
        var daySchema = PlanService.LoadSchema()["properties"]!["weeks"]!["items"]!["properties"]!["days"]!["items"]!;
        return new JsonObject
        {
            ["type"] = "object",
            ["required"] = new JsonArray("message", "days"),
            ["properties"] = new JsonObject
            {
                ["message"] = new JsonObject
                {
                    ["type"] = "string",
                    ["description"] = "Kurze Erklärung an den Athleten, was geändert wurde und warum."
                },
                ["days"] = new JsonObject
                {
                    ["type"] = "array",
                    ["minItems"] = 1,
                    ["items"] = daySchema.DeepClone()
                }
            }
        };
    }

    public async Task<PlanChat> GetAsync(User user, CancellationToken ct)
    {
        var plan = await CurrentPlanAsync(user.Id, ct);
        return await _db.Chats.Find(c => c.PlanId == plan.Id).FirstOrDefaultAsync(ct)
               ?? new PlanChat { PlanId = plan.Id, UserId = user.Id };
    }

    /// <param name="displayText">Text, der im Chatverlauf statt der (ggf. langen) Nachricht an die KI gezeigt wird.</param>
    public async Task<ChatResult> SendAsync(User user, string message, CancellationToken ct, string? displayText = null)
    {
        message = (message ?? "").Trim();
        if (message.Length == 0) throw new ApiException(400, "Nachricht ist leer.");
        if (displayText is null && message.Length > 2000)
            throw new ApiException(400, "Nachricht ist zu lang (maximal 2000 Zeichen).");

        var plan = await CurrentPlanAsync(user.Id, ct);
        var anamnese = await _db.Anamneses.Find(a => a.UserId == user.Id).FirstOrDefaultAsync(ct)
                       ?? throw new ApiException(400, "Bitte zuerst die Anamnese ausfüllen.");
        var chat = await _db.Chats.Find(c => c.PlanId == plan.Id).FirstOrDefaultAsync(ct)
                   ?? new PlanChat { PlanId = plan.Id, UserId = user.Id };
        var recent = await _db.Workouts.Find(w => w.UserId == user.Id && w.PlanId == plan.Id)
            .SortByDescending(w => w.Date).Limit(10).ToListAsync(ct);

        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var system = PlanPrompts.ChatSystemPrompt + "\n\n" +
                     PlanPrompts.BuildChatContext(today, anamnese, plan.PlanJson, recent);

        var messages = new JsonArray();
        foreach (var m in chat.Messages.TakeLast(MaxHistory).SkipWhile(m => m.Role != "user"))
            messages.Add(new JsonObject { ["role"] = m.Role, ["content"] = m.Text });
        messages.Add(new JsonObject { ["role"] = "user", ["content"] = message });

        var tools = new JsonArray(new JsonObject
        {
            ["name"] = PlanPrompts.ChatToolName,
            ["description"] = PlanPrompts.ChatToolDescription,
            ["input_schema"] = DayToolSchema.DeepClone()
        });

        string? lastError = null;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            await EnforceLimitAsync(user.Id, ct);

            if (lastError is not null)
            {
                // Fehlversuch nicht in den Verlauf schreiben, nur für den zweiten Versuch mitgeben
                var retry = messages.DeepClone().AsArray();
                retry[^1] = new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = message + $"\n\n(Hinweis vom System: Deine letzte Planänderung war ungültig: {lastError} Korrigiere das.)"
                };
                messages = retry;
            }

            var reply = await _ai.CallAsync(system, messages.DeepClone().AsArray(), tools, ChatMaxTokens, ct);
            await _db.Usage.InsertOneAsync(new AiUsage
            {
                UserId = user.Id,
                Kind = "chat",
                Model = _options.AnthropicModel,
                InputTokens = reply.InputTokens,
                OutputTokens = reply.OutputTokens
            }, cancellationToken: ct);

            if (reply.StopReason == "max_tokens")
            {
                lastError = "Die Antwort wurde abgeschnitten. Ändere weniger Tage auf einmal und halte Notizen kurz.";
                continue;
            }

            if (reply.ToolName != PlanPrompts.ChatToolName || reply.ToolInput is not { } input)
            {
                var text = reply.Text.Length > 0 ? reply.Text : "Dazu kann ich gerade nichts sagen. Formulierst du es nochmal anders?";
                var answer = new ChatMessage { Role = "assistant", Text = text };
                await SaveAsync(chat, displayText ?? message, answer, ct);
                return new ChatResult(answer, plan, false);
            }

            var (newPlanJson, changed, error) = ApplyDays(plan, input, PlanValidator.RaceDays(anamnese));
            if (error is not null)
            {
                lastError = error;
                continue;
            }

            plan.PlanJson = newPlanJson!;
            plan.Revision++;
            plan.UpdatedAt = DateTime.UtcNow;
            await _db.Plans.ReplaceOneAsync(p => p.Id == plan.Id, plan, cancellationToken: ct);

            var explanation = input.TryGetProperty("message", out var msg) ? msg.GetString() ?? "" : "";
            if (explanation.Length == 0) explanation = reply.Text.Length > 0 ? reply.Text : "Plan angepasst.";
            var changedReply = new ChatMessage { Role = "assistant", Text = explanation, ChangedDates = changed };
            await SaveAsync(chat, displayText ?? message, changedReply, ct);
            return new ChatResult(changedReply, plan, true);
        }

        throw new ApiException(502, "Der Coach konnte die Änderung nicht sauber umsetzen: " + lastError);
    }

    /// <summary>
    /// Zwei-Wochen-Check-in: wertet die letzten 14 Tage aus und lässt den Coach zusammenfassen und Vorschläge machen.
    /// Geändert wird erst, wenn der Athlet im Chat zustimmt.
    /// </summary>
    public async Task<ChatResult> CheckinAsync(User user, CancellationToken ct)
    {
        var plan = await CurrentPlanAsync(user.Id, ct);
        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var from = DateTime.Now.AddDays(-14).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var f = Builders<WorkoutLog>.Filter;
        var logs = await _db.Workouts.Find(f.Eq(w => w.UserId, user.Id) & f.Gte(w => w.Date, from)).ToListAsync(ct);
        var summary = AdaptationSummary.Build(plan.PlanJson, logs, today);
        var data = JsonSerializer.Serialize(new { from, to = today, summary, fixedSessionsDone = logs.Count(l => l.Fixed) });

        var message = "[Check-in] Zwei-Wochen-Check-in. Auswertung der letzten 14 Tage (JSON): " + data +
                      "\nFasse in 3-5 kurzen Sätzen zusammen: Umsetzung, Belastung/RPE, Fortschritte (Gewichte, Benchmarks), " +
                      "Auffälligkeiten. Schlage dann 1-3 konkrete Anpassungen für die nächsten 2 Wochen vor und frag, ob du sie " +
                      "übernehmen sollst. Ändere jetzt noch nichts am Plan.";
        var result = await SendAsync(user, message, ct, displayText: "Zwei-Wochen-Check-in");

        await _db.Users.UpdateOneAsync(u => u.Id == user.Id,
            Builders<User>.Update.Set(u => u.LastCheckinAt, DateTime.UtcNow), cancellationToken: ct);
        return result;
    }

    /// <summary>Setzt die gelieferten Tage per Datum in den Plan ein und prüft den ganzen Plan danach erneut.</summary>
    private static (string? PlanJson, List<string> Changed, string? Error) ApplyDays(
        PlanDoc plan, JsonElement input, IReadOnlyDictionary<string, string> raceDays)
    {
        if (!input.TryGetProperty("days", out var days) || days.ValueKind != JsonValueKind.Array || days.GetArrayLength() == 0)
            return (null, new(), "days fehlt oder ist leer.");

        var root = JsonNode.Parse(plan.PlanJson)!;
        var index = new Dictionary<string, (JsonArray Days, int Pos)>();
        foreach (var week in root["weeks"]!.AsArray())
        {
            var weekDays = week!["days"]!.AsArray();
            for (var i = 0; i < weekDays.Count; i++)
                index[weekDays[i]!["date"]!.GetValue<string>()] = (weekDays, i);
        }

        var changed = new List<string>();
        foreach (var day in days.EnumerateArray())
        {
            var date = day.TryGetProperty("date", out var d) ? d.GetString() : null;
            if (date is null || !index.TryGetValue(date, out var slot))
                return (null, new(), $"Datum {date ?? "leer"} gehört nicht zum Plan.");
            slot.Days[slot.Pos] = JsonNode.Parse(day.GetRawText());
            changed.Add(date);
        }

        var json = root.ToJsonString();
        using var check = JsonDocument.Parse(json);
        var error = PlanValidator.Validate(check.RootElement, plan.StartDate, plan.Weeks, raceDays);
        return error is null ? (json, changed, null) : (null, new(), error);
    }

    private async Task SaveAsync(PlanChat chat, string userText, ChatMessage reply, CancellationToken ct)
    {
        chat.Messages.Add(new ChatMessage { Role = "user", Text = userText });
        chat.Messages.Add(reply);
        await _db.Chats.ReplaceOneAsync(c => c.PlanId == chat.PlanId, chat, new ReplaceOptions { IsUpsert = true }, ct);
    }

    private async Task<PlanDoc> CurrentPlanAsync(string userId, CancellationToken ct) =>
        await _db.Plans.Find(p => p.UserId == userId && p.Status == "active")
            .SortByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct)
        ?? throw new ApiException(404, "Noch kein Plan.");

    private Task EnforceLimitAsync(string userId, CancellationToken ct) => EnforceDailyLimitAsync(_db, _options, userId, ct);

    /// <summary>Tageslimit für kleine KI-Aufrufe (Coach-Chat und Bildauswertung), getrennt vom Planlimit.</summary>
    public static async Task EnforceDailyLimitAsync(MongoContext db, AppOptions options, string userId, CancellationToken ct)
    {
        var dayStart = DateTime.UtcNow.Date;
        var today = await db.Usage.CountDocumentsAsync(
            u => u.UserId == userId && (u.Kind == "chat" || u.Kind == "extract" || u.Kind == "feedback") && u.At >= dayStart, cancellationToken: ct);
        if (today >= options.AiMaxChatPerDay)
            throw new ApiException(429, $"Tageslimit für Coach-Chat und Bildauswertung erreicht ({options.AiMaxChatPerDay}).");
    }
}
