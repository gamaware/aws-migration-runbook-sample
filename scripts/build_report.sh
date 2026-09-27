#!/usr/bin/env bash
# Render report/REPORT.md to report/REPORT.pdf: pandoc converts Markdown to Typst, the typst Python package
# compiles the PDF. No LaTeX install needed. Usage: scripts/build_report.sh [output.pdf]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/report/REPORT.pdf}"
WORK="$ROOT/build/report"
TYPST_VERSION="0.15.0"

command -v pandoc > /dev/null || { echo "pandoc is required (https://pandoc.org/installing.html)" >&2; exit 2; }
mkdir -p "$WORK"

# Run from report/ so the relative image paths in REPORT.md resolve.
(
  cd "$ROOT/report"
  pandoc REPORT.md --from gfm --to typst --standalone \
    --shift-heading-level-by=-1 --variable papersize=a4 \
    --output "$WORK/REPORT.typ"
)
# Typst resolves absolute image paths from --root, so point the report's ../docs/ images there.
sed -i.bak 's#"\.\./docs/#"/docs/#g' "$WORK/REPORT.typ" && rm -f "$WORK/REPORT.typ.bak"

uv run --quiet --no-project --with "typst==$TYPST_VERSION" python - "$WORK/REPORT.typ" "$OUT" "$ROOT" << 'PY'
import sys
import typst

source, output, root = sys.argv[1:4]
typst.compile(source, output=output, root=root)
PY
echo "wrote $OUT"
