#!/usr/bin/env bash
# Richtet das Projekt auf dem Mac ein. Start im Projektordner:  bash setup-mac.sh
# Das Skript ist idempotent (mehrfach ausführbar) und fragt vor jeder Installation nach.
# HINWEIS: Dieses Skript wurde noch nie auf einem Mac ausgeführt. Bei Fehlern: Ausgabe an Claude schicken.
set -euo pipefail
cd "$(dirname "$0")"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    ok: %s\n' "$*"; }
warn() { printf '    \033[33mhinweis:\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask()  { local a; read -r -p "    $1 [j/N] " a; [[ "$a" == "j" || "$a" == "J" ]]; }

say "1/6 Voraussetzungen prüfen"
if ! have brew; then
  echo "    Homebrew fehlt. Installation: https://brew.sh (dort den Befehl kopieren), danach dieses Skript neu starten."
  exit 1
fi
ok "Homebrew"

if have node; then ok "Node $(node -v)"; else
  ask "Node.js fehlt (für Mock-Server und Smoke-Test). Mit Homebrew installieren?" && brew install node
fi

if have flutter; then ok "Flutter $(flutter --version 2>/dev/null | head -1)"; else
  if ask "Flutter fehlt. Mit Homebrew installieren (brew install --cask flutter)?"; then
    brew install --cask flutter
  else
    warn "Ohne Flutter wird die App-Einrichtung übersprungen."
  fi
fi

if have docker; then ok "Docker"; else
  warn "Docker fehlt. Installation: 'brew install --cask docker', danach Docker Desktop einmal öffnen (Rechte bestätigen)."
  warn "Ohne Docker läuft nur der Mock-Server, nicht das echte Backend."
fi

if xcodebuild -version >/dev/null 2>&1; then ok "Xcode"; else
  warn "Xcode fehlt oder ist nicht eingerichtet. Nötig nur für iPhone-Builds (App Store, danach 'sudo xcodebuild -runFirstLaunch')."
fi

say "2/6 .env anlegen"
if [[ -f .env ]]; then
  ok ".env existiert schon (wird nicht verändert)"
else
  key="$(openssl rand -hex 24)"
  sed "s|^ADMIN_KEY=.*|ADMIN_KEY=${key}|" .env.example > .env
  ok ".env angelegt mit zufälligem ADMIN_KEY"
fi
if grep -q '^ANTHROPIC_API_KEY=$' .env; then
  warn "ANTHROPIC_API_KEY ist noch leer. Trage ihn in .env ein, bevor du echte Pläne erzeugst."
fi

say "3/6 Git-Repository"
if [[ -d .git ]]; then
  ok "Repository existiert schon"
else
  git init -q
  git add -A
  git -c user.name="${GIT_AUTHOR_NAME:-hyrox-coach}" -c user.email="${GIT_AUTHOR_EMAIL:-hyrox@localhost}" commit -q -m "Initiales Projekt"
  ok "Repository angelegt und ersten Stand eingecheckt (.env ist per .gitignore ausgeschlossen)"
fi

say "4/6 Mock-Server-Abhängigkeiten"
if have npm; then
  (cd tools && npm install --no-audit --no-fund >/dev/null 2>&1) && ok "npm install in tools/" || warn "npm install fehlgeschlagen"
else
  warn "npm nicht gefunden, übersprungen"
fi

say "5/6 Flutter-App"
if have flutter; then
  if [[ -d app/ios && -d app/android ]]; then
    ok "Plattform-Ordner existieren schon"
  else
    (cd app && flutter create --project-name hyrox_coach --platforms=android,ios . )
    ok "flutter create ausgeführt"
    git add -A >/dev/null 2>&1 || true
  fi

  # Android: Internet-Recht und Klartext-HTTP für lokale Tests
  manifest="app/android/app/src/main/AndroidManifest.xml"
  if [[ -f "$manifest" ]]; then
    grep -q 'android.permission.INTERNET' "$manifest" || \
      perl -0pi -e 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$manifest"
    grep -q 'usesCleartextTraffic' "$manifest" || \
      perl -0pi -e 's|<application|<application android:usesCleartextTraffic="true"|' "$manifest"
    ok "Android-Manifest: INTERNET + Klartext-HTTP (nur für lokale Tests, für gehostetes Backend HTTPS nutzen)"
  fi

  # iOS: lokales Netzwerk erlauben
  plist="app/ios/Runner/Info.plist"
  if [[ -f "$plist" && -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Verbindung zum Hyrox-Coach-Backend im lokalen Netzwerk'" "$plist" 2>/dev/null || true
    ok "iOS Info.plist: lokales Netzwerk erlaubt"
  fi

  (cd app && flutter pub get) && ok "flutter pub get"
  warn "Prüfe die Umgebung mit: flutter doctor"
else
  warn "Flutter nicht installiert, übersprungen"
fi

say "6/6 Fertig. So geht es weiter"
cat <<'TEXT'

  A) Schnelltest ohne Docker und ohne API-Key (Mock-Server):
       cd tools && npm run mock             # Terminal 1
       cd tools && ADMIN_KEY=dev-admin npm run smoke   # Terminal 2

  B) Echtes Backend:
       1. ANTHROPIC_API_KEY in .env eintragen
       2. docker compose up --build
       3. Nutzer anlegen (ADMIN_KEY steht in .env):
            curl -X POST http://localhost:8080/admin/users \
              -H "Content-Type: application/json" -H "X-Admin-Key: <ADMIN_KEY>" \
              -d '{"name":"Pia"}'
          Den ausgegebenen Einladungscode aufheben, er wird nur einmal angezeigt.

  C) App starten:
       cd app && flutter run
       Backend-Adresse im Login: Android-Emulator http://10.0.2.2:8080,
       iOS-Simulator http://localhost:8080, echtes Handy http://<Mac-IP>:8080

TEXT
