#!/usr/bin/env bash
# Testa as migrações num PostgreSQL local temporário (simulando o mínimo do Supabase).
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | tail -1)}
DIR=$(mktemp -d); PORT=${PGPORT_TESTE:-55432}
trap '"$BIN/pg_ctl" -D "$DIR" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT
"$BIN/initdb" -D "$DIR" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$DIR" -o "-p $PORT -k $DIR -c listen_addresses=''" -l "$DIR/log" -w start >/dev/null
P="psql -q -X -v ON_ERROR_STOP=1 -h $DIR -p $PORT -U postgres -d postgres"
$P -f tests/stub_supabase.sql
for f in migrations/*.sql; do $P -f "$f"; done
$P -f seed.sql
$P -f tests/regras.sql
