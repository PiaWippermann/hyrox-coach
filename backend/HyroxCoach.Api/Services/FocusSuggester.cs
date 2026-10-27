using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Services;

public sealed record FocusSuggestion(string Key, string Label, string Reason, int Weight);

/// <summary>
/// Regelbasierter Fokus-Vorschlag (v0, ohne KI). Nutzt Selbsteinschätzung, Läufertyp und, falls vorhanden,
/// den Pacing-Verlauf der Läufe im letzten Hyrox-Ergebnis. Die Gewichte sind bewusst grobe Heuristik und lassen sich hier leicht anpassen.
/// </summary>
public static class FocusSuggester
{
    private static readonly Dictionary<string, string> Labels = new()
    {
        ["running"] = "Laufen",
        ["strength"] = "Kraft",
        ["endurance"] = "Grundlagenausdauer",
        ["skierg"] = "SkiErg",
        ["sled_push"] = "Sled Push",
        ["sled_pull"] = "Sled Pull",
        ["burpee_broad_jump"] = "Burpee Broad Jumps",
        ["rowing"] = "Rudern",
        ["farmers_carry"] = "Farmers Carry",
        ["sandbag_lunges"] = "Sandbag Lunges",
        ["wall_balls"] = "Wall Balls"
    };

    public static List<FocusSuggestion> Suggest(Anamnese a, HyroxResult? result)
    {
        var list = new List<FocusSuggestion>();

        foreach (var (key, rating) in a.SelfAssessment.Ratings)
        {
            if (rating <= 2 && Labels.TryGetValue(key, out var label))
            {
                list.Add(new FocusSuggestion(key, label, $"Selbsteinschätzung {rating} von 5", (3 - rating) * 10 + 10));
            }
        }

        switch (a.SelfAssessment.RunnerType)
        {
            case "strong_runner":
                list.Add(new FocusSuggestion("run_volume_low", "Laufumfang halten statt steigern, Stationen priorisieren",
                    "Du bist läuferisch stark", 15));
                break;
            case "weak_runner":
                list.Add(new FocusSuggestion("running", "Laufen und Lauftechnik", "Du schätzt dich als schwächeren Läufer ein", 25));
                break;
        }

        if (result is not null && result.RunsSec.Count >= 6)
        {
            var first = result.RunsSec.Take(3).Average();
            var last = result.RunsSec.TakeLast(3).Average();
            if (first > 0)
            {
                var drift = last / first - 1.0;
                if (drift > 0.07)
                {
                    list.Add(new FocusSuggestion("pacing", "Pacing und Laufen unter Ermüdung",
                        $"Deine letzten drei Läufe waren im Schnitt {drift * 100:0}% langsamer als die ersten drei", 25));
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(a.SelfAssessment.Limiter))
        {
            list.Add(new FocusSuggestion("limiter", $"Dein Engpass im Rennen: {a.SelfAssessment.Limiter!.Trim()}",
                "Von dir genannt", 20));
        }

        if (list.Count == 0)
        {
            list.Add(new FocusSuggestion("allround", "Allround-Vorbereitung", "Keine klare Schwäche erkennbar", 5));
        }

        return list.OrderByDescending(s => s.Weight).Take(4).ToList();
    }
}
