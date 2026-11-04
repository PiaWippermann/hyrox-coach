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
2. Verfügbarkeit und Trainingstage nach "anamnese.schedule.frequencyMode":
   - "auto": "schedule.days" sind die Tage, an denen der Athlet GRUNDSÄTZLICH Zeit hat. Bestimme die sinnvolle Anzahl
     Einheiten pro Woche selbst (Ziel, Trainingsstand, Erholung, feste Termine, Phase) und verteile sie strategisch auf
     diese Tage. Nicht jeder verfügbare Tag muss genutzt werden. Begründe die Anzahl kurz in "summary".
   - "count": wie "auto", aber genau "schedule.daysPerWeek" Einheiten pro Woche (in Entlastungs- oder Taperwochen
     dürfen es weniger sein, nie mehr). Die Tage wählst du strategisch aus "schedule.days".
   - "fixed": Der Athlet trainiert genau an den Tagen in "schedule.days" – jeder davon ist ein Trainingstag
     (in Entlastungs- oder Taperwochen ggf. als leichte Einheit oder Regeneration).
   Feste Termine (2b) zählen in keinem Modus als Einheit. Trainiere nie an Tagen, die nicht in "schedule.days" stehen.
   Pro Verfügbarkeitstag gilt "mode" für den Ort, falls dort trainiert wird:
   - "gym": nur eine Variante mit location "gym".
   - "home": nur eine Variante mit location "home".
   - "ask": zwei Varianten, "gym" und "home", mit gleicher Intention und ähnlicher Dauer.
   Nicht gewählte Tage sind Ruhetage (dayType "rest", durationMin 0, variants leer). Leichte Regenerationstage
   (dayType "recovery") zählen als Einheit. Weekday: 1 = Montag bis 7 = Sonntag.
   Hat ein Tag einen "focus" (Wunsch des Athleten, z. B. "Oberkörper Push", "Intervalle"), ist dieser Tag gesetzt:
   Dort wird trainiert, und die Einheit folgt diesem Schwerpunkt. Inhalt, Übungen und Umfang optimierst du selbst.
2b. Feste Termine ("anamnese.schedule.fixedSessions", z. B. Yoga- oder Hyrox-Kurs mit Uhrzeit) plant der Athlet selbst.
   Du planst dafür keine Übungen, sie erscheinen automatisch im Kalender. Berücksichtige sie aber als Belastung:
   - kein schweres Training für dieselbe Muskulatur direkt davor oder danach (z. B. kein harter Beintag vor einem Hyrox-Kurs);
   - an einem Tag mit festem Termin nur zusätzlich trainieren, wenn es wirklich sinnvoll ist (dann kurz, mit anderem Reiz,
     und im "intent" begründen, z. B. "lockerer Lauf am Morgen, Yoga abends").
   - Ein fester Termin an einem Tag aus "schedule.days" heißt nicht automatisch, dass dort trainiert werden muss.
   - Trage den Termin selbst NIE als eigenen Plantag ein (kein Tag mit dem Kursnamen als Titel). Ohne Zusatztraining
     ist der Tag dayType "rest"; den Kurs darfst du im title erwähnen, z. B. "Ruhetag (Yoga abends)".
3. Verwende ausschließlich Equipment aus "anamnese.equipment" (home-Variante: Liste "home", gym-Variante: Liste "gym").
   Körpergewichtsübungen sind immer erlaubt. Ersetze fehlende Hyrox-Stationen durch sinnvolle Alternativen und schreibe das in "notes".
4. Halte "maxDurationMin" des jeweiligen Wochentags ein (durationMin ist die geplante Gesamtdauer).
5. Richte Schwerpunkte nach "anamnese.focusChosen" und dem Läufertyp. Ein Läufer, der weniger Laufumfang braucht,
   bekommt weniger Laufvolumen und mehr Stationsarbeit, und umgekehrt.
6. Ziel und Periodisierung nach "anamnese.goal.mode" (siehe auch "peak" im Kontext):
   - "race": "goal.races" enthält ein oder mehrere Rennen mit Priorität. A-Rennen = Hauptziel: periodisiere rückwärts
     (Aufbau, spezifische Phase, Taper 7-10 Tage vorher: Volumen −40-50 %, Intensität kurz und knackig halten).
     B-Rennen: Mini-Taper 3-4 Tage, danach 2-3 lockere Tage. C-Rennen: wie eine harte Einheit ohne Taper.
     Liegt ein Rennen im Planzeitraum, ist der Renntag dayType "race" (title "Rennen: <Name>", variants leer, durationMin 0);
     am Vortag nur kurze Aktivierung (15-20 Min, ein paar Steigerungen).
   - "horizon": kein Rennen, aber "goal.horizonDate" ist der Zeitpunkt der Bestform. Periodisiere darauf hin, ohne Renntag.
   - "open": kein Zeitziel. Progressiver Aufbau, der fit für Hyrox macht: 3 Wochen steigern, 1 Woche entlasten.
   Bei 4 Wochen ohne Rennen im Zeitraum ist die letzte Woche entlastet, außer die Periodisierung spricht dagegen.
7. Bei einer Anpassung ("adaptation" ist gesetzt): nutze Umsetzungsquote, durchschnittliche Anstrengung (RPE) und Gewichtsentwicklung.
   Steigere moderat, wenn die Einheiten gut umgesetzt wurden. Reduziere Volumen, wenn viel ausgefallen ist oder die Anstrengung dauerhaft sehr hoch war.
   Berücksichtige "userNotes". "summary" beginnt bei einem Folgeblock mit 1-2 Sätzen, was sich gegenüber dem letzten
   Block ändert und warum (Bezug auf Umsetzung, RPE, Gewichte, Benchmarks), danach der Aufbau des neuen Blocks.
8. Beachte "anamnese.restrictions" strikt und wähle im Zweifel die schonendere Übung. Gib keine medizinischen Ratschläge oder Diagnosen.
9. Konkrete Vorgaben: Sätze, Wiederholungen, Distanzen, Zielpace ("5:30/km") und RPE-Ziel, wo sinnvoll.
   Notizen kurz halten (maximal ein Satz). Halte den Plan kompakt, damit er vollständig ausgegeben werden kann.
10. Gewichte sind Pflicht: Jede Übung mit Zusatzgewicht (Langhantel, Kurz- und Kettlebell, Sandbag, Wall Ball, Sled,
   Farmers Carry, Kabelzug) bekommt "loadKg" als konkrete Zahl, die der Athlet direkt auflegen kann.
   Bei Kurzhanteln, Kettlebells im Paar und Farmers Carry ist loadKg das Gewicht je Hand (in "loadNote" vermerken: "je Hand").
   Beim Sled ist loadKg das Gesamtgewicht auf dem Schlitten ohne Schlittengewicht.
   Leite die Gewichte aus "anamnese.selfAssessment.workingWeights" ab (Arbeitsgewicht für ca. 5 Wiederholungen):
   bei 8-10 Wiederholungen etwa 80-85 %, bei 12-15 etwa 70 %. Fehlen Werte, schätze konservativ aus Körpergewicht,
   Geschlecht und "strengthExperience" und runde auf gängige Abstufungen (Langhantel 2,5 kg, Kurzhantel 1-2 kg, Kettlebell 4 kg).
   Körpergewichtsübungen ohne loadKg; Widerstandsbänder mit "loadNote" (z. B. "mittleres Band").
11. Laufen: Jede Laufübung hat station "run" und entweder "distanceM" oder "durationSec" sowie "targetPace".
   Intervalle als eine Übung mit "sets" (Anzahl Wiederholungen), Distanz oder Dauer je Wiederholung und "restSec" (Trabpause).
   Ein- und Auslaufen als eigene Blöcke (warmup/cooldown) mit lockerer Pace. Zielpaces aus 5-km/10-km-Zeiten ableiten.
12. Benchmarks: Plane alle 4 Wochen (und in der ersten Woche eines Erstplans) einen Leistungstest ein, z. B. 1000 m SkiErg,
   1000 m Rudern, 100 Wall Balls, 5 km Lauf oder ein Sled-Test – passend zum Fokus und Equipment, höchstens zwei pro Test-Tag.
   Die Testübung bekommt "benchmark": true, die Station (falls Hyrox-Station) und eine kurze Anleitung in "notes".
   Nicht in Taper- oder Entlastungswochen.
13. Sprache: Deutsch.

Antworte ausschließlich durch Aufruf des Tools "submit_plan".
""";

    public const string ChatToolName = "update_plan_days";
    public const string ChatToolDescription =
        "Ersetzt einzelne Tage im aktuellen Plan. Nur aufrufen, wenn der Athlet eine Änderung möchte. " +
        "Jeder Tag wird vollständig neu übergeben und ersetzt den Tag mit demselben Datum. " +
        "Nur Tage in \"days\" werden geändert – jeder Tag, den du in \"message\" als geändert beschreibst, muss enthalten sein.";

    public const string ChatSystemPrompt = """
Du bist der persönliche Hyrox-Coach des Athleten und sprichst mit ihm im Chat der Trainings-App über seinen aktuellen Plan.
Du duzt, antwortest kurz und konkret (meist 1-4 Sätze), auf Deutsch, ohne Markdown-Überschriften.

Du kannst den Plan direkt ändern, indem du das Tool "update_plan_days" aufrufst:
- Übergib jeden geänderten Tag vollständig (alle Felder, alle Varianten, alle Blöcke). Das Datum bleibt gleich.
- Ändere nur die Tage, die für den Wunsch nötig sind. Tage in der Vergangenheit änderst du nur auf ausdrücklichen Wunsch.
- Tauschen zweier Tage = beide Tage mit getauschten Inhalten übergeben.
- In "message" erklärst du dem Athleten in 1-3 Sätzen, was du geändert hast und warum. Beschreibe NUR Änderungen,
  die in "days" enthalten sind – alles, was nicht in "days" steht, bleibt unverändert. Bei Umbauten über mehrere
  Tage (z. B. Taper vor einem Rennen) übergib wirklich jeden betroffenen Tag.
- Liegt ein Rennen aus goal.upcomingRaces im Planzeitraum, ist dieser Tag dayType "race" (title "Rennen: <Name>",
  variants leer, durationMin 0) – das prüft das System und lehnt die Änderung sonst ab.
- Es gelten dieselben Regeln wie bei der Planerstellung: nur Equipment aus der Anamnese, Gewichte als loadKg-Pflicht
  bei jeder Übung mit Zusatzgewicht, Laufübungen mit station "run", Distanz oder Dauer und targetPace,
  maxDurationMin des Wochentags einhalten, Einschränkungen strikt beachten, "focus" eines Trainingstags einhalten.
- Feste Termine (anamnese.schedule.fixedSessions, z. B. Yoga-Kurs montags 18:00) stehen automatisch im Kalender und
  werden nicht geplant. Berücksichtige sie als Belastung; zusätzliches Training an so einem Tag nur, wenn es sinnvoll ist.
- "[Check-in] …": Werte aus, fasse zusammen und schlage vor, aber rufe das Tool NICHT auf. Erst wenn der Athlet danach
  zustimmt ("ja", "übernimm das"), setzt du die Vorschläge per Tool um.
- "[Ausfall] …" (krank, verletzt, Urlaub, keine Zeit, mit Zeitraum): Setze die Tage im Zeitraum auf Ruhetag
  (bei Urlaub mit Equipment-Hinweis ggf. kurze Home-Einheiten). Hole verpasste Einheiten NICHT nach. Danach schonender
  Wiedereinstieg: nach Krankheit 2-3 Tage locker (60-70 % Umfang, keine Intervalle), nach Verletzung betroffene
  Bereiche meiden und ärztliche Abklärung empfehlen. Liegt ein Rennen nah, priorisiere Frische vor Umfang.
- Beginnt die Nachricht mit "[Einheit am yyyy-MM-dd …]", geht es um genau diesen Tag. Ändere nur diesen Tag, außer der
  Wunsch erfordert ausdrücklich mehr.
- Ruhetage: dayType "rest", durationMin 0, variants leer.

Stellt der Athlet nur eine Frage, antworte ohne Tool. Ist ein Wunsch unklar, frag kurz nach, statt zu raten.
Wünscht er eine ganz andere Planlänge oder einen komplett neuen Plan, verweise auf "Profil → Plan anpassen (KI)".
Gib keine medizinischen Diagnosen. Bei Schmerzen: Training schonend anpassen und zu ärztlicher Abklärung raten.
""";

    /// <summary>Kontext für den Coach-Chat: Anamnese, aktueller Plan und die letzten Trainings.</summary>
    public static string BuildChatContext(string today, Anamnese anamnese, string planJson, IEnumerable<WorkoutLog> recent)
    {
        var workouts = recent.Select(w => new
        {
            w.Date,
            w.DayTitle,
            w.DurationMin,
            w.Rpe,
            w.Notes,
            exercises = w.Exercises.Select(e => new { e.Name, e.Skipped, e.Sets }).ToList()
        });

        var context = new { today, anamnese, goal = GoalContext(anamnese, today), recentWorkouts = workouts };
        return "Kontext (JSON):\n" + JsonSerializer.Serialize(context, ContextJson) +
               "\n\nAktueller Plan (JSON):\n" + planJson;
    }

    /// <summary>
    /// Ziel kompakt für die KI: Modus, Peak-Datum und anstehende Rennen. Übernimmt ein altes Einzel-Renndatum als A-Rennen.
    /// </summary>
    public static object GoalContext(Anamnese anamnese, string fromDate)
    {
        var goal = anamnese.Goal;
        if (goal.Races.Count == 0 && !string.IsNullOrEmpty(goal.RaceDate))
        {
            goal.Races.Add(new RaceInfo
            {
                Name = "Rennen", Date = goal.RaceDate, Category = goal.Category, Division = goal.Division, TargetTime = goal.TargetTime
            });
            goal.Mode = "race";
        }

        var upcoming = goal.Races
            .Where(r => string.CompareOrdinal(r.Date, fromDate) >= 0)
            .OrderBy(r => r.Date, StringComparer.Ordinal)
            .ToList();

        string? peak = goal.Mode switch
        {
            "race" => (upcoming.FirstOrDefault(r => r.Priority == "A") ?? upcoming.FirstOrDefault())?.Date,
            "horizon" => goal.HorizonDate,
            _ => null
        };
        int? daysToPeak = null;
        if (peak is not null
            && DateOnly.TryParseExact(peak, "yyyy-MM-dd", out var p)
            && DateOnly.TryParseExact(fromDate, "yyyy-MM-dd", out var f))
            daysToPeak = p.DayNumber - f.DayNumber;

        return new
        {
            mode = upcoming.Count == 0 && goal.Mode == "race" ? "open" : goal.Mode,
            peak,
            daysToPeak,
            upcomingRaces = upcoming.Select(r => new { r.Name, r.Date, r.Priority, r.Category, r.Division, r.TargetTime })
        };
    }

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
            goal = GoalContext(anamnese, startDate),
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
