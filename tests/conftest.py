"""Shared fixtures: each test gets a private copy of the plan, data and runbook to break on purpose."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from harbor import plan, runbook
from harbor.model import Migration

REPO = Path(__file__).resolve().parent.parent
COPIED = ("data", "plan", "migration", "runbooks")


class Sandbox:
    def __init__(self, root: Path) -> None:
        self.root = root

    def edit(self, relative: str, old: str, new: str, count: int = 1) -> None:
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        assert old in text, f"{old!r} not found in {relative}; the fixture no longer matches the repository"
        path.write_text(text.replace(old, new, count), encoding="utf-8")

    def migration(self) -> Migration:
        return Migration.load(self.root)

    def plan_results(self) -> dict[str, bool]:
        return {r.rule: r.ok for r in plan.run(self.migration())}

    def runbook_results(self) -> dict[str, list[str]]:
        m = self.migration()
        rb = runbook.Runbook.load(self.root / m.wave(1)["runbook"])
        return {r.rule: r.problems for r in runbook.run(rb, m)}


@pytest.fixture
def sandbox(tmp_path: Path) -> Sandbox:
    for name in COPIED:
        shutil.copytree(REPO / name, tmp_path / name)
    return Sandbox(tmp_path)


def failing(results: dict) -> set[str]:
    return {rule for rule, value in results.items() if value is False or (isinstance(value, list) and value)}
