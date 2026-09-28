#!/usr/bin/env python3
"""Check that the report cites existing evidence, carries its fictional label and that local links resolve.

Usage: scripts/check_report.py [--root DIR]
Exit status: 0 when every rule passes, 1 when any rule fails, 2 when the report cannot be read.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from harbor import report
from harbor.checks import render


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        results = report.run(args.root)
    except FileNotFoundError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2
    sys.stdout.write(render(results))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
