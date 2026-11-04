using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Ai;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

/// <summary>Kurzes Coach-Feedback nach einem Training: geplant gegen tatsächlich, mit einem Tipp für nächstes Mal.</summary>
public sealed class WorkoutFeedbackService
{
    private const string SystemPrompt = """
Du bist der Hyrox-Coach des Athleten und gibst direkt nach dem Training kurzes Feedback auf Deutsch, im Du.
Höchstens 3 Sätze, kein Markdown. Vergleiche geplant mit tatsächlich (Gewichte, Wiederholungen, Paces, Zeiten, RPE),
nenne eine konkrete Beobachtung, lobe Fortschritte (auch im Vergleich zu früheren Einheiten) und gib einen Tipp
für das nächste Mal. Bei sehr hohem RPE oder vielen übersprungenen Übungen: freundlich auf Erholung achten.
Keine medizinischen Diagnosen.
""";

    private readonly MongoContext _db;
    private readonly AnthropicClient _ai;
    private readonly AppOptions _options;

    public WorkoutFeedbackService(MongoContext db, AnthropicClient ai, AppOptions options)
    {
        _db = db;
        _ai = ai;
        _options = options;
    }

    public async Task<string> CreateAsync(User user, string workoutId, CancellationToken ct)
    {
        var log = await _db.Workouts.Find(w => w.Id == workoutId && w.UserId == user.Id).FirstOrDefaultAsync(ct)
                  ?? throw new ApiException(404, "Training nicht gefunden.");
        if (log.Feedback is not null) return log.Feedback;

        // Geplanter Tag aus dem Plan, zu dem das Training gehört
        JsonNode? plannedDay = null;
        if (log.PlanId is not null)
        {
            var plan = await _db.Plans.Find(p => p.Id == log.PlanId).FirstOrDefaultAsync(ct);
            if (plan is not null)
            {
                plannedDay = JsonNode.Parse(plan.PlanJson)?["weeks"]?.AsArray()
                    .SelectMany(w => w!["days"]!.AsArray())
                    .FirstOrDefault(d => d!["date"]?.GetValue<string>() == log.Date && d["title"]?.GetValue<string>() == log.DayTitle);
            }
        }

        var names = log.Exercises.Select(e => e.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var f = Builders<WorkoutLog>.Filter;
        var earlier = await _db.Workouts.Find(f.Eq(w => w.UserId, user.Id) & f.Ne(w => w.Id, log.Id) & f.Lte(w => w.Date, log.Date))
            .SortByDescending(w => w.Date).Limit(15).ToListAsync(ct);
        var history = earlier
            .SelectMany(w => w.Exercises.Where(e => !e.Skipped && names.Contains(e.Name)).Select(e => new { w.Date, e.Name, e.Sets }))
            .Take(12);

        var context = JsonSerializer.Serialize(new
        {
            planned = plannedDay,
            actual = new { log.Date, log.DayTitle, log.Location, log.DurationMin, log.Rpe, log.Notes, log.Exercises },
            earlierSameExercises = history
        });

        await PlanChatService.EnforceDailyLimitAsync(_db, _options, user.Id, ct);
        var reply = await _ai.CallAsync(
            SystemPrompt,
            new JsonArray(new JsonObject { ["role"] = "user", ["content"] = context }),
            new JsonArray(),
            2000, ct, effort: "low");

        await _db.Usage.InsertOneAsync(new AiUsage
        {
            UserId = user.Id, Kind = "feedback", Model = _options.AnthropicModel,
            InputTokens = reply.InputTokens, OutputTokens = reply.OutputTokens
        }, cancellationToken: ct);

        var feedback = reply.Text.Length > 0 ? reply.Text : "Gut gemacht – Training ist gespeichert.";
        await _db.Workouts.UpdateOneAsync(w => w.Id == log.Id, Builders<WorkoutLog>.Update.Set(w => w.Feedback, feedback),
            cancellationToken: ct);
        return feedback;
    }
}
