"""Just enough Markdown parsing for the runbook: H2 sections, H3 subsections and pipe tables."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

_HEADING = re.compile(r"^(#{2,3}) (.+?)\s*$")


@dataclass
class Section:
    title: str
    level: int
    lines: list[str] = field(default_factory=list)
    children: list[Section] = field(default_factory=list)

    @property
    def text(self) -> str:
        return "\n".join(self.lines)

    def table(self) -> list[dict[str, str]]:
        """Rows of the first pipe table in the section, keyed by header."""
        rows: list[str] = []
        in_fence = False
        for line in self.lines:
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if not in_fence and line.lstrip().startswith("|"):
                rows.append(line)
            elif rows:
                break
        if len(rows) < 2:
            return []
        header = split_row(rows[0])
        return [dict(zip(header, split_row(row), strict=False)) for row in rows[2:]]


def split_row(row: str) -> list[str]:
    """Split a table row on pipes that are not inside backticks."""
    cells, current, in_code = [], [], False
    for char in row.strip().strip("|"):
        if char == "`":
            in_code = not in_code
        if char == "|" and not in_code:
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    cells.append("".join(current).strip())
    return cells


def parse(text: str) -> list[Section]:
    """Return the H2 sections in order; H3 sections become children of the H2 above them."""
    sections: list[Section] = []
    current: Section | None = None
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        match = None if in_fence else _HEADING.match(line)
        if match and len(match.group(1)) == 2:
            current = Section(match.group(2), 2)
            sections.append(current)
            continue
        if match and current is not None:
            child = Section(match.group(2), 3)
            current.children.append(child)
            continue
        if current is not None:
            current.lines.append(line)
            if current.children:
                current.children[-1].lines.append(line)
    return sections
