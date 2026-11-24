#!/usr/bin/env bash
# Testa as migrações num PostgreSQL local temporário (simulando o mínimo do Supabase).
# Cenário 1: banco novo + dados fictícios + regras (inclui a separação entre empresas).
# Cenário 2: banco como a produção antes da migração multi-empresa, migração e conferência.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | tail -1)}
PORT=${PGPORT_TESTE:-55432}
MULTI=20261124000002

cenario() {
  local DIR; DIR=$(mktemp -d)
  "$BIN/initdb" -D "$DIR" -U postgres -A trust >/dev/null
  "$BIN/pg_ctl" -D "$DIR" -o "-p $PORT -k $DIR -c listen_addresses=''" -l "$DIR/log" -w start >/dev/null
  P="psql -q -X -v ON_ERROR_STOP=1 -h $DIR -p $PORT -U postgres -d postgres"
  local ok=0
  ( set -e; $P -f tests/stub_supabase.sql; "$@" ) || ok=$?
  "$BIN/pg_ctl" -D "$DIR" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$DIR"
  return $ok
}

novo() {
  for f in migrations/*.sql; do $P -f "$f"; done
  $P -f seed.sql
  $P -f tests/regras.sql
}

legado() {
  for f in migrations/*.sql; do [[ $(basename "$f") < $MULTI ]] && $P -f "$f"; done
  $P -f tests/legado_antes.sql
  for f in migrations/*.sql; do [[ $(basename "$f") < $MULTI ]] || $P -f "$f"; done
  $P -f tests/legado_depois.sql
}

cenario novo
cenario legado
