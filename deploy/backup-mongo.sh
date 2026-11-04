#!/usr/bin/env bash
# Sichert die MongoDB nach ./backups (auf dem Server) und behält die letzten 14 Tage.
# Per Cron täglich aufrufen, siehe docs/deployment.md.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p backups

file="hyroxcoach-$(date +%Y-%m-%d_%H%M).archive.gz"
docker compose -f docker-compose.prod.yml exec -T mongo \
  mongodump --db hyroxcoach --archive="/backups/$file" --gzip

find backups -name 'hyroxcoach-*.archive.gz' -mtime +14 -delete
echo "Backup erstellt: backups/$file"
