using MongoDB.Bson.Serialization.Attributes;

namespace HyroxCoach.Api.Domain;

// Bewusst einfache Klassen: dieselben Typen werden für die JSON-API und für MongoDB verwendet.
// Werte mit festen Optionen (Modus, Ort, Kategorie ...) sind Strings, damit nichts an Enum-Konvertern hängt.

[BsonIgnoreExtraElements]
public sealed class User
{
    [BsonId] public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "";
    public string NameKey { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public sealed class ProfileInfo
{
    public int? Age { get; set; }
    public int? HeightCm { get; set; }
    public double? WeightKg { get; set; }
    public string? Sex { get; set; }
}

public sealed class GoalInfo
{
    public string? RaceDate { get; set; }          // yyyy-MM-dd
    public string Category { get; set; } = "single"; // single | doubles | relay
    public string? Division { get; set; }          // z. B. Open, Pro, Altersklasse
    public string? TargetTime { get; set; }        // z. B. 1:25:00
    public string Priority { get; set; } = "improve"; // finish | improve | podium
    public string? PartnerName { get; set; }
}

public sealed class SelfAssessment
{
    public double? RunWeeklyKm { get; set; }
    public string? Run5kTime { get; set; }
    public string? Run10kTime { get; set; }
    public string StrengthExperience { get; set; } = "some"; // none | some | regular | advanced
    public string RunnerType { get; set; } = "balanced";     // strong_runner | balanced | weak_runner
    // Schlüssel: running, strength, endurance, skierg, sled_push, sled_pull,
    // burpee_broad_jump, rowing, farmers_carry, sandbag_lunges, wall_balls; Wert 1-5
    public Dictionary<string, int> Ratings { get; set; } = new();
    public string? Limiter { get; set; } // Freitext: wo geht im Rennen die Luft aus?
}

public sealed class DayPreference
{
    public int Weekday { get; set; }            // 1 = Montag ... 7 = Sonntag
    public string Mode { get; set; } = "ask";   // gym | home | ask (erst am Tag entscheiden)
    public int MaxDurationMin { get; set; } = 60;
}

public sealed class ScheduleInfo
{
    public int DaysPerWeek { get; set; } = 4;
    public List<DayPreference> Days { get; set; } = new(); // nur Trainingstage
    public string? OtherSports { get; set; }
}

public sealed class EquipmentInfo
{
    public List<string> Home { get; set; } = new();
    public List<string> Gym { get; set; } = new();
}

[BsonIgnoreExtraElements]
public sealed class Anamnese
{
    [BsonId] public string UserId { get; set; } = "";
    public ProfileInfo Profile { get; set; } = new();
    public GoalInfo Goal { get; set; } = new();
    public SelfAssessment SelfAssessment { get; set; } = new();
    public ScheduleInfo Schedule { get; set; } = new();
    public EquipmentInfo Equipment { get; set; } = new();
    public string? Restrictions { get; set; }
    public List<string> FocusChosen { get; set; } = new();
    public bool FocusConfirmed { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

[BsonIgnoreExtraElements]
public sealed class HyroxResult
{
    [BsonId] public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string UserId { get; set; } = "";
    public string? EventName { get; set; }
    public string Date { get; set; } = "";        // yyyy-MM-dd
    public string? Category { get; set; }
    public int TotalTimeSec { get; set; }
    public List<int> RunsSec { get; set; } = new();     // 8 Läufe
    public List<int> StationsSec { get; set; } = new(); // 8 Stationen
    public int? RoxzoneSec { get; set; }
    public string Source { get; set; } = "manual";      // manual | import
}

[BsonIgnoreExtraElements]
public sealed class PlanDoc
{
    [BsonId] public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string UserId { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string StartDate { get; set; } = "";
    public int Weeks { get; set; }
    public string Status { get; set; } = "active"; // active | archived
    public string Kind { get; set; } = "initial";  // initial | adapted
    public string PlanJson { get; set; } = "{}";   // validierter Plan laut contracts/plan.schema.json
    public string Model { get; set; } = "";
}

public sealed class LoggedSet
{
    public int? Reps { get; set; }
    public double? LoadKg { get; set; }
    public double? DistanceM { get; set; }
    public int? DurationSec { get; set; }
}

public sealed class LoggedExercise
{
    public string Name { get; set; } = "";
    public string? Station { get; set; }
    public bool Skipped { get; set; }
    public List<LoggedSet> Sets { get; set; } = new();
}

[BsonIgnoreExtraElements]
public sealed class WorkoutLog
{
    [BsonId] public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string UserId { get; set; } = "";
    public string Date { get; set; } = "";          // yyyy-MM-dd
    public string? PlanId { get; set; }
    public string? DayTitle { get; set; }
    public string Location { get; set; } = "gym";   // gym | home
    public DateTime? StartedAt { get; set; }
    public DateTime? FinishedAt { get; set; }
    public int? DurationMin { get; set; }
    public int? Rpe { get; set; }                   // 1-10
    public string? Notes { get; set; }
    public List<LoggedExercise> Exercises { get; set; } = new();
}

[BsonIgnoreExtraElements]
public sealed class AiUsage
{
    [BsonId] public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string UserId { get; set; } = "";
    public DateTime At { get; set; } = DateTime.UtcNow;
    public string Kind { get; set; } = "";
    public string Model { get; set; } = "";
    public int InputTokens { get; set; }
    public int OutputTokens { get; set; }
}

// Request-Typen
public sealed record CreateUserRequest(string Name);
public sealed record LoginRequest(string Name, string Code);
public sealed record GeneratePlanRequest(string StartDate, int Weeks);
public sealed record AdaptPlanRequest(string StartDate, int Weeks, string? Notes);

public sealed class ApiException : Exception
{
    public int Status { get; }
    public ApiException(int status, string message) : base(message) { Status = status; }
}
