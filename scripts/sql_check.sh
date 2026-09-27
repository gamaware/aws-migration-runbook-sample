#!/usr/bin/env bash
# Run runbooks/sql/validation.sql against throwaway PostgreSQL 14 (the source version) and 16 (the target
# version) containers loaded with tests/sql/fixture.sql, and prove that V-05 finds the sequence DMS leaves behind
# and that its generated fix clears it. Needs Docker; no AWS access. Usage: make sql-check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES=(
  "postgres:14-alpine@sha256:4ea9e5ed06591da7ea23eb65465e8d3187fe79f4d5ec3ae976d29a33b013e77a"
  "postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea"
)
NAME="harbor-sql-check-$$"

cleanup() { docker rm -f "$NAME" > /dev/null 2>&1 || true; }
trap cleanup EXIT

psql() { docker exec -i "$NAME" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d harbor "$@"; }

for image in "${IMAGES[@]}"; do
  cleanup
  docker run -d --name "$NAME" -e POSTGRES_PASSWORD=local-only -e POSTGRES_DB=harbor "$image" > /dev/null
  for (( attempt = 0; attempt < 30; attempt++ )); do
    docker exec "$NAME" pg_isready -U postgres -d harbor > /dev/null 2>&1 && break
    sleep 1
  done
  psql < "$ROOT/tests/sql/fixture.sql"
  psql < "$ROOT/runbooks/sql/validation.sql" > /dev/null

  v05="$(sed -n '/^-- V-05:/,/^-- V-06:/p' "$ROOT/runbooks/sql/validation.sql")"
  before="$(psql -At <<< "$v05" | wc -l | tr -d ' ')"
  fix="$(psql -At -F '|' <<< "$v05" | cut -d '|' -f 5)"
  psql -At <<< "$fix" > /dev/null
  after="$(psql -At <<< "$v05" | wc -l | tr -d ' ')"
  if [[ "$before" != "1" || "$after" != "0" ]]; then
    echo "FAIL $image: V-05 found $before stale sequence(s) before the fix and $after after; expected 1 and 0" >&2
    exit 1
  fi
  echo "PASS $image: validation.sql runs; V-05 finds the stale sequence and its fix clears it"
done
