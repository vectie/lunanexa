#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

for command_name in initdb pg_ctl psql moon; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '%s\n' "PostgreSQL integration test requires $command_name" >&2
    exit 1
  fi
done

test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-postgres.XXXXXX")
port=$((30000 + ($$ % 20000)))
database_url="postgresql://lunanexa@127.0.0.1:$port/postgres?sslmode=disable"
started=0

cleanup() {
  if [ "$started" = "1" ]; then
    pg_ctl -D "$test_directory/data" -m fast stop >/dev/null 2>&1 || true
  fi
  rm -rf "$test_directory"
}
trap cleanup EXIT INT TERM

initdb -D "$test_directory/data" -A trust -U lunanexa >/dev/null
pg_ctl -D "$test_directory/data" \
  -l "$test_directory/postgres.log" \
  -o "-h 127.0.0.1 -p $port -k $test_directory" start >/dev/null
started=1

psql "$database_url" -v ON_ERROR_STOP=1 \
  -f database/migrations/001_management.sql >/dev/null
LUNANEXA_DATABASE_URL="$database_url" moon run cmd/database --target native
test "$(psql "$database_url" -Atc 'SELECT max(version) FROM lunanexa.schema_migrations')" = "2"
LUNANEXA_TEST_DATABASE_URL="$database_url" \
  moon test internal/postgres database portal/store workspace/directory \
    --target native --deny-warn

printf '%s\n' 'PostgreSQL injection, migration, projection, rollback, and restart tests passed'
