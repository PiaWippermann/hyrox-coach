using System.Globalization;
using System.Text.Json.Nodes;
using HyroxCoach.Api.Data;
using HyroxCoach.Api.Domain;
using MongoDB.Driver;

namespace HyroxCoach.Api.Services;

/// <summary>Ein Training aus Apple Health / Health Connect, wie es die App liefert.</summary>
public sealed record HealthWorkout(
    string ExternalId, string ActivityType, DateTime Start, DateTime End,
    double? DistanceM, int? Calories, int? AvgHr, int? MaxHr, string? SourceName,
    string LocalDate, string LocalTime); // Ortszeit des Geräts (yyyy-MM-dd, HH:mm) – der Server läuft in UTC

public sealed record HealthImportRequest(List<HealthWorkout> Workouts);

/// <summary>
/// Führt Watch-Trainings mit Plan und Protokollen zusammen:
/// 1. schon in der App protokolliert (Zeitfenster überschneidet sich) → Puls, Kalorien, Distanz anhängen;
/// 2. passt zu einem festen Termin (±90 Min, passende Art) → Termin abhaken;
/// 3. passt zu einer geplanten Einheit am selben Tag → als erledigt protokollieren;
/// 4. sonst eigener Eintrag „… (Watch)“.
/// </summary>
public sealed class HealthImportService
{
    private readonly MongoContext _db;

    public HealthImportService(MongoContext db) => _db = db;

    /// <summary>Health-Aktivitätstyp → dayType des Plans.</summary>
    public static string MapType(string activity) => activity switch
    {
        "RUNNING" or "RUNNING_TREADMILL" or "WALKING" or "HIKING" => "run",
        "TRADITIONAL_STRENGTH_TRAINING" or "FUNCTIONAL_STRENGTH_TRAINING" or "STRENGTH_TRAINING" or "CORE_TRAINING"
            or "WEIGHTLIFTING" => "strength",
        "HIGH_INTENSITY_INTERVAL_TRAINING" or "CROSS_TRAINING" or "MIXED_CARDIO" or "BOOT_CAMP" => "hyrox_sim",
        "YOGA" or "PILATES" or "FLEXIBILITY" or "MIND_AND_BODY" or "COOLDOWN" or "STRETCHING" => "recovery",
        _ => "mixed"
    };

    private static readonly Dictionary<string, string> TypeLabels = new()
    {
        ["run"] = "Laufen", ["strength"] = "Krafttraining", ["hyrox_sim"] = "Hyrox/HIIT", ["recovery"] = "Yoga/Mobility",
        ["mixed"] = "Training"
    };

    /// <summary>Passen zwei Arten grob zusammen? Ein Hyrox-Training wird z. B. oft als HIIT oder Krafttraining aufgezeichnet.</summary>
    private static bool Compatible(string planned, string recorded) => planned == recorded || (planned, recorded) switch
    {
        ("hyrox_sim", "strength") or ("hyrox_sim", "mixed") or ("mixed", _) or (_, "mixed") => true,
        ("strength", "hyrox_sim") => true,
        _ => false
    };

    /// <summary>RPE aus dem Puls schätzen, wenn keiner eingegeben wurde (% der maximalen Herzfrequenz).</summary>
    public static int? EstimateRpe(int? avgHr, int? age)
    {
        if (avgHr is null) return null;
        var pct = avgHr.Value / (double)(220 - (age ?? 30));
        return pct switch { < 0.6 => 3, < 0.7 => 4, < 0.8 => 6, < 0.87 => 7, < 0.93 => 8, _ => 9 };
    }

    public async Task<object> ImportAsync(User user, HealthImportRequest req, CancellationToken ct)
    {
        var incoming = (req.Workouts ?? new())
            .Where(w => !string.IsNullOrEmpty(w.ExternalId) && w.End > w.Start && DateOnly.TryParseExact(w.LocalDate, "yyyy-MM-dd", out _))
            .ToList();
        if (incoming.Count == 0) return new { merged = 0, created = 0, skipped = 0 };

        var ids = incoming.Select(w => w.ExternalId).ToList();
        var known = (await _db.Workouts.Find(w => w.UserId == user.Id && w.ExternalId != null && ids.Contains(w.ExternalId!))
            .Project(w => w.ExternalId).ToListAsync(ct)).ToHashSet();

        var anamnese = await _db.Anamneses.Find(a => a.UserId == user.Id).FirstOrDefaultAsync(ct);
        var plan = await _db.Plans.Find(p => p.UserId == user.Id && p.Status == "active")
            .SortByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct);
        var planDays = new Dictionary<string, List<JsonNode>>();
        if (plan is not null)
        {
            foreach (var day in JsonNode.Parse(plan.PlanJson)!["weeks"]!.AsArray().SelectMany(w => w!["days"]!.AsArray()))
            {
                var date = day!["date"]!.GetValue<string>();
                if (day["dayType"]?.GetValue<string>() is "rest" or "race") continue;
                (planDays.TryGetValue(date, out var l) ? l : planDays[date] = new()).Add(day);
            }
        }

        int merged = 0, created = 0, skipped = 0;
        foreach (var hw in incoming.OrderBy(w => w.Start))
        {
            if (known.Contains(hw.ExternalId)) { skipped++; continue; }

            var date = hw.LocalDate;
            var localTime = TimeSpan.TryParse(hw.LocalTime, CultureInfo.InvariantCulture, out var lt) ? lt : TimeSpan.Zero;
            var type = MapType(hw.ActivityType);
            var minutes = (int)Math.Round((hw.End - hw.Start).TotalMinutes);
            var dayLogs = await _db.Workouts.Find(w => w.UserId == user.Id && w.Date == date).ToListAsync(ct);

            // 1. Schon in der App erfasst: Zeitfenster überschneidet sich und noch keine Health-Daten angehängt
            var appLog = dayLogs.FirstOrDefault(l => l.ExternalId is null && !l.Fixed && l.StartedAt.HasValue &&
                l.StartedAt.Value < hw.End.AddMinutes(15) && (l.FinishedAt ?? l.StartedAt.Value.AddMinutes(l.DurationMin ?? 60)) > hw.Start.AddMinutes(-15));
            if (appLog is not null)
            {
                var upd = Builders<WorkoutLog>.Update
                    .Set(w => w.ExternalId, hw.ExternalId)
                    .Set(w => w.AvgHr, hw.AvgHr)
                    .Set(w => w.MaxHr, hw.MaxHr)
                    .Set(w => w.Calories, hw.Calories)
                    .Set(w => w.DistanceM, hw.DistanceM);
                if (appLog.Rpe is null) upd = upd.Set(w => w.Rpe, EstimateRpe(hw.AvgHr, anamnese?.Profile.Age));
                await _db.Workouts.UpdateOneAsync(w => w.Id == appLog.Id, upd, cancellationToken: ct);
                merged++;
                continue;
            }

            var log = new WorkoutLog
            {
                UserId = user.Id, Date = date, Location = "other", Source = "health", ExternalId = hw.ExternalId,
                StartedAt = hw.Start, FinishedAt = hw.End, DurationMin = minutes, DayType = type,
                AvgHr = hw.AvgHr, MaxHr = hw.MaxHr, Calories = hw.Calories, DistanceM = hw.DistanceM,
                Rpe = EstimateRpe(hw.AvgHr, anamnese?.Profile.Age),
                Notes = hw.SourceName is null ? null : $"Aufgezeichnet mit {hw.SourceName}"
            };
            if (type == "run" && hw.DistanceM is > 0)
            {
                log.Exercises.Add(new LoggedExercise
                {
                    Name = "Lauf (Watch)", Station = "run",
                    Sets = { new LoggedSet { DistanceM = hw.DistanceM, DurationSec = (int)(hw.End - hw.Start).TotalSeconds } }
                });
            }

            // 2. Fester Termin zur passenden Zeit
            var weekday = DateOnly.TryParseExact(date, "yyyy-MM-dd", out var d) ? ((int)d.DayOfWeek + 6) % 7 + 1 : 0;
            var fixedSession = anamnese?.Schedule.FixedSessions.FirstOrDefault(f =>
                f.Weekday == weekday && Compatible(f.DayType, type) &&
                TimeSpan.TryParse(f.Time, CultureInfo.InvariantCulture, out var t) &&
                Math.Abs((localTime - t).TotalMinutes) <= 90 &&
                !dayLogs.Any(l => l.Fixed && l.DayTitle == f.Title));
            if (fixedSession is not null)
            {
                log.Fixed = true;
                log.DayTitle = fixedSession.Title;
                log.DayType = fixedSession.DayType;
            }
            else
            {
                // 3. Geplante, noch offene Einheit am selben Tag
                var planned = planDays.GetValueOrDefault(date)?.FirstOrDefault(d =>
                    Compatible(d["dayType"]!.GetValue<string>(), type) &&
                    !dayLogs.Any(l => !l.Fixed && l.DayTitle == d["title"]!.GetValue<string>()));
                if (planned is not null)
                {
                    log.PlanId = plan!.Id;
                    log.DayTitle = planned["title"]!.GetValue<string>();
                    log.DayType = planned["dayType"]!.GetValue<string>();
                }
                else
                {
                    // 4. Zusatztraining
                    log.DayTitle = $"{TypeLabels.GetValueOrDefault(type, "Training")} (Watch)";
                }
            }

            await _db.Workouts.InsertOneAsync(log, cancellationToken: ct);
            created++;
        }

        return new { merged, created, skipped };
    }
}
