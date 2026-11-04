using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Services;

/// <summary>
/// Bestimmt Start und Länge des nächsten Trainingsblocks aus dem Ziel, statt den Nutzer danach zu fragen.
/// Blöcke sind 2-4 Wochen lang (mehr passt nicht zuverlässig in eine KI-Antwort und wäre ohnehin zu weit vorausgeplant).
/// </summary>
public static class BlockPlanner
{
    public static DateOnly Today(string timeZone)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZone);
        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz));
    }

    /// <summary>Montag der Woche von [d].</summary>
    public static DateOnly MondayOf(DateOnly d) => d.AddDays(-(((int)d.DayOfWeek + 6) % 7));

    /// <summary>Nächster Montag nach [d] (bzw. [d] selbst, wenn Montag).</summary>
    public static DateOnly NextMonday(DateOnly d) => d.DayOfWeek == DayOfWeek.Monday ? d : MondayOf(d).AddDays(7);

    /// <summary>Peak-Datum: nächstes A-Rennen (sonst nächstes Rennen) bzw. Horizont; null bei offenem Ziel.</summary>
    public static DateOnly? Peak(Anamnese anamnese, DateOnly from)
    {
        var goal = anamnese.Goal;
        var raceDates = goal.Races
            .Select(r => (r.Priority, Ok: DateOnly.TryParseExact(r.Date, "yyyy-MM-dd", out var d), Date: d))
            .Where(r => r.Ok && r.Date >= from)
            .OrderBy(r => r.Date)
            .ToList();
        if (raceDates.Count == 0 && DateOnly.TryParseExact(goal.RaceDate, "yyyy-MM-dd", out var legacy) && legacy >= from)
            return legacy;

        return goal.Mode switch
        {
            "race" when raceDates.Count > 0 => (raceDates.FirstOrDefault(r => r.Priority == "A").Ok
                ? raceDates.First(r => r.Priority == "A").Date
                : raceDates[0].Date),
            "horizon" when DateOnly.TryParseExact(goal.HorizonDate, "yyyy-MM-dd", out var h) && h >= from => h,
            _ => null
        };
    }

    /// <summary>
    /// Blocklänge so, dass ein Block mit der Peak-Woche endet: bis 4 Wochen direkt, 5 → 3+2, 6 → 4+2, 7 → 4+3, sonst 4.
    /// </summary>
    public static int Weeks(DateOnly start, DateOnly? peak)
    {
        if (peak is null) return 4;
        var weeksToPeak = (peak.Value.DayNumber - start.DayNumber) / 7 + 1; // Woche, in der der Peak liegt
        return weeksToPeak switch
        {
            <= 1 => 2, // Rennen in dieser Woche: Rennen + Erholungswoche
            <= 4 => weeksToPeak,
            5 => 3,
            _ => 4
        };
    }
}
