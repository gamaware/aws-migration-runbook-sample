#!/usr/bin/env python3
"""Write the evidence files the report cites (E-01 to E-07) into a directory.

Usage: scripts/build_evidence.py [--root DIR] [--out DIR]
`make evidence` writes to evidence/; `make evidence-check` writes to build/evidence and diffs the two.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from harbor import evidence
from harbor.model import DataError, Migration


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--out", type=Path, help="defaults to <root>/evidence")
    args = parser.parse_args()
    out = args.out or args.root / "evidence"
    try:
        migration = Migration.load(args.root)
        files = evidence.build(migration, args.root / migration.wave(1)["runbook"])
    except (DataError, FileNotFoundError, KeyError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (out / name).write_text(content, encoding="utf-8")
    print(f"wrote {len(files)} evidence files to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
