"""Each plan rule passes on the repository and fails on the one mistake it exists to catch."""

from __future__ import annotations

import pytest

from conftest import REPO, failing
from harbor import plan
from harbor.model import DataError, Migration


def test_repository_plan_passes() -> None:
    results = plan.run(Migration.load(REPO))
    assert [r.rule for r in results if not r.ok] == []


def test_hybrid_links_follow_the_waves() -> None:
    links = Migration.load(REPO).hybrid_links()
    assert links == {
        ("SRV-09", "SRV-07", 5432, 1, 2),
        ("SRV-10", "SRV-07", 5432, 1, 3),
        ("SRV-09", "SRV-11", 22, 2, None),
    }


def test_duplicate_classification_is_a_load_error(sandbox) -> None:
    sandbox.edit("plan/classification.yaml", "  - id: SRV-02\n", "  - id: SRV-01\n")
    with pytest.raises(DataError, match="classified twice"):
        sandbox.migration()


@pytest.mark.parametrize(
    ("relative", "old", "new", "rule"),
    [
        pytest.param(
            "plan/classification.yaml", "  - id: SRV-12\n", "  - id: SRV-99\n", "PLAN-01", id="server-left-unclassified"
        ),
        pytest.param(
            "plan/classification.yaml", "strategy: rehost", "strategy: lift-and-shift", "PLAN-02", id="unknown-strategy"
        ),
        pytest.param(
            "plan/waves.yaml",
            "components: [SRV-09, SRV-12]",
            "components: [SRV-09, SRV-12, SRV-10]",
            "PLAN-03",
            id="server-in-two-waves",
        ),
        pytest.param(
            "plan/waves.yaml",
            "    repoints:\n      - consumer: SRV-10",
            "    repoints_removed:\n      - consumer: SRV-10",
            "PLAN-04",
            id="replica-retired-while-bi-reads-it",
        ),
        pytest.param(
            "plan/waves.yaml",
            "    port: 22\n    from_wave: 2",
            "    port: 22\n    from_wave: 3",
            "PLAN-05",
            id="hybrid-link-declared-for-the-wrong-wave",
        ),
        pytest.param(
            "plan/target.yaml",
            "onprem_value: 203.0.113.11",
            "onprem_value: 203.0.113.99",
            "PLAN-06",
            id="dns-value-differs-from-inventory",
        ),
        pytest.param("plan/target.yaml", "memory: 6144", "memory: 5120", "PLAN-07", id="api-task-too-small"),
        pytest.param("plan/target.yaml", "memory: 3072", "memory: 9216", "PLAN-07", id="invalid-fargate-size"),
        pytest.param(
            "plan/target.yaml",
            "allocated_storage_gb: 400",
            "allocated_storage_gb: 300",
            "PLAN-08",
            id="storage-below-twice-the-data",
        ),
        pytest.param("plan/target.yaml", 'engine_version: "16"', 'engine_version: "13"', "PLAN-08", id="downgrade"),
        pytest.param(
            "migration/dms/table-mappings.json",
            '"rule-action": "exclude"',
            '"rule-action": "include"',
            "PLAN-09",
            id="table-without-primary-key-replicated",
        ),
        pytest.param(
            "plan/data-migration.yaml",
            "migration_type: full-load-and-cdc",
            "migration_type: full-load",
            "PLAN-10",
            id="forward-task-without-cdc",
        ),
        pytest.param(
            "migration/dms/task-settings-forward.json",
            '"LobMaxSize": 64',
            '"LobMaxSize": 32',
            "PLAN-10",
            id="lob-limit-truncates-orders",
        ),
        pytest.param(
            "migration/dms/task-settings-reverse.json",
            '"ApplyErrorInsertPolicy": "SUSPEND_TABLE"',
            '"ApplyErrorInsertPolicy": "LOG_ERROR"',
            "PLAN-10",
            id="reverse-task-logs-and-skips-a-failed-insert",
        ),
    ],
)
def test_rule_catches_its_mistake(sandbox, relative: str, old: str, new: str, rule: str) -> None:
    sandbox.edit(relative, old, new)
    assert rule in failing(sandbox.plan_results())


def test_moving_batch_earlier_changes_the_hybrid_links(sandbox) -> None:
    sandbox.edit("plan/waves.yaml", "SRV-07, SRV-08]", "SRV-07, SRV-08, SRV-09]")
    sandbox.edit("plan/waves.yaml", "components: [SRV-09, SRV-12]", "components: [SRV-12]")
    assert failing(sandbox.plan_results()) == {"PLAN-05"}
