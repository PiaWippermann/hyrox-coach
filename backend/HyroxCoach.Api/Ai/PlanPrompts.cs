using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using HyroxCoach.Api.Domain;

namespace HyroxCoach.Api.Ai;

public static class PlanPrompts
{
    public const string ToolName = "submit_plan";
    public const string ToolDescription =
        "Gibt den fertigen Trainingsplan zurück. Muss exakt dem Schema entsprechen.";

    private static readonly JsonSerializerOptions ContextJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false
    };

    public const string SystemPrompt = """
Du bist ein erfahrener Hyrox-Coach. Du erstellst individuelle Trainingspläne für Hyrox-Athleten.

Hyrox-Format als Grundlage: 8 x 1 km Laufen, jeweils gefolgt von einer Station, in dieser Reihenfolge:
SkiErg 1000 m, Sled Push 50 m, Sled Pull 50 m, Burpee Broad Jumps 80 m, Rudern 1000 m, Farmers Carry 200 m,
Sandbag Lunges 100 m, Wall Balls (100 Wiederholungen).

Regeln für den Plan:
1. Der Plan hat genau so viele Wochen wie in "weeks" angegeben, jede Woche genau 7 Tage, lückenlos ab "startDate".
   Jeder Tag trägt sein konkretes Datum (yyyy-MM-dd). "startDate" im Plan ist exakt der übergebene Wert.
2. Trainingstage richten sich nach "anamnese.schedule.days". Pro Eintrag gilt "mode":
   - "gym": nur eine Variante mit location "gym".
   - "home": nur eine Variante mit location "home".
   - "ask": zwei Varianten, "gym" und "home", mit gleicher Intention und ähnlicher Dauer.
   Alle anderen Wochentage sind Ruhetage (dayType "rest", durationMin 0, variants leer). Optional sind
   leichte Regenerationstage (dayType "recovery") erlaubt, aber nur wenn sie nicht gegen die Anzahl der Trainingstage verstoßen.
   Weekday: 1 = Montag bis 7 = Sonntag.
3. Verwende ausschließlich Equipment aus "anamnese.equipment" (home-Variante: Liste "home", gym-Variante: Liste "gym").
   Körpergewichtsübungen sind immer erlaubt. Ersetze fehlende Hyrox-Stationen durch sinnvolle Alternativen und schreibe das in "notes".
4. Halte "maxDurationMin" des jeweiligen Wochentags ein (durationMin ist die geplante Gesamtdauer).
5. Richte Schwerpunkte nach "anamnese.focusChosen" und dem Läufertyp. Ein Läufer, der weniger Laufumfang braucht,
   bekommt weniger Laufvolumen und mehr Stationsarbeit, und umgekehrt.
6. Mit Wettkampfdatum ("goal.raceDate"): periodisiere rückwärts (Aufbau, spezifische Phase, Taper in den letzten ein bis zwei Wochen vor dem Rennen).
   Ohne Datum: solider Aufbauplan, bei 4 Wochen mit entlasteter letzter Woche.
7. Bei einer Anpassung ("adaptation" ist gesetzt): nutze Umsetzungsquote, durchschnittliche Anstrengung (RPE) und Gewichtsentwicklung.
   Steigere moderat, wenn die Einheiten gut umgesetzt wurden. Reduziere Volumen, wenn viel ausgefallen ist oder die Anstrengung dauerhaft sehr hoch war.
   Berücksichtige "userNotes".
8. Beachte "anamnese.restrictions" strikt und wähle im Zweifel die schonendere Übung. Gib keine medizinischen Ratschläge oder Diagnosen.
9. Konkrete Vorgaben: Sätze, Wiederholungen, Distanzen, Gewichte oder Zielpace ("5:30/km") und RPE-Ziel, wo sinnvoll.
   Notizen kurz halten (maximal ein Satz). Halte den Plan kompakt, damit er vollständig ausgegeben werden kann.
10. Sprache: Deutsch.

Antworte ausschließlich durch Aufruf des Tools "submit_plan".
""";

    public static string BuildUserMessage(
        string startDate,
        int weeks,
        string kind,
        Anamnese anamnese,
        HyroxResult? latestResult,
        PlanDoc? previousPlan,
        object? adaptation,
        string? userNotes)
    {
        object? previous = null;
        if (previousPlan is not null)
        {
            using var doc = JsonDocument.Parse(previousPlan.PlanJson);
            var root = doc.RootElement;
            previous = new
            {
                startDate = previousPlan.StartDate,
                weeks = previousPlan.Weeks,
                title = root.TryGetProperty("title", out var t) ? t.GetString() : null,
                focus = root.TryGetProperty("focus", out var f) && f.TryGetProperty("primary", out var p) ? p.GetString() : null
            };
        }

        var context = new
        {
            task = kind == "adapted" ? "Folgeplan nach Auswertung des letzten Blocks erstellen" : "Erstplan erstellen",
            startDate,
            weeks,
            anamnese,
            latestHyroxResult = latestResult is null ? null : new
            {
                latestResult.Date,
                latestResult.Category,
                latestResult.TotalTimeSec,
                latestResult.RunsSec,
                latestResult.StationsSec,
                latestResult.RoxzoneSec
            },
            previousPlan = previous,
            adaptation,
            userNotes
        };

        return JsonSerializer.Serialize(context, ContextJson);
    }
}
