#!/usr/bin/env bash
set -euo pipefail
umask 077
backup_dir="${UV_BINGO_BACKUP_DIR:-${HOME}/backups/uv-bingo-production/daily}"
retention_days="${UV_BINGO_BACKUP_RETENTION_DAYS:-14}"
if [[ ! "$retention_days" =~ ^[1-9][0-9]*$ ]]; then
  echo 'UV_BINGO_BACKUP_RETENTION_DAYS must be a positive number' >&2
  exit 1
fi
mkdir -p "$backup_dir"
exec 9>"$backup_dir/.backup.lock"
flock -n 9 || exit 0
file="$backup_dir/uv_bingo_production_$(date -u +%Y%m%d_%H%M%S).dump"
temporary="${file}.partial"
trap 'rm -f "$temporary"' EXIT
docker exec uv-bingo-db pg_dump -U uv_bingo -Fc uv_bingo_production > "$temporary"
if [ "$(head -c 5 "$temporary")" != 'PGDMP' ]; then
  echo 'Invalid PostgreSQL backup; retaining earlier backups' >&2
  exit 1
fi
mv "$temporary" "$file"
find "$backup_dir" -maxdepth 1 -type f -name 'uv_bingo_production_*.dump' -mtime "+$retention_days" -delete
printf 'Backup saved: %s\n' "$file"
