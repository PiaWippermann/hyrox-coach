# Deployment auf einem VPS (Hetzner)

Ziel: Die API läuft unter `https://api.<deine-domain>` auf einem eigenen Server, mit
automatischem HTTPS (Caddy), MongoDB im Container und täglichem Backup.

```
App ──HTTPS──▶ Caddy (:443) ──▶ api (:8080) ──▶ mongo
```

Dauer beim ersten Mal: etwa 1 bis 1,5 Stunden. Kosten: etwa 4–8 €/Monat für den Server
und etwa 1–15 €/Jahr für eine Domain.

Dateien im Repo, die dazugehören:

| Datei | Zweck |
|---|---|
| `docker-compose.prod.yml` | Mongo + API + Caddy, nur Caddy ist von außen erreichbar |
| `deploy/Caddyfile` | HTTPS und Weiterleitung an die API (Timeout 10 min wegen Plan-Erstellung) |
| `deploy/deploy.sh` | Vom Mac aus: Code hochladen und neu starten |
| `deploy/backup-mongo.sh` | Auf dem Server: Datenbank-Backup, behält 14 Tage |

---

## 0. Vorbereitung (auf dem Mac)

**Domain.** Du brauchst eine Domain (oder Subdomain), weil HTTPS-Zertifikate an einen
Namen gebunden sind. Hast du schon eine, nimm eine Subdomain wie `api.deinedomain.de`.
Sonst bekommst du eine bei Hetzner, INWX, Netcup o.ä.

**SSH-Schlüssel.** Falls `~/.ssh/id_ed25519.pub` noch nicht existiert:

```bash
ssh-keygen -t ed25519 -C "pia-mac"
cat ~/.ssh/id_ed25519.pub   # diesen Text brauchst du gleich bei Hetzner
```

## 1. Server bei Hetzner anlegen

1. Konto auf <https://console.hetzner.cloud> anlegen, ein Projekt erstellen.
2. **Server hinzufügen:**
   - Standort: Falkenstein oder Nürnberg
   - Image: **Ubuntu 24.04**
   - Typ: **Shared vCPU, x86**, mindestens **4 GB RAM** (der .NET-Build läuft auf dem Server)
   - Netzwerk: öffentliche IPv4 und IPv6 aktiviert lassen
   - SSH-Key: den Inhalt von `id_ed25519.pub` einfügen
   - Optional: **Backups** aktivieren (etwa 20 % Aufpreis, tägliches Abbild des ganzen Servers)
3. **Firewall** erstellen und dem Server zuweisen, eingehend erlauben:
   - TCP 22 (SSH), TCP 80, TCP 443, UDP 443
4. Die **IPv4-Adresse** des Servers notieren.

## 2. DNS eintragen

Beim Domain-Anbieter einen Eintrag anlegen:

| Typ | Name | Wert |
|---|---|---|
| A | `api` | IPv4 des Servers |
| AAAA | `api` | IPv6 des Servers (optional) |

Prüfen (kann ein paar Minuten dauern):

```bash
dig +short api.deinedomain.de   # muss die Server-IP zeigen
```

## 3. Server grundlegend einrichten

```bash
ssh root@<SERVER-IP>
```

Auf dem Server:

```bash
# System aktualisieren und automatische Sicherheitsupdates
apt update && apt upgrade -y
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades   # "Yes" wählen

# Docker installieren (offizielles Skript)
curl -fsSL https://get.docker.com | sh

# Eigener Benutzer statt root
adduser --disabled-password --gecos "" deploy
usermod -aG sudo,docker deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy

# Projektordner
mkdir -p /opt/hyrox-coach
chown deploy:deploy /opt/hyrox-coach
```

**In einem zweiten Terminal testen**, ob der Login als `deploy` klappt, bevor du root sperrst:

```bash
ssh deploy@<SERVER-IP>
```

Wenn das geht, im root-Terminal Passwort- und root-Login abschalten:

```bash
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
EOF
systemctl restart ssh
exit
```

Ab jetzt immer `ssh deploy@<SERVER-IP>` (oder `ssh deploy@api.deinedomain.de`).

## 4. Code hochladen (vom Mac)

Im Repo-Ordner auf dem Mac:

```bash
SERVER=deploy@api.deinedomain.de ./deploy/deploy.sh
```

Beim ersten Mal schlägt der Start am Ende fehl, weil die `.env` auf dem Server noch fehlt.
Das ist erwartet, weiter mit Schritt 5.

## 5. `.env` auf dem Server anlegen

```bash
ssh deploy@api.deinedomain.de
cd /opt/hyrox-coach
nano .env
```

Inhalt (Werte anpassen):

```
DOMAIN=api.deinedomain.de
ADMIN_KEY=<Ergebnis von: openssl rand -hex 32>
ANTHROPIC_API_KEY=<dein Key aus der Anthropic Console>
ANTHROPIC_MODEL=claude-sonnet-5-5
AI_MAX_CALLS_PER_DAY=4
AI_MAX_CALLS_PER_MONTH=8
AI_MAX_CHAT_PER_DAY=40
PLAN_MAX_TOKENS=32000
PLAN_EFFORT=medium
MONGO_DB=hyroxcoach
```

Wichtig: einen **neuen** `ADMIN_KEY` erzeugen, nicht den lokalen übernehmen. Dann:

```bash
chmod 600 .env
```

## 6. Starten

```bash
cd /opt/hyrox-coach
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f caddy   # Zertifikat wird geholt, Strg+C beendet
```

Test vom Mac aus:

```bash
curl https://api.deinedomain.de/health
# {"status":"ok"}
```

## 7. Nutzer anlegen

Vom Mac aus, einmal pro Person:

```bash
curl -X POST https://api.deinedomain.de/admin/users \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: <ADMIN_KEY vom Server>" \
  -d '{"name":"Pia"}'
```

Die Antwort enthält den Einladungscode, er wird **nur einmal** angezeigt.

Optional ein kompletter Test ohne KI-Kosten:

```bash
cd tools
BASE_URL=https://api.deinedomain.de ADMIN_KEY=<ADMIN_KEY> SKIP_AI=1 npm run smoke
```

## 8. App verbinden

Im Login-Bildschirm der App als Server-Adresse `https://api.deinedomain.de` eintragen,
dazu Name und Einladungscode.

## 9. Tägliches Backup einrichten

Auf dem Server:

```bash
cd /opt/hyrox-coach
./deploy/backup-mongo.sh          # einmal von Hand testen
ls -lh backups/

crontab -e
# diese Zeile ergänzen (täglich 3:30 Uhr):
30 3 * * * /opt/hyrox-coach/deploy/backup-mongo.sh >> /opt/hyrox-coach/backups/backup.log 2>&1
```

Die Backups liegen auf demselben Server. Für einen Ausfall des ganzen Servers entweder
die Hetzner-Backups (Schritt 1) aktivieren oder ab und zu eine Kopie auf den Mac/NAS ziehen:

```bash
rsync -av deploy@api.deinedomain.de:/opt/hyrox-coach/backups/ ~/hyrox-backups/
```

**Wiederherstellen** (überschreibt die Datenbank):

```bash
docker compose -f docker-compose.prod.yml exec -T mongo \
  mongorestore --archive=/backups/<datei>.archive.gz --gzip --drop
```

## 10. Updates einspielen

Nach Änderungen am Backend, vom Mac aus:

```bash
SERVER=deploy@api.deinedomain.de ./deploy/deploy.sh
```

Das lädt `backend/`, `contracts/`, `deploy/` und `docker-compose.prod.yml` hoch, baut neu
und startet die API neu. `.env`, Datenbank und Backups bleiben unberührt.

---

## Nützliche Befehle (auf dem Server, in `/opt/hyrox-coach`)

```bash
alias dc='docker compose -f docker-compose.prod.yml'
dc ps                 # Status
dc logs -f api        # API-Logs live
dc restart api        # API neu starten
dc down               # alles stoppen (Daten bleiben erhalten)
df -h                 # Speicherplatz
```

## Wenn etwas nicht klappt

| Problem | Ursache / Lösung |
|---|---|
| `curl` hängt oder „connection refused“ | Hetzner-Firewall: Ports 80/443 offen? `dc ps`: läuft caddy? |
| Caddy-Log: Zertifikatsfehler | DNS zeigt noch nicht auf den Server (`dig +short …`), oder Port 80 ist zu |
| `api` startet ständig neu | `dc logs api`: meist fehlt etwas in der `.env` oder Mongo ist nicht bereit |
| `mongo` startet nicht, Log erwähnt AVX | Servertyp hat keine AVX-CPU, anderen x86-Typ wählen |
| Plan-Erstellung bricht nach einiger Zeit ab | `dc logs api` prüfen; der Proxy erlaubt 10 min, die Anthropic-Anfrage 8 min |
| Build bricht mit „killed“ ab | Zu wenig RAM, Server mit mindestens 4 GB nehmen |
