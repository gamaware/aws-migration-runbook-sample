"""Rules for the wave 1 cutover runbook: its structure, its timeline and its agreement with the plan."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .checks import Result
from .markdown import Section, parse
from .model import EXTERNAL_PREFIX, Migration

REQUIRED_SECTIONS = [
    "Scope",
    "Roles",
    "Prerequisites",
    "Timed checklist",
    "Go/no-go criteria",
    "DNS switch",
    "Validation queries",
    "Rollback triggers",
    "Rollback procedures",
    "Acceptance and sign-off",
]

_OFFSET = re.compile(r"^T(?:([+-])(\d+)([mhd]))?$|^T-0$")
_THRESHOLD = re.compile(r"(<=|>=|=|<|>)\s*\d")
_UNITS = {"m": 1, "h": 60, "d": 1440}


def offset_minutes(value: str) -> int:
    """Convert T-72h, T-0, T+02m or T+7d to minutes relative to T-0."""
    value = value.strip()
    if value in ("T-0", "T+0", "T"):
        return 0
    match = _OFFSET.match(value)
    if not match or not match.group(1):
        raise ValueError(f"unreadable T-offset '{value}'")
    sign = -1 if match.group(1) == "-" else 1
    return sign * int(match.group(2)) * _UNITS[match.group(3)]


def ids(text: str, prefix: str) -> list[str]:
    return re.findall(rf"\b{prefix}-\d{{2}}\b", text)


@dataclass
class Runbook:
    path: Path
    sections: dict[str, Section]
    order: list[str]

    @classmethod
    def load(cls, path: Path) -> Runbook:
        parsed = parse(path.read_text(encoding="utf-8"))
        return cls(path, {s.title: s for s in parsed}, [s.title for s in parsed])

    def table(self, title: str) -> list[dict[str, str]]:
        section = self.sections.get(title)
        return section.table() if section else []

    @property
    def steps(self) -> list[dict[str, str]]:
        return self.table("Timed checklist")

    def step(self, pattern: str) -> dict[str, str] | None:
        regex = re.compile(pattern, re.IGNORECASE)
        return next((s for s in self.steps if regex.search(s.get("Action", ""))), None)

    @property
    def freeze_step(self) -> dict[str, str] | None:
        return self.step(r"\bstart the write freeze\b")

    @property
    def switch_step(self) -> dict[str, str] | None:
        return self.step(r"^DNS switch\b")

    def procedures(self) -> dict[str, Section]:
        section = self.sections.get("Rollback procedures")
        if not section:
            return {}
        return {child.title.split()[0]: child for child in section.children}


def _wave_one_apps(m: Migration) -> list[dict[str, str]]:
    servers = m.wave(1)["components"]
    app_ids = {m.servers[sid]["app_id"] for sid in servers}
    return [m.applications[a] for a in sorted(app_ids)]


# --- Structure ---------------------------------------------------------------------------------------------------


def sections_in_order(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-01", "all required sections are present, in order")
    present = [t for t in rb.order if t in REQUIRED_SECTIONS]
    for title in REQUIRED_SECTIONS:
        if title not in rb.sections:
            r.fail(f"missing section '## {title}'")
    if not r.problems and present != REQUIRED_SECTIONS:
        r.fail(f"sections out of order: {', '.join(present)}")
    return r


def ids_are_sequential(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-02", "IDs in every table are unique and numbered without gaps")
    tables = {
        "Prerequisites": ("ID", "P"),
        "Timed checklist": ("ID", "C"),
        "Go/no-go criteria": ("ID", "G"),
        "Validation queries": ("ID", "V"),
        "Rollback triggers": ("ID", "T"),
    }
    for title, (column, prefix) in tables.items():
        rows = rb.table(title)
        if not rows:
            r.fail(f"'{title}' has no table")
            continue
        found = [row.get(column, "") for row in rows]
        expected = [f"{prefix}-{i:02d}" for i in range(1, len(rows) + 1)]
        if found != expected:
            r.fail(f"'{title}' IDs are {', '.join(found)}; expected {expected[0]} to {expected[-1]} in order")
    return r


def owners_are_roles(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-03", "every prerequisite and step has an owner from the roles table")
    roles = {row["Role"] for row in rb.table("Roles")}
    for title in ("Prerequisites", "Timed checklist"):
        for row in rb.table(title):
            if row.get("Owner") not in roles:
                r.fail(f"{row.get('ID')}: owner '{row.get('Owner')}' is not a role")
    return r


# --- Timeline ----------------------------------------------------------------------------------------------------


def timeline_is_ordered(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-04", "T-offsets parse, steps run in time order, prerequisites fall due before T-0")
    previous = None
    for step in rb.steps:
        try:
            minutes = offset_minutes(step["T-offset"])
            int(step["Duration (min)"])
        except (KeyError, ValueError) as exc:
            r.fail(f"{step.get('ID')}: {exc}")
            continue
        if previous is not None and minutes < previous:
            r.fail(f"{step['ID']} at {step['T-offset']} starts before the step above it")
        previous = minutes
    for row in rb.table("Prerequisites"):
        try:
            if offset_minutes(row["Due"]) >= 0:
                r.fail(f"{row['ID']} is due at {row['Due']}, not before T-0")
        except (KeyError, ValueError) as exc:
            r.fail(f"{row.get('ID')}: {exc}")
    freeze = rb.freeze_step
    if freeze is None or offset_minutes(freeze["T-offset"]) != 0:
        r.fail("the step that starts the write freeze must be at T-0")
    return r


def freeze_fits_the_budget(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-05", "the write freeze, from its start to the DNS switch, fits the business budget")
    budget = min(int(a["max_write_freeze_minutes"]) for a in _wave_one_apps(m))
    freeze, switch = rb.freeze_step, rb.switch_step
    if freeze is None or switch is None:
        r.fail("cannot find the write-freeze step or the DNS switch step")
        return r
    end = offset_minutes(switch["T-offset"]) + int(switch["Duration (min)"])
    freeze_minutes = end - offset_minutes(freeze["T-offset"])
    if freeze_minutes > budget:
        r.fail(f"planned freeze is {freeze_minutes} min; the wave 1 applications accept {budget} min")
    if f"{budget} minutes" not in rb.sections["Scope"].text:
        r.fail(f"Scope does not state the {budget}-minute write-freeze budget")
    return r


# --- Rollback ----------------------------------------------------------------------------------------------------


def every_step_can_roll_back(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-06", "every step names a rollback that exists and fits its phase; only the last step has none")
    procedures = rb.procedures()
    freeze, switch = rb.freeze_step, rb.switch_step
    if freeze is None or switch is None:
        r.fail("cannot find the write-freeze step or the DNS switch step")
        return r
    freeze_at, switch_at = offset_minutes(freeze["T-offset"]), offset_minutes(switch["T-offset"])
    phase_procedure: dict[str, set[str]] = {}
    steps = rb.steps
    for step in steps:
        ref = step.get("Rollback", "")
        at = offset_minutes(step["T-offset"])
        phase = "before" if at < freeze_at else "freeze" if at < switch_at else "after"
        if ref == "none":
            if step["ID"] != steps[-1]["ID"]:
                r.fail(f"{step['ID']} has no rollback but is not the final step")
            elif "reverse task" not in step["Action"]:
                r.fail(f"{step['ID']} ends rollback, so it must be the step that stops the reverse task")
            continue
        if ref not in procedures:
            r.fail(f"{step['ID']} refers to unknown rollback procedure '{ref}'")
            continue
        phase_procedure.setdefault(phase, set()).add(ref)
    for phase, refs in phase_procedure.items():
        if len(refs) != 1:
            r.fail(f"steps in the '{phase}' phase use different procedures: {', '.join(sorted(refs))}")
    if len(set().union(*phase_procedure.values()) if phase_procedure else set()) != 3:
        r.fail("expected three distinct procedures: before the freeze, during it, and after the DNS switch")
    return r


def procedures_are_complete(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-07", "each rollback procedure has an owner, a duration within the RTO and at least three steps")
    rto = min(int(a["rto_minutes"]) for a in _wave_one_apps(m))
    procedures = rb.procedures()
    if not procedures:
        r.fail("no '### R-NN' procedures under 'Rollback procedures'")
    for pid, section in procedures.items():
        text = section.text
        if "Decision owner:" not in text:
            r.fail(f"{pid}: no 'Decision owner:' line")
        match = re.search(r"Time to complete: (\d+) min", text)
        if not match:
            r.fail(f"{pid}: no 'Time to complete: N min' line")
        elif int(match.group(1)) > rto:
            r.fail(f"{pid}: takes {match.group(1)} min, longer than the {rto}-minute RTO")
        if len(re.findall(r"^\d+\. ", text, flags=re.MULTILINE)) < 3:
            r.fail(f"{pid}: fewer than three numbered steps")
    referenced = {row.get("Procedure") for row in rb.table("Rollback triggers")}
    referenced |= {row.get("If no-go") for row in rb.table("Go/no-go criteria")}
    for pid in procedures:
        if pid not in referenced:
            r.fail(f"{pid} is never triggered by a rollback trigger or a no-go decision")
    return r


def triggers_are_measurable(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-08", "rollback triggers have numeric thresholds and point at a procedure")
    procedures = rb.procedures()
    for row in rb.table("Rollback triggers"):
        if not _THRESHOLD.search(row.get("Threshold", "")):
            r.fail(f"{row['ID']}: threshold '{row.get('Threshold')}' has no comparison with a number")
        if row.get("Procedure") not in procedures:
            r.fail(f"{row['ID']}: unknown procedure '{row.get('Procedure')}'")
    return r


# --- Go/no-go ----------------------------------------------------------------------------------------------------


def go_no_go_is_measurable(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-09", "go/no-go criteria are numeric and each checkpoint step lists exactly its criteria")
    criteria = rb.table("Go/no-go criteria")
    steps = {s["ID"]: s for s in rb.steps}
    procedures = rb.procedures()
    by_checkpoint: dict[str, set[str]] = {}
    for row in criteria:
        if not _THRESHOLD.search(row.get("Threshold", "")):
            r.fail(f"{row['ID']}: threshold '{row.get('Threshold')}' has no comparison with a number")
        if row.get("If no-go") not in procedures:
            r.fail(f"{row['ID']}: unknown procedure '{row.get('If no-go')}'")
        by_checkpoint.setdefault(row.get("Checkpoint", ""), set()).add(row["ID"])
    for checkpoint, gids in sorted(by_checkpoint.items()):
        step = steps.get(checkpoint)
        if step is None or "go/no-go checkpoint" not in step["Action"].lower():
            r.fail(f"{checkpoint} is used as a checkpoint but is not a go/no-go step")
            continue
        listed = set(ids(step["Action"], "G"))
        if listed != gids:
            r.fail(f"{checkpoint} lists {sorted(listed)} but the criteria table assigns {sorted(gids)}")
    freeze, switch = rb.freeze_step, rb.switch_step
    if freeze and switch:
        freeze_at, switch_at = offset_minutes(freeze["T-offset"]), offset_minutes(switch["T-offset"])
        times = [offset_minutes(steps[c]["T-offset"]) for c in by_checkpoint if c in steps]
        if not any(t < freeze_at for t in times):
            r.fail("no go/no-go checkpoint before the write freeze")
        if not any(freeze_at < t < switch_at for t in times):
            r.fail("no go/no-go checkpoint between the write freeze and the DNS switch")
    return r


def counts_match_their_sources(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-10", "numbers in the criteria match the inventory, the prerequisites and the smoke tests")
    criteria = {row["ID"]: row for row in rb.table("Go/no-go criteria")}
    expected_tables = m.expected_table_count()
    loaded = next((c for c in criteria.values() if "tables loaded" in c.get("Criterion", "").lower()), None)
    if loaded is None or f"= {expected_tables} of {expected_tables}" not in loaded["Threshold"]:
        r.fail(f"a 'Tables loaded' criterion must require = {expected_tables} of {expected_tables}")
    prereqs = len(rb.table("Prerequisites"))
    closed = next((c for c in criteria.values() if "prerequisites closed" in c.get("Criterion", "").lower()), None)
    if closed is None or f"= {prereqs} of {prereqs}" not in closed["Threshold"]:
        r.fail(f"a 'Prerequisites closed' criterion must require = {prereqs} of {prereqs}")
    smoke_path = rb.path.parent / "smoke-tests.md"
    count = len(_first_table(smoke_path))
    if count == 0:
        r.fail(f"{smoke_path.name} has no smoke test table")
    for row in [*criteria.values(), *rb.table("Rollback triggers")]:
        if "smoke" in row.get("Criterion", row.get("Trigger", "")).lower() and str(count) not in row["Threshold"]:
            r.fail(f"{row['ID']} threshold '{row['Threshold']}' does not match the {count} smoke tests")
    return r


def _first_table(path: Path) -> list[dict[str, str]]:
    """First table of a short companion file (smoke tests, acceptance criteria) that has no H2 sections."""
    if not path.is_file():
        return []
    section = Section("smoke", 1, path.read_text(encoding="utf-8").splitlines())
    return section.table()


# --- Agreement with the plan -------------------------------------------------------------------------------------


def dns_switch_is_prepared(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-11", "TTLs drop early enough, the public records go away and the switch covers every name")
    names = [rec["name"] for rec in m.target["records"]]
    old_ttl = max(int(m.dns_records[n]["ttl"]) for n in names)
    ttl_step = rb.step(r"\bTTL\b")
    switch = rb.switch_step
    if ttl_step is None or switch is None:
        r.fail("cannot find the TTL step or the DNS switch step")
        return r
    match = re.search(r"from (\d+) to (\d+) seconds", ttl_step["Action"])
    if not match or int(match.group(1)) != old_ttl:
        r.fail(f"{ttl_step['ID']} must lower the TTL from the inventory value {old_ttl}")
    new_ttl = int(match.group(2)) if match else 0
    lead = offset_minutes(switch["T-offset"]) - offset_minutes(ttl_step["T-offset"])
    if lead * 60 < 2 * old_ttl:
        r.fail(f"TTL lowered only {lead} min before the switch; resolvers may cache the old answer for {old_ttl} s")
    for name in names:
        if name not in ttl_step["Action"]:
            r.fail(f"{ttl_step['ID']} does not lower the TTL of {name}")
        if name not in rb.sections["DNS switch"].text and name not in switch["Action"]:
            r.fail(f"the DNS switch does not mention {name}")
    # The weighted pairs live in the private hosted zones that Terraform creates (ADR 0006). The public zone only
    # loses the old simple records, once the corporate resolvers forward the names to the private zones.
    batch_path = m.root / "runbooks" / "dns" / "remove-public-records.json"
    changes = json.loads(batch_path.read_text(encoding="utf-8"))["Changes"] if batch_path.is_file() else []
    for name in names:
        deletes = [c for c in changes if c["Action"] == "DELETE" and c["ResourceRecordSet"]["Name"] == name]
        value = m.dns_records[name]["value"]
        if len(deletes) != 1 or deletes[0]["ResourceRecordSet"]["TTL"] != new_ttl:
            r.fail(f"remove-public-records.json must delete {name} with the lowered TTL {new_ttl}")
        elif deletes[0]["ResourceRecordSet"]["ResourceRecords"] != [{"Value": value}]:
            r.fail(f"remove-public-records.json deletes {name} with a value other than {value}")
    if any(c["Action"] != "DELETE" for c in changes):
        r.fail("remove-public-records.json may only delete; the weighted pairs belong in the private hosted zones")
    # Each name has its own private zone (ADR 0006), so the break-glass path sends one change batch per zone.
    for name in names:
        template_path = m.root / "runbooks" / "dns" / f"switch-{name}.json.tpl"
        if not template_path.is_file():
            r.fail(f"{template_path.name} is missing; the break-glass path needs one batch per private zone")
            continue
        template = template_path.read_text(encoding="utf-8")
        others = [n for n in names if n != name and f'"Name": "{n}"' in template]
        if template.count(f'"Name": "{name}"') != 2 or others:
            r.fail(f"{template_path.name} must flip both members of {name} and touch no other name")
    if "traffic_weights" not in switch["Action"]:
        r.fail(f"{switch['ID']} must change traffic_weights, the only input of the DNS module that moves traffic")
    return r


def validation_queries_exist(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-12", "every validation query in the runbook exists in validation.sql, and no other")
    listed = {row["ID"] for row in rb.table("Validation queries")}
    sql_path = m.root / "runbooks" / "sql" / "validation.sql"
    in_sql = set(re.findall(r"^-- (V-\d{2}):", sql_path.read_text(encoding="utf-8"), flags=re.MULTILINE))
    for vid in sorted(listed - in_sql):
        r.fail(f"{vid} is in the runbook but not in runbooks/sql/validation.sql")
    for vid in sorted(in_sql - listed):
        r.fail(f"{vid} is in validation.sql but not in the runbook")
    return r


def scheduled_jobs_are_handled(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-13", "jobs that write to the database or run on a moving server stop before T-0")
    wave_servers = set(m.wave(1)["components"])
    schemas = {row["schema"] for row in m.migrated_schemas()}
    before = [s for s in rb.steps if offset_minutes(s["T-offset"]) < 0]
    after_switch = []
    if rb.switch_step:
        switch_at = offset_minutes(rb.switch_step["T-offset"])
        after_switch = [s for s in rb.steps if offset_minutes(s["T-offset"]) > switch_at]
    for job in m.jobs:
        affected = job["server_id"] in wave_servers or job["writes_to"] in schemas
        if not affected:
            continue
        if not any(job["job_id"] in s["Action"] and "disable" in s["Action"].lower() for s in before):
            r.fail(f"{job['job_id']} ({job['description']}) is not disabled before T-0")
        stays = job["server_id"] not in wave_servers
        if stays and not any(job["job_id"] in s["Action"] and "re-enable" in s["Action"].lower() for s in after_switch):
            r.fail(f"{job['job_id']} runs on {job['server_id']}, which stays, but is not re-enabled after the switch")
    r01 = rb.procedures().get("R-01")
    if r01:
        for job in m.jobs:
            if job["job_id"] in " ".join(s["Action"] for s in before) and job["job_id"] not in r01.text:
                r.fail(f"R-01 does not re-enable {job['job_id']}")
    return r


def replication_is_driven_by_the_runbook(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-14", "the runbook stops the forward task and starts the reverse task inside the freeze")
    tasks = m.data_migration["tasks"]
    forward, reverse = tasks["forward"]["id"], tasks["reverse"]["id"]
    text = rb.path.read_text(encoding="utf-8")
    for task in (forward, reverse):
        if task not in text:
            r.fail(f"task {task} from plan/data-migration.yaml is not in the runbook")
    freeze, switch = rb.freeze_step, rb.switch_step
    if freeze is None or switch is None:
        r.fail("cannot find the write-freeze step or the DNS switch step")
        return r
    freeze_at, switch_at = offset_minutes(freeze["T-offset"]), offset_minutes(switch["T-offset"])
    stop = next((s for s in rb.steps if forward in s["Action"] and s["Action"].lower().startswith("stop")), None)
    start = next((s for s in rb.steps if reverse in s["Action"] and s["Action"].lower().startswith("start")), None)
    if stop is None or not freeze_at < offset_minutes(stop["T-offset"]) < switch_at:
        r.fail(f"a step must stop {forward} after the freeze starts and before the DNS switch")
    if start is None or not freeze_at < offset_minutes(start["T-offset"]) < switch_at:
        r.fail(f"a step must start {reverse} before the DNS switch, so no write on AWS escapes it")
    for step_def in m.data_migration.get("manual_steps", []):
        if step_def["id"] not in text:
            r.fail(f"manual step {step_def['id']} from plan/data-migration.yaml is not in the runbook")
    return r


def external_parties_are_prepared(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-15", "every outside party a moving server depends on has a prerequisite")
    wave_servers = set(m.wave(1)["components"])
    prereq_text = rb.sections["Prerequisites"].text if "Prerequisites" in rb.sections else ""
    externals = {
        dep["provider"]
        for dep in m.dependencies
        if dep["consumer"] in wave_servers and dep["provider"].startswith(EXTERNAL_PREFIX)
    }
    for ext in sorted(externals):
        if ext not in prereq_text:
            r.fail(f"{ext} is a dependency of a wave 1 server but no prerequisite names it")
    return r


def acceptance_criteria_are_measurable(rb: Runbook, m: Migration) -> Result:
    r = Result("RUN-16", "acceptance criteria are numbered, numeric and include the write-freeze budget")
    path = rb.path.parent / "acceptance-criteria.md"
    rows = _first_table(path)
    if not rows:
        r.fail(f"{path.name} has no criteria table")
        return r
    found = [row.get("ID", "") for row in rows]
    expected = [f"A-{i:02d}" for i in range(1, len(rows) + 1)]
    if found != expected:
        r.fail(f"IDs are {', '.join(found)}; expected {expected[0]} to {expected[-1]}")
    for row in rows:
        if not _THRESHOLD.search(row.get("Threshold", "")):
            r.fail(f"{row.get('ID')}: threshold '{row.get('Threshold')}' has no comparison with a number")
    budget = min(int(a["max_write_freeze_minutes"]) for a in _wave_one_apps(m))
    if not any(f"<= {budget} min" in row.get("Threshold", "") for row in rows):
        r.fail(f"no criterion holds the actual write freeze to <= {budget} min")
    if "acceptance-criteria.md" not in rb.sections.get("Acceptance and sign-off", Section("", 2)).text:
        r.fail("'Acceptance and sign-off' does not link acceptance-criteria.md")
    return r


RUNBOOK_RULES = [
    sections_in_order,
    ids_are_sequential,
    owners_are_roles,
    timeline_is_ordered,
    freeze_fits_the_budget,
    every_step_can_roll_back,
    procedures_are_complete,
    triggers_are_measurable,
    go_no_go_is_measurable,
    counts_match_their_sources,
    dns_switch_is_prepared,
    validation_queries_exist,
    scheduled_jobs_are_handled,
    replication_is_driven_by_the_runbook,
    external_parties_are_prepared,
    acceptance_criteria_are_measurable,
]


def run(rb: Runbook, m: Migration) -> list[Result]:
    results = [sections_in_order(rb, m)]
    if not results[0].ok:
        return results
    return results + [rule(rb, m) for rule in RUNBOOK_RULES[1:]]
