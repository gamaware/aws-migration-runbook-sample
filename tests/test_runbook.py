"""Each runbook rule passes on the repository and fails on the one mistake it exists to catch."""

from __future__ import annotations

import pytest

from conftest import REPO, failing
from harbor import runbook
from harbor.markdown import split_row
from harbor.model import Migration

RUNBOOK = "runbooks/wave-1-cutover.md"


def test_repository_runbook_passes() -> None:
    m = Migration.load(REPO)
    results = runbook.run(runbook.Runbook.load(REPO / RUNBOOK), m)
    assert [r.rule for r in results if not r.ok] == []


@pytest.mark.parametrize(
    ("offset", "minutes"),
    [("T-72h", -4320), ("T-90m", -90), ("T-0", 0), ("T+02m", 2), ("T+7d", 10080), ("T-14d", -20160)],
)
def test_offsets(offset: str, minutes: int) -> None:
    assert runbook.offset_minutes(offset) == minutes


@pytest.mark.parametrize("offset", ["72h before", "T-3w", "T+", ""])
def test_unreadable_offsets_raise(offset: str) -> None:
    with pytest.raises(ValueError, match="unreadable"):
        runbook.offset_minutes(offset)


def test_pipes_inside_code_do_not_split_cells() -> None:
    assert split_row("| C-01 | run `a | b` | R-01 |") == ["C-01", "run `a | b`", "R-01"]


def test_missing_section_stops_the_other_rules(sandbox) -> None:
    sandbox.edit(RUNBOOK, "## Rollback triggers", "## Things that might go wrong")
    results = sandbox.runbook_results()
    assert list(results) == ["RUN-01"]
    assert "missing section '## Rollback triggers'" in results["RUN-01"]


@pytest.mark.parametrize(
    ("relative", "old", "new", "rule"),
    [
        pytest.param(RUNBOOK, "| P-13 |", "| P-14 |", "RUN-02", id="gap-in-prerequisite-ids"),
        pytest.param(
            RUNBOOK, "| C-05 | T-90m | 10 | CL |", "| C-05 | T-90m | 10 | Alex |", "RUN-03", id="owner-is-a-person"
        ),
        pytest.param(RUNBOOK, "| C-08 | T-30m |", "| C-08 | T-3h |", "RUN-04", id="step-out-of-order"),
        pytest.param(RUNBOOK, "| C-19 | T+25m | 2 |", "| C-19 | T+25m | 9 |", "RUN-05", id="freeze-over-budget"),
        pytest.param(RUNBOOK, "freeze ends | R-03 |", "freeze ends | none |", "RUN-06", id="switch-without-rollback"),
        pytest.param(
            RUNBOOK, "Time to complete: 25 min", "Time to complete: 45 min", "RUN-07", id="rollback-slower-than-rto"
        ),
        pytest.param(RUNBOOK, "| ALB 5xx > 2 percent for 5 min |", "| high error rate |", "RUN-08", id="vague-trigger"),
        pytest.param(RUNBOOK, "| = 12 of 12 passed |", "| all pass |", "RUN-09", id="vague-go-no-go"),
        pytest.param(
            RUNBOOK,
            "criteria G-06, G-07 and G-08",
            "criteria G-06 and G-07",
            "RUN-09",
            id="checkpoint-skips-a-criterion",
        ),
        pytest.param(RUNBOOK, "| = 54 of 54 |", "| = 55 of 55 |", "RUN-10", id="table-count-ignores-exclusion"),
        pytest.param(
            "runbooks/smoke-tests.md",
            "| S-12 | both |",
            "| S-12 | both |\n| S-13 | both | extra | x |",
            "RUN-10",
            id="smoke-count-changed",
        ),
        pytest.param(
            "data/synthetic/dns-records.csv",
            "A,3600,203.0.113.10",
            "A,172800,203.0.113.10",
            "RUN-11",
            id="ttl-too-long-for-lead-time",
        ),
        pytest.param(
            "runbooks/dns/remove-public-records.json",
            '"TTL": 60',
            '"TTL": 3600',
            "RUN-11",
            id="public-record-deleted-with-old-ttl",
        ),
        pytest.param(
            "runbooks/dns/remove-public-records.json",
            '"Action": "DELETE"',
            '"Action": "UPSERT"',
            "RUN-11",
            id="public-record-kept",
        ),
        pytest.param(
            "runbooks/dns/switch-api.example.com.json.tpl",
            '"Name": "api.example.com",\n        "Type": "A",\n        "SetIdentifier": "aws"',
            '"Name": "warehouse.example.com",\n        "Type": "A",\n        "SetIdentifier": "aws"',
            "RUN-11",
            id="break-glass-batch-crosses-zones",
        ),
        pytest.param(
            "runbooks/dns/switch-api.example.com.json.tpl",
            '"SetIdentifier": "aws"',
            '"SetIdentifier": "onprem"',
            "RUN-11",
            id="break-glass-batch-flips-one-member-twice",
        ),
        pytest.param(
            "runbooks/dns/switch-warehouse.example.com.json.tpl",
            '"Weight": ${AWS_WEIGHT}',
            '"Weight": ${ONPREM_WEIGHT}',
            "RUN-11",
            id="break-glass-batch-gives-both-members-one-weight",
        ),
        pytest.param("runbooks/sql/validation.sql", "-- V-07:", "-- V-7:", "RUN-12", id="validation-query-missing"),
        pytest.param(RUNBOOK, "JOB-03 on SRV-07 and JOB-04", "JOB-04", "RUN-13", id="backup-job-left-running"),
        pytest.param(RUNBOOK, "re-enable JOB-01 and JOB-02, resume", "resume", "RUN-13", id="batch-never-re-enabled"),
        pytest.param(
            RUNBOOK,
            "Start the reverse task `harbor-wave1-reverse-cdc`",
            "Start the reverse task",
            "RUN-14",
            id="reverse-task-not-started",
        ),
        pytest.param(RUNBOOK, "| P-04 | EXT-CARRIER: the", "| P-04 | The", "RUN-15", id="carrier-allowlist-forgotten"),
        pytest.param(
            "runbooks/acceptance-criteria.md",
            "| <= 30 min |",
            "| short |",
            "RUN-16",
            id="freeze-not-accepted-numerically",
        ),
    ],
)
def test_rule_catches_its_mistake(sandbox, relative: str, old: str, new: str, rule: str) -> None:
    sandbox.edit(relative, old, new)
    assert rule in failing(sandbox.runbook_results())


def test_only_the_first_table_of_a_section_is_read() -> None:
    from harbor.markdown import parse

    text = "## S\n\n| ID |\n| --- |\n| A-01 |\n\n```text\n| not | a row |\n```\n\n| ID |\n| --- |\n| B-01 |\n"
    assert parse(text)[0].table() == [{"ID": "A-01"}]
