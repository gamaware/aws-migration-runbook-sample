#!/usr/bin/env bash
# Pre-edit hook: evidence/ and report/REPORT.pdf are generated. Block hand edits so evidence always matches the
# scripts that produced it. Regenerate with `make evidence` or `make report` instead.
set -euo pipefail

FILE="$(jq -r '.tool_input.file_path // empty')"
case "$FILE" in
  evidence/* | */evidence/* | report/REPORT.pdf | */report/REPORT.pdf)
    echo "BLOCKED: $FILE is generated. Run 'make evidence' or 'make report' instead of editing it." >&2
    exit 2
    ;;
esac
exit 0
