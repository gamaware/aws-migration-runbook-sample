#!/usr/bin/env bash
# Render report/REPORT.md to report/REPORT.pdf with the same pandoc/latex image and arguments as the shared
# report.yml workflow in CI. Needs Docker. Usage: scripts/build_report.sh [output.pdf]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/report/REPORT.pdf}"
WORK="$ROOT/build/report"
PANDOC_IMAGE="pandoc/latex:3.11@sha256:cdbf139f607237498b412b3aa051008311d69b88006ab47550efba357af3b277"
PANDOC_ARGS=(--pdf-engine=xelatex -V geometry:margin=2cm --shift-heading-level-by=-1)

command -v docker > /dev/null || { echo "docker is required to run the pandoc/latex image" >&2; exit 2; }
mkdir -p "$WORK"

# Run from report/ so the relative image paths in REPORT.md resolve.
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$ROOT:/data" -v "$WORK:/out" -w /data/report \
  "$PANDOC_IMAGE" REPORT.md "${PANDOC_ARGS[@]}" -o /out/REPORT.pdf
cp "$WORK/REPORT.pdf" "$OUT"
echo "wrote $OUT"
