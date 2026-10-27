using System.Globalization;
using System.Text.Json;

namespace HyroxCoach.Api.Services;

/// <summary>
/// Strukturprüfung der KI-Antwort. Das JSON-Schema zwingt die Form, hier prüfen wir, was ein Schema nicht kann:
/// Wochenanzahl, lückenlose Datumsfolge, Varianten an Trainingstagen.
/// Spiegelbild in tools/lib/plan-checks.mjs (wird im Smoke-Test benutzt).
/// </summary>
public static class PlanValidator
{
    private static readonly HashSet<string> Locations = new() { "gym", "home" };

    public static string? Validate(JsonElement plan, string startDate, int weeks)
    {
        if (!DateOnly.TryParseExact(startDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var start))
            return "startDate ist ungültig.";

        var errors = new List<string>();

        if (!plan.TryGetProperty("startDate", out var sd) || sd.GetString() != startDate)
            errors.Add($"startDate im Plan muss {startDate} sein.");

        if (!plan.TryGetProperty("weeks", out var weekArray) || weekArray.ValueKind != JsonValueKind.Array)
            return "weeks fehlt oder ist kein Array.";

        if (weekArray.GetArrayLength() != weeks)
            errors.Add($"Es müssen genau {weeks} Wochen sein, geliefert wurden {weekArray.GetArrayLength()}.");

        var dayIndex = 0;
        var weekNo = 0;
        foreach (var week in weekArray.EnumerateArray())
        {
            weekNo++;
            if (!week.TryGetProperty("days", out var days) || days.ValueKind != JsonValueKind.Array || days.GetArrayLength() != 7)
            {
                errors.Add($"Woche {weekNo} muss genau 7 Tage haben.");
                dayIndex += 7;
                continue;
            }

            foreach (var day in days.EnumerateArray())
            {
                var expected = start.AddDays(dayIndex).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                dayIndex++;

                var date = day.TryGetProperty("date", out var d) ? d.GetString() : null;
                if (date != expected)
                    errors.Add($"Tag {dayIndex}: Datum muss {expected} sein (war {date ?? "leer"}).");

                var type = day.TryGetProperty("dayType", out var dt) ? dt.GetString() : null;
                var hasVariants = day.TryGetProperty("variants", out var variants) && variants.ValueKind == JsonValueKind.Array;

                if (type == "rest")
                    continue;

                if (!hasVariants || variants.GetArrayLength() == 0)
                {
                    errors.Add($"Tag {expected}: Trainingstag ohne Variante.");
                    continue;
                }

                foreach (var variant in variants.EnumerateArray())
                {
                    var loc = variant.TryGetProperty("location", out var l) ? l.GetString() : null;
                    if (loc is null || !Locations.Contains(loc))
                        errors.Add($"Tag {expected}: ungültiger Ort {loc ?? "leer"}.");

                    if (!variant.TryGetProperty("blocks", out var blocks) || blocks.ValueKind != JsonValueKind.Array || blocks.GetArrayLength() == 0)
                        errors.Add($"Tag {expected}: Variante {loc} ohne Blöcke.");
                }
            }
        }

        return errors.Count == 0 ? null : string.Join(" ", errors.Take(6));
    }
}
