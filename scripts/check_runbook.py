#!/usr/bin/env python3
"""Check the cutover runbook's structure, timeline and rollback coverage against the plan.

Usage: scripts/check_runbook.py [--root DIR] [--runbook FILE]
Exit status: 0 when every rule passes, 1 when any rule fails, 2 when a source file cannot be read.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from harbor import runbook
from harbor.checks import render
from harbor.model import DataError, Migration


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--runbook", type=Path, help="defaults to the wave 1 runbook named in plan/waves.yaml")
    args = parser.parse_args()
    try:
        migration = Migration.load(args.root)
        path = args.runbook or args.root / migration.wave(1)["runbook"]
        results = runbook.run(runbook.Runbook.load(path), migration)
    except (DataError, FileNotFoundError, KeyError, ValueError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2
    sys.stdout.write(render(results))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
