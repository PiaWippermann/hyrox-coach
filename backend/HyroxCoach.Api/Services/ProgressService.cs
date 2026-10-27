using System.Globalization;
using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Services;

/// <summary>Auswertung des Fortschritts, komplett ohne KI.</summary>
public static class ProgressService
{
    public static object Build(IReadOnlyList<WorkoutLog> logs)
    {
        var weekly = logs
            .Select(l => (Log: l, Week: WeekStart(l.Date)))
            .Where(x => x.Week is not null)
            .GroupBy(x => x.Week!)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => new
            {
                weekStart = g.Key,
                sessions = g.Count(),
                minutes = g.Sum(x => x.Log.DurationMin ?? 0),
                avgRpe = g.Where(x => x.Log.Rpe.HasValue).Select(x => (double)x.Log.Rpe!.Value).DefaultIfEmpty().Average()
            })
            .ToList();

        var exercises = logs
            .SelectMany(l => l.Exercises.Where(e => !e.Skipped).Select(e => (l.Date, Exercise: e)))
            .GroupBy(x => x.Exercise.Name, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                var points = g
                    .OrderBy(x => x.Date, StringComparer.Ordinal)
                    .Select(x => new
                    {
                        date = x.Date,
                        topLoadKg = x.Exercise.Sets.Where(s => s.LoadKg.HasValue).Select(s => s.LoadKg!.Value).DefaultIfEmpty(0).Max(),
                        totalReps = x.Exercise.Sets.Sum(s => s.Reps ?? 0),
                        totalDistanceM = x.Exercise.Sets.Sum(s => s.DistanceM ?? 0)
                    })
                    .ToList();
                return new
                {
                    name = g.Key,
                    sessions = points.Count,
                    bestLoadKg = points.Max(p => p.topLoadKg),
                    points
                };
            })
            .OrderByDescending(e => e.sessions)
            .Take(30)
            .ToList();

        return new
        {
            totalSessions = logs.Count,
            weekly,
            exercises
        };
    }

    private static string? WeekStart(string date)
    {
        if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
            return null;
        var diff = ((int)d.DayOfWeek + 6) % 7; // Montag = 0
        return d.AddDays(-diff).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    }
}
