#!/usr/bin/env bash
# Copies the database and local storage of the current production Chatwoot
# ("chatwoot" stack) into the parallel "chatwoot_v2" stack. The source is only
# read (pg_dump + read-only volume mount). Re-runnable: use it again at cutover.
#
# Stop v2 app/sidekiq first:  docker service scale chatwoot_v2_app=0 chatwoot_v2_sidekiq=0
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dump

SRC=$(docker ps -qf name=pgvector_pgvector | head -n1)
DST=$(docker ps -qf name=chatwoot_v2_postgres | head -n1)
[ -n "$SRC" ] && [ -n "$DST" ] || { echo "postgres container not found"; exit 1; }

echo "[$(date)] dumping source database (read-only)"
docker exec "$SRC" pg_dump -U postgres -Fc -Z3 chatwoot > dump/chatwoot.dump
ls -lh dump/chatwoot.dump

echo "[$(date)] recreating v2 database"
docker exec "$DST" psql -U postgres -c "DROP DATABASE IF EXISTS chatwoot WITH (FORCE)" -c "CREATE DATABASE chatwoot"

echo "[$(date)] restoring"
docker cp dump/chatwoot.dump "$DST":/tmp/chatwoot.dump
docker exec "$DST" pg_restore -U postgres -d chatwoot --no-owner -j 4 /tmp/chatwoot.dump
docker exec "$DST" rm -f /tmp/chatwoot.dump
docker exec "$DST" psql -U postgres -d chatwoot -Atc "select 'migrations', count(*), max(version) from schema_migrations"

echo "[$(date)] copying local storage (source mounted read-only)"
docker run --rm -v chatwoot_storage:/src:ro -v chatwoot_v2_storage:/dst alpine \
  sh -c "apk add -q rsync && rsync -a --delete /src/ /dst/"

echo "[$(date)] SYNC OK"
