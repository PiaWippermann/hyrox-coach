# API-Vertrag (v0)

Basis: `http://<host>:8080`. JSON, camelCase. Datumsformat überall `yyyy-MM-dd`.
Fehler: `{ "error": "Text" }` mit passendem HTTP-Status.

## Authentifizierung
- Nutzer werden vom Admin angelegt (`POST /admin/users`, Header `X-Admin-Key`). Antwort enthält einmalig den **Einladungscode**.
- Die App fragt Name + Code ab und ruft `POST /auth/login` auf.
- Alle `/api/*`-Endpunkte erwarten `Authorization: Bearer <code>`.
- Der Code wird nur als SHA-256-Hash gespeichert.

## Endpunkte
| Methode | Pfad | Zweck |
|---|---|---|
| GET | /health | Lebenszeichen (ohne Auth) |
| POST | /admin/users | Nutzer anlegen `{name}` → `{userId, name, code}` |
| POST | /auth/login | `{name, code}` → `{userId, name, hasAnamnese, hasPlan}` |
| GET / PUT | /api/anamnese | Anamnese lesen / speichern (Upsert) |
| POST | /api/anamnese/extract | `{images:[{mediaType, data(base64)}]}` (max. 4) → erkannte Werte zum Vorbefüllen, wird **nicht** gespeichert (**1 KI-Aufruf**, Chat-Tageslimit) |
| GET | /api/anamnese/suggestions | Regelbasierter Fokus-Vorschlag, **ohne KI** |
| GET / POST | /api/results | Hyrox-Ergebnisse (manuell erfasst) |
| DELETE | /api/results/{id} | Ergebnis löschen |
| POST | /api/plans/generate | `{}` → Erstplan ab nächstem Montag, Länge aus dem Ziel (`startDate`/`weeks` optional) (**1 KI-Aufruf**) |
| POST | /api/plans/adapt | `{notes?, startNow?}` → nächster Block im Anschluss (Status `upcoming`) oder ab dieser Woche (**1 KI-Aufruf**) |
| GET | /api/plans/current | Aktiver Plan, dazu `upcoming` (Folgeblock oder null); aktiviert fällige Folgeblöcke |
| GET | /api/plans/chat | Coach-Chat-Verlauf zum aktiven Plan `{planId, messages[]}` |
| POST | /api/plans/chat | `{message}` → `{reply, planChanged, plan?}`; der Coach kann einzelne Tage ersetzen (**1 KI-Aufruf**, eigenes Tageslimit) |
| GET / POST | /api/plans/checkin | Status `{lastCheckinAt, planCreatedAt}` / Zwei-Wochen-Check-in starten (Antwort im Coach-Chat, **1 KI-Aufruf**) |
| POST | /api/workouts | Absolviertes Training protokollieren (`location` gym/home/other, `fixed` = abgehakter fester Termin, `dayType`) |
| GET | /api/workouts?from=&to= | Protokolle |
| DELETE | /api/workouts/{id} | Protokoll löschen (z. B. Häkchen bei festem Termin entfernen) |
| POST | /api/workouts/{id}/feedback | Kurzes Coach-Feedback, wird gespeichert (**1 KI-Aufruf** beim ersten Abruf) |
| POST | /api/workouts/import | Trainings aus Apple Health / Health Connect zusammenführen (ohne KI), siehe `HealthImportService` |
| GET | /api/progress | Auswertung ohne KI |
| GET | /api/usage | KI-Aufrufe und Tokenverbrauch |

## KI-Nutzung
`plans/generate`, `plans/adapt` und `plans/chat` rufen Claude auf. Pro Nutzer gelten Tages- und Monatslimits (`.env`);
Chat, Bildauswertung, Check-in und Trainings-Feedback zählen gemeinsam getrennt davon (`AI_MAX_CHAT_PER_DAY`, Standard 40).

## Blöcke
Pläne entstehen in Blöcken von 2–4 Wochen (`BlockPlanner`): 4 Wochen, oder so, dass ein Block mit dem Peak (A-Rennen
bzw. Horizont) endet. `AutoBlockService` erstellt 3 Tage vor Blockende automatisch den Folgeblock (`kind: adapted`,
`status: upcoming`) und aktiviert ihn am Starttag. Zeitzone für „heute“: `APP_TIME_ZONE` (Standard Europe/Berlin).

## Ziele und Rennen
`anamnese.goal.mode`: `race` (Liste `goal.races` mit Priorität A/B/C), `horizon` (`goal.horizonDate` = Bestform-Zeitpunkt)
oder `open` (progressiver Aufbau ohne Zeitziel). Renntage im Plan haben `dayType: "race"`. Benchmark-Tests sind Übungen mit
`benchmark: true`.
Der Plan enthält pro Trainingstag Varianten für `gym` und/oder `home`; die Auswahl beim Trainingsstart braucht keinen weiteren KI-Aufruf.

## Plan
Siehe `contracts/plan.schema.json` und `contracts/examples/plan.example.json`.
