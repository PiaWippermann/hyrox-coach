using System.Globalization;
using System.Text.Json;
using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Services;

/// <summary>
/// Verdichtet Plan und Protokolle zu einer kleinen Zusammenfassung für die Plananpassung.
/// So gehen nur wenige Token an die KI statt aller Rohdaten.
/// </summary>
public static class AdaptationSummary
{
    public static object Build(string planJson, IReadOnlyList<WorkoutLog> logs, string beforeDate)
    {
        using var doc = JsonDocument.Parse(planJson);
        var plannedDays = new List<(string Date, string Title, string Type)>();

        if (doc.RootElement.TryGetProperty("weeks", out var weeks))
        {
            foreach (var week in weeks.EnumerateArray())
            {
                if (!week.TryGetProperty("days", out var days)) continue;
                foreach (var day in days.EnumerateArray())
                {
                    var date = day.GetProperty("date").GetString() ?? "";
                    var type = day.TryGetProperty("dayType", out var t) ? t.GetString() ?? "" : "";
                    var title = day.TryGetProperty("title", out var ti) ? ti.GetString() ?? "" : "";
                    var hasVariants = day.TryGetProperty("variants", out var v) && v.GetArrayLength() > 0;
                    if (hasVariants && type != "rest" && string.CompareOrdinal(date, beforeDate) < 0)
                        plannedDays.Add((date, title, type));
                }
            }
        }

        var logDates = logs.Select(l => l.Date).ToHashSet();
        var completed = plannedDays.Count(p => logDates.Contains(p.Date));
        var missed = plannedDays.Where(p => !logDates.Contains(p.Date)).Select(p => $"{p.Date} {p.Title}").ToList();

        var rpes = logs.Where(l => l.Rpe.HasValue).Select(l => l.Rpe!.Value).ToList();

        var exercises = logs
            .SelectMany(l => l.Exercises.Where(e => !e.Skipped).Select(e => (l.Date, Exercise: e)))
            .GroupBy(x => x.Exercise.Name, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                var ordered = g.OrderBy(x => x.Date, StringComparer.Ordinal).ToList();
                double? Top(IEnumerable<LoggedSet> sets) => sets.Where(s => s.LoadKg.HasValue).Select(s => s.LoadKg).DefaultIfEmpty(null).Max();
                return new
                {
                    name = g.Key,
                    sessions = ordered.Count,
                    firstTopLoadKg = Top(ordered.First().Exercise.Sets),
                    lastTopLoadKg = Top(ordered.Last().Exercise.Sets)
                };
            })
            .Where(e => e.lastTopLoadKg.HasValue)
            .Take(25)
            .ToList();

        return new
        {
            plannedSessions = plannedDays.Count,
            completedSessions = completed,
            completionRate = plannedDays.Count == 0 ? (double?)null : Math.Round((double)completed / plannedDays.Count, 2),
            missedSessions = missed.Take(12).ToList(),
            averageRpe = rpes.Count == 0 ? (double?)null : Math.Round(rpes.Average(), 1),
            gymSessions = logs.Count(l => l.Location == "gym"),
            homeSessions = logs.Count(l => l.Location == "home"),
            exerciseProgress = exercises
        };
    }
}
