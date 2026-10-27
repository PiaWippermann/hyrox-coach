# Hyrox Coach

Private Trainings-App für zwei Nutzer: Anamnese → KI-Trainingsplan (2 bis 4 Wochen) → Training starten (Gym oder Zuhause) → Fortschritt → Folgeplan.

```
contracts/   Plan-Schema (JSON Schema) und Beispielplan = Vertrag zwischen App, Backend und KI
docs/api.md  API-Beschreibung
backend/     ASP.NET Core 8 + MongoDB (Docker)
app/         Flutter-App (iOS + Android)
tools/       Mock-Server (Node) und Smoke-Test, laufen ohne Docker, ohne MongoDB, ohne API-Key
```

## Schnellstart auf dem Mac

```bash
cd ~/Documents/hyrox-coach
bash setup-mac.sh
```

Das Skript prüft Flutter, Docker und Node, legt `.env` mit zufälligem `ADMIN_KEY` an, initialisiert Git, führt `flutter create` aus (inkl. Android-/iOS-Netzwerkeinstellungen) und zeigt die nächsten Schritte. Es wurde noch nie auf einem Mac ausgeführt.

## Stand

| Teil | Status |
|---|---|
| Plan-Schema, API-Vertrag | fertig |
| Mock-Server + Smoke-Test | läuft, alle Tests grün |
| Backend (C#) | geschrieben, **noch nie kompiliert** |
| Flutter-App | geschrieben, **noch nie kompiliert** |
| Echter KI-Aufruf | **noch nie ausgeführt** |
| Automatischer Hyrox-Ergebnisabruf, Apple Health | Phase 2, nicht enthalten |

Rechne beim ersten Build mit ein paar Compilerfehlern. Schick sie mir, ich korrigiere.

## 1. Schnelltest ohne alles (Mock-Server, 1 Minute)

Braucht nur Node.js.

```bash
cd tools
npm install
npm run mock                      # Terminal 1: läuft auf http://localhost:8080
ADMIN_KEY=dev-admin npm run smoke # Terminal 2: prüft den gesamten API-Ablauf
```

Der Mock erzeugt Beispielpläne ohne KI. Damit kannst du die App entwickeln, ohne Geld auszugeben.

## 2. Backend mit MongoDB (Docker)

```bash
cp .env.example .env
# .env bearbeiten: ADMIN_KEY (langer Zufallswert) und ANTHROPIC_API_KEY eintragen
docker compose up --build
```

Nutzer anlegen (einmal pro Person, den Code gut aufheben, er wird nur einmal angezeigt):

```bash
curl -X POST http://localhost:8080/admin/users \
  -H "Content-Type: application/json" -H "X-Admin-Key: <dein ADMIN_KEY>" \
  -d '{"name":"Pia"}'
```

Test gegen das echte Backend (ohne KI-Kosten):

```bash
cd tools
BASE_URL=http://localhost:8080 ADMIN_KEY=<dein ADMIN_KEY> SKIP_AI=1 npm run smoke
```

Ohne `SKIP_AI=1` löst der Test zwei echte KI-Aufrufe aus (ca. 0,20 $ je Aufruf, grobe Schätzung). Das ist der erste echte Test der Plan-Erzeugung.

Ohne Docker: .NET 8 SDK und eine laufende MongoDB, dann `cd backend/HyroxCoach.Api && dotnet run` (Umgebungsvariablen wie in `.env.example`; die `.env` wird nur von Docker Compose gelesen).

## 3. Flutter-App

Voraussetzung: Flutter SDK 3.22 oder neuer. Für iOS zusätzlich Xcode.

```bash
cd app
git init && git add -A && git commit -m "vor flutter create"   # damit du sehen kannst, was flutter create ändert
flutter create --project-name hyrox_coach --platforms=android,ios .
flutter pub get
flutter run
```

Backend-Adresse im Login-Screen:

| Gerät | Adresse |
|---|---|
| Android-Emulator | `http://10.0.2.2:8080` |
| iOS-Simulator | `http://localhost:8080` |
| echtes Handy im WLAN | `http://<IP deines Rechners>:8080` |

Klartext-HTTP (nur für lokale Tests, mit gehostetem Backend nimmst du HTTPS):
- Android: in `android/app/src/main/AndroidManifest.xml` im `<application>`-Tag `android:usesCleartextTraffic="true"` ergänzen, und im Manifest `<uses-permission android:name="android.permission.INTERNET"/>`, sonst hat ein Release-Build kein Internet.
- iOS: in `ios/Runner/Info.plist` eine App-Transport-Security-Ausnahme eintragen (`NSAppTransportSecurity` → `NSAllowsLocalNetworking` = true).

Auf dem Handy installieren: iPhone per Xcode (Signing-Team wählen, mit kostenlosem Account läuft die App 7 Tage), Android per `flutter build apk` und APK installieren.

## 4. Wie die KI sparsam genutzt wird

- KI nur bei `POST /api/plans/generate` und `POST /api/plans/adapt`. Alles andere (Fokus-Vorschlag, Fortschritt, Statistiken) rechnet das Backend ohne KI.
- Jeder Trainingstag enthält Gym- und Home-Variante, die Wahl beim Start kostet nichts.
- Die Anpassung schickt nur eine Zusammenfassung (Umsetzungsquote, RPE, Gewichtsverlauf), keine Rohdaten.
- Limits pro Nutzer in `.env`: `AI_MAX_CALLS_PER_DAY`, `AI_MAX_CALLS_PER_MONTH`.
- Zusätzlich: nur wenig Guthaben in der Anthropic Console kaufen, Auto-Reload aus.

## 5. Bekannte Schwächen und offene Punkte

- **Länge der KI-Antwort:** Ein 4-Wochen-Plan mit Gym- und Home-Variante an vielen Tagen ist groß. Wird die Antwort abgeschnitten (`max_tokens`), versucht das Backend es einmal neu (zweiter Aufruf, doppelte Kosten). Wenn das bei dir auftritt: `PLAN_MAX_TOKENS` erhöhen oder 2 bis 3 Wochen wählen.
- **Hyrox-Ergebnisse** werden vorerst manuell eingetragen. Ein automatischer Abruf müsste zuerst auf technische Machbarkeit und Nutzungsbedingungen geprüft werden.
- **Ergebnis in der Anamnese:** Wer nach dem Speichern zurückgeht und die Splits ändert, speichert damit kein zweites Ergebnis (Duplikatschutz). Korrektur geht über einen neuen Durchlauf bzw. später über eine Ergebnisverwaltung.
- **Sicherheit:** Der Einladungscode ist der einzige Schutz. Im Internet unbedingt HTTPS davor setzen (Reverse Proxy oder Load Balancer). Der Einladungscode liegt in der App im Secure Storage.
- **Gesundheitsdaten:** Das Feld "Einschränkungen" geht im Klartext an die Claude API. Nur eintragen, was für den Plan nötig ist.
- Es gibt noch keine automatisierten Tests für C# und Flutter, nur den Smoke-Test.
