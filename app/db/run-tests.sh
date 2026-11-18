#!/usr/bin/env bash
# Cria um banco temporário, aplica migrações e seeds e roda os testes das regras.
# Uso: DATABASE_URL=postgres://usuario@localhost/postgres app/db/run-tests.sh
set -euo pipefail
cd "$(dirname "$0")"

ADMIN_URL="${DATABASE_URL:-postgres://postgres@localhost/postgres}"
DB="sgs_teste_$$"

psql "$ADMIN_URL" -qc "CREATE DATABASE $DB"
trap 'psql "$ADMIN_URL" -qc "DROP DATABASE IF EXISTS $DB WITH (FORCE)"' EXIT

TEST_URL="${ADMIN_URL%/*}/$DB"
for f in migrations/*.sql seed/*.sql tests/*.sql; do
  echo "== $f"
  psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$f"
done
