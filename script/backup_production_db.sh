#!/usr/bin/env bash
set -euo pipefail
umask 077
backup_dir="${BACKUP_DIR:-${HOME}/backups/uv-bingo}"
retention_days="${RETENTION_DAYS:-7}"
if [[ ! "$retention_days" =~ ^[1-9][0-9]*$ ]]; then
  echo 'RETENTION_DAYS must be a positive number' >&2
  exit 1
fi
mkdir -p "$backup_dir"
exec 9>"$backup_dir/.backup.lock"
# Keep scheduled and manual backups from overlapping.
flock -w 60 9 || { echo 'Timed out waiting for the production backup lock' >&2; exit 1; }
temporary="$(mktemp "$backup_dir/prod_dump_$(date -u +%Y-%m-%d_%H_%M_%S)_XXXXXX.sql.gz.partial")"
file="${temporary%.partial}"
trap 'rm -f "$temporary"' EXIT
docker exec uv-bingo-db pg_dump -U uv_bingo -d uv_bingo_production --clean --if-exists | gzip -9 > "$temporary"
if ! gzip -cd "$temporary" | awk '/^-- PostgreSQL database dump$/ { valid = 1 } END { exit !valid }'; then
  echo 'Invalid PostgreSQL backup; retaining earlier backups' >&2
  exit 1
fi
mv "$temporary" "$file"
find "$backup_dir" -maxdepth 1 -type f -name 'prod_dump_*.sql.gz' -mtime "+$retention_days" -delete
printf 'Backup saved: %s\n' "$file"
