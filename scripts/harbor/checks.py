"""Small result type shared by the plan, runbook and report checks."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Result:
    rule: str
    title: str
    problems: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.problems

    def fail(self, message: str) -> None:
        self.problems.append(message)

    def lines(self) -> list[str]:
        head = f"{'PASS' if self.ok else 'FAIL'} {self.rule} {self.title}"
        return [head, *(f"     - {p}" for p in self.problems)]


def render(results: list[Result]) -> str:
    lines = [line for r in results for line in r.lines()]
    failed = sum(1 for r in results if not r.ok)
    lines.append(f"{len(results) - failed} of {len(results)} rules pass")
    return "\n".join(lines) + "\n"
