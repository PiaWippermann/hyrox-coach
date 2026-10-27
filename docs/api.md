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
| GET | /api/anamnese/suggestions | Regelbasierter Fokus-Vorschlag, **ohne KI** |
| GET / POST | /api/results | Hyrox-Ergebnisse (manuell erfasst) |
| DELETE | /api/results/{id} | Ergebnis löschen |
| POST | /api/plans/generate | `{startDate, weeks(2-4)}` → neuer Plan (**1 KI-Aufruf**) |
| POST | /api/plans/adapt | `{startDate, weeks, notes?}` → Folgeplan (**1 KI-Aufruf**) |
| GET | /api/plans/current | Aktiver Plan |
| POST | /api/workouts | Absolviertes Training protokollieren |
| GET | /api/workouts?from=&to= | Protokolle |
| GET | /api/progress | Auswertung ohne KI |
| GET | /api/usage | KI-Aufrufe und Tokenverbrauch |

## KI-Nutzung
Nur `plans/generate` und `plans/adapt` rufen Claude auf. Pro Nutzer gelten Tages- und Monatslimits (`.env`).
Der Plan enthält pro Trainingstag Varianten für `gym` und/oder `home`; die Auswahl beim Trainingsstart braucht keinen weiteren KI-Aufruf.

## Plan
Siehe `contracts/plan.schema.json` und `contracts/examples/plan.example.json`.
