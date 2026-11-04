using System.Text.Json;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Ai;
using HyroxCoach.Api.Config;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

public sealed record ExtractImage(string MediaType, string Data); // Data = Base64 ohne data:-Präfix
public sealed record ExtractRequest(List<ExtractImage> Images);

/// <summary>
/// Liest Werte für die Anamnese aus Screenshots (Hyrox-Ergebnisse, Lauf-Apps, Trainingslogs, Profilangaben).
/// Gibt nur zurück, was im Bild steht. Die App füllt damit die Felder vor, gespeichert wird erst nach Prüfung.
/// </summary>
public sealed class AnamneseExtractor
{
    private const string ToolName = "submit_extracted";
    private const int MaxImages = 4;
    private const int MaxImageBytes = 5 * 1024 * 1024; // Grenze der Claude API je Bild
    private static readonly HashSet<string> MediaTypes = new() { "image/jpeg", "image/png", "image/webp", "image/gif" };

    private const string SystemPrompt = """
Du liest Screenshots oder Fotos aus, die ein Hyrox-Athlet für seine Trainings-Anamnese hochlädt:
offizielle Hyrox-Ergebnisse (Splits), Lauf-Apps (Strava, Garmin, Runna, Apple Fitness), Trainingslogs (Hevy, Strong),
Profil- oder Waagenangaben, Anmeldebestätigungen für Rennen.

Rufe immer das Tool "submit_extracted" auf. Regeln:
- Trage nur Werte ein, die im Bild eindeutig zu sehen sind. Nichts schätzen, nichts aus Allgemeinwissen ergänzen.
  Felder ohne sicheren Wert lässt du weg.
- Zeiten als "mm:ss" oder "h:mm:ss". Datumsangaben als "yyyy-MM-dd".
- Hyrox-Ergebnis: runs = die 8 Laufsplits in Reihenfolge, stations = die 8 Stationen in Reihenfolge
  SkiErg, Sled Push, Sled Pull, Burpee Broad Jumps, Rudern, Farmers Carry, Sandbag Lunges, Wall Balls.
  Nur übergeben, wenn alle 8 Werte lesbar sind. Roxzone separat.
- Laufbestzeiten: run5kTime/run10kTime nur aus ausgewiesenen Bestzeiten, Rennen oder Aktivitäten über ~5 bzw. ~10 km.
  runWeeklyKm aus Wochen- oder Monatsstatistiken (Monat ÷ 4,3).
- Kraftwerte (workingWeights): Gewicht, mit dem ca. 5 saubere Wiederholungen möglich sind. Aus Logs: bei Sätzen
  mit 3-8 Wiederholungen das Arbeitsgewicht nehmen; aus 1RM-Angaben etwa 85 % davon. Schlüssel: back_squat, deadlift,
  bench_press, overhead_press, barbell_row, dumbbell (je Hand), kettlebell_swing, wall_ball.
- In "summary" schreibst du auf Deutsch in 1-3 Sätzen, was du erkannt hast und was unklar war.
""";

    private static readonly JsonNode Schema = JsonNode.Parse("""
{
  "type": "object",
  "required": ["summary"],
  "properties": {
    "summary": { "type": "string" },
    "profile": {
      "type": "object",
      "properties": {
        "age": { "type": "integer" },
        "heightCm": { "type": "integer" },
        "weightKg": { "type": "number" },
        "sex": { "type": "string", "enum": ["female", "male", "diverse"] }
      }
    },
    "goal": {
      "type": "object",
      "properties": {
        "raceDate": { "type": "string" },
        "category": { "type": "string", "enum": ["single", "doubles", "relay"] },
        "division": { "type": "string" },
        "targetTime": { "type": "string" }
      }
    },
    "selfAssessment": {
      "type": "object",
      "properties": {
        "runWeeklyKm": { "type": "number" },
        "run5kTime": { "type": "string" },
        "run10kTime": { "type": "string" },
        "workingWeights": { "type": "object", "additionalProperties": { "type": "number" } }
      }
    },
    "hyroxResult": {
      "type": "object",
      "properties": {
        "eventName": { "type": "string" },
        "date": { "type": "string" },
        "division": { "type": "string" },
        "totalTime": { "type": "string" },
        "roxzone": { "type": "string" },
        "runs": { "type": "array", "items": { "type": "string" }, "minItems": 8, "maxItems": 8 },
        "stations": { "type": "array", "items": { "type": "string" }, "minItems": 8, "maxItems": 8 }
      }
    }
  }
}
""")!;

    private readonly MongoContext _db;
    private readonly AnthropicClient _ai;
    private readonly AppOptions _options;

    public AnamneseExtractor(MongoContext db, AnthropicClient ai, AppOptions options)
    {
        _db = db;
        _ai = ai;
        _options = options;
    }

    public async Task<JsonElement> ExtractAsync(User user, ExtractRequest req, CancellationToken ct)
    {
        var images = req.Images ?? new();
        if (images.Count == 0) throw new ApiException(400, "Kein Bild übergeben.");
        if (images.Count > MaxImages) throw new ApiException(400, $"Maximal {MaxImages} Bilder auf einmal.");

        var content = new JsonArray();
        foreach (var img in images)
        {
            if (!MediaTypes.Contains(img.MediaType))
                throw new ApiException(400, "Nur JPEG, PNG, WebP oder GIF.");
            if (img.Data.Length * 3L / 4 > MaxImageBytes)
                throw new ApiException(400, "Ein Bild ist zu groß (maximal 5 MB).");
            content.Add(new JsonObject
            {
                ["type"] = "image",
                ["source"] = new JsonObject { ["type"] = "base64", ["media_type"] = img.MediaType, ["data"] = img.Data }
            });
        }
        content.Add(new JsonObject { ["type"] = "text", ["text"] = "Lies die Werte für meine Anamnese aus." });

        await PlanChatService.EnforceDailyLimitAsync(_db, _options, user.Id, ct);

        var reply = await _ai.CallAsync(
            SystemPrompt,
            new JsonArray(new JsonObject { ["role"] = "user", ["content"] = content }),
            new JsonArray(new JsonObject
            {
                ["name"] = ToolName,
                ["description"] = "Gibt die aus den Bildern gelesenen Werte zurück.",
                ["input_schema"] = Schema.DeepClone()
            }),
            8000, ct);

        await _db.Usage.InsertOneAsync(new AiUsage
        {
            UserId = user.Id,
            Kind = "extract",
            Model = _options.AnthropicModel,
            InputTokens = reply.InputTokens,
            OutputTokens = reply.OutputTokens
        }, cancellationToken: ct);

        if (reply.ToolName == ToolName && reply.ToolInput is { } input) return input;

        // Kein Tool-Aufruf: Text als Zusammenfassung zurückgeben, damit die App etwas anzeigen kann
        var text = reply.Text.Length > 0 ? reply.Text : "Im Bild wurden keine passenden Werte erkannt.";
        return JsonSerializer.SerializeToElement(new { summary = text });
    }
}
