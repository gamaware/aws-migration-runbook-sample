"""Rules that keep the report, the evidence and the documentation links honest."""

from __future__ import annotations

import re
from pathlib import Path

from .checks import Result

_LINK = re.compile(r"\]\(([^)\s]+)\)")
DOC_GLOBS = (
    "*.md",
    "docs/**/*.md",
    "report/*.md",
    "runbooks/*.md",
    "data/**/*.md",
    "migration/**/*.md",
    "infra/**/*.md",
    "evidence/*.md",
)


def _markdown_files(root: Path) -> list[Path]:
    files = {p for pattern in DOC_GLOBS for p in root.glob(pattern) if ".terraform" not in p.parts}
    return sorted(files)


def evidence_is_cited_and_present(root: Path) -> Result:
    r = Result("REPORT-01", "every evidence ID the report cites exists, and every evidence file is cited")
    report = (root / "report" / "REPORT.md").read_text(encoding="utf-8")
    cited = set(re.findall(r"\bE-\d{2}\b", report))
    files = {p.name[:4]: p for p in (root / "evidence").glob("E-*")}
    for eid in sorted(cited - set(files)):
        r.fail(f"REPORT.md cites {eid} but evidence/ has no {eid}-* file")
    for eid in sorted(set(files) - cited):
        r.fail(f"evidence/{files[eid].name} is never cited in REPORT.md")
    return r


def report_is_labelled_fictional(root: Path) -> Result:
    r = Result("REPORT-02", "the report says it is fictional in its title block and its footer")
    lines = [line for line in (root / "report" / "REPORT.md").read_text(encoding="utf-8").splitlines() if line.strip()]
    if not any("fictional" in line.lower() for line in lines[:6]):
        r.fail("no 'fictional' label in the first lines of REPORT.md")
    if not any("fictional" in line.lower() for line in lines[-4:]):
        r.fail("no 'fictional' label in the last lines of REPORT.md")
    return r


def risks_named_in_code_exist(root: Path) -> Result:
    r = Result("REPORT-03", "every RISK-NN that a scanner skip or comment names is in the report's risk register")
    report = (root / "report" / "REPORT.md").read_text(encoding="utf-8")
    for tf in sorted((root / "infra").rglob("*.tf")):
        if ".terraform" in tf.parts:
            continue
        for risk in sorted(set(re.findall(r"\bRISK-\d{2}\b", tf.read_text(encoding="utf-8")))):
            if f"| {risk} |" not in report:
                r.fail(f"{tf.relative_to(root)} names {risk}, which is not a row in the report's risk register")
    return r


def local_links_resolve(root: Path) -> Result:
    r = Result("REPORT-04", "every relative link in the Markdown files points at a file that exists")
    for md in _markdown_files(root):
        text = re.sub(r"```.*?```", "", md.read_text(encoding="utf-8"), flags=re.DOTALL)
        for target in _LINK.findall(text):
            if re.match(r"^(https?:|mailto:|#)", target):
                continue
            path = (md.parent / target.split("#", 1)[0]).resolve()
            if not path.exists():
                r.fail(f"{md.relative_to(root)} links to missing {target}")
    return r


RULES = [evidence_is_cited_and_present, report_is_labelled_fictional, risks_named_in_code_exist, local_links_resolve]


def run(root: Path) -> list[Result]:
    return [rule(root) for rule in RULES]
