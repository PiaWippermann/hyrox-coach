#!/usr/bin/env bash
# Vom Mac aus aufrufen: überträgt den Backend-Code auf den Server und startet neu.
#   SERVER=deploy@api.example.de ./deploy/deploy.sh
set -euo pipefail

: "${SERVER:?SERVER setzen, z.B. SERVER=deploy@api.example.de}"
REMOTE_DIR="${REMOTE_DIR:-/opt/hyrox-coach}"

cd "$(dirname "$0")/.."

rsync -az --delete \
  --exclude 'bin/' --exclude 'obj/' \
  backend contracts deploy docker-compose.prod.yml \
  "$SERVER:$REMOTE_DIR/"

# backups/ selbst anlegen, sonst erstellt Docker den Ordner als root und das Backup-Skript kann nicht aufräumen
ssh "$SERVER" "cd $REMOTE_DIR && mkdir -p backups && docker compose -f docker-compose.prod.yml up -d --build && docker image prune -f"
echo "Fertig. Test: curl https://<deine-domain>/health"
