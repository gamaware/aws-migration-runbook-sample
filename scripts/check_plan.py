#!/usr/bin/env python3
"""Check that the inventory, the 7R classification, the wave plan, the sizing and the DMS tasks agree.

Usage: scripts/check_plan.py [--root DIR]
Exit status: 0 when every rule passes, 1 when any rule fails, 2 when a source file cannot be read.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from harbor import plan
from harbor.checks import render
from harbor.model import DataError, Migration


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        results = plan.run(Migration.load(args.root))
    except (DataError, KeyError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2
    sys.stdout.write(render(results))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
