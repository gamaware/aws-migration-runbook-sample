"""Load the inventory, plan and DMS files into plain Python structures."""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from pathlib import Path

import yaml

STRATEGIES = ("retire", "retain", "rehost", "relocate", "repurchase", "replatform", "refactor")
EXTERNAL_PREFIX = "EXT-"


class DataError(Exception):
    """A source file is missing, malformed or refers to something that does not exist."""


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise DataError(f"missing file: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_yaml(path: Path) -> dict:
    if not path.is_file():
        raise DataError(f"missing file: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise DataError(f"{path}: expected a mapping at the top level")
    return data


def read_json(path: Path) -> dict:
    if not path.is_file():
        raise DataError(f"missing file: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise DataError(f"{path}: invalid JSON ({exc})") from exc


@dataclass
class Migration:
    """Everything the checks need, loaded once from a repository root."""

    root: Path
    servers: dict[str, dict[str, str]]
    applications: dict[str, dict[str, str]]
    dependencies: list[dict[str, str]]
    databases: list[dict[str, str]]
    dns_records: dict[str, dict[str, str]]
    jobs: list[dict[str, str]]
    classification: dict[str, dict]
    waves: dict
    target: dict
    data_migration: dict
    table_mappings: dict
    forward_settings: dict
    reverse_settings: dict
    notes: list[str] = field(default_factory=list)

    @classmethod
    def load(cls, root: Path) -> Migration:
        synthetic = root / "data" / "synthetic"
        plan = root / "plan"
        data_migration = read_yaml(plan / "data-migration.yaml")
        tasks = data_migration.get("tasks", {})
        try:
            forward, reverse = tasks["forward"], tasks["reverse"]
        except KeyError as exc:
            raise DataError(f"plan/data-migration.yaml: missing task {exc}") from exc

        classification = {}
        for entry in read_yaml(plan / "classification.yaml").get("components", []):
            if entry["id"] in classification:
                raise DataError(f"plan/classification.yaml: {entry['id']} is classified twice")
            classification[entry["id"]] = entry

        return cls(
            root=root,
            servers={row["server_id"]: row for row in read_csv(synthetic / "servers.csv")},
            applications={row["app_id"]: row for row in read_csv(synthetic / "applications.csv")},
            dependencies=read_csv(synthetic / "dependencies.csv"),
            databases=read_csv(synthetic / "databases.csv"),
            dns_records={row["name"]: row for row in read_csv(synthetic / "dns-records.csv")},
            jobs=read_csv(synthetic / "scheduled-jobs.csv"),
            classification=classification,
            waves=read_yaml(plan / "waves.yaml"),
            target=read_yaml(plan / "target.yaml"),
            data_migration=data_migration,
            table_mappings=read_json(root / forward["table_mappings"]),
            forward_settings=read_json(root / forward["settings"]),
            reverse_settings=read_json(root / reverse["settings"]),
        )

    # --- Derived views ---------------------------------------------------------------------------------------

    def wave_of(self, server_id: str) -> int | None:
        """Wave number a server moves or retires in; None if it is retained or unplanned."""
        for wave in self.waves.get("waves", []):
            if server_id in wave.get("components", []):
                return int(wave["id"])
        return None

    def strategy(self, server_id: str) -> str | None:
        entry = self.classification.get(server_id)
        return entry["strategy"] if entry else None

    def wave(self, wave_id: int) -> dict:
        for wave in self.waves.get("waves", []):
            if int(wave["id"]) == wave_id:
                return wave
        raise DataError(f"plan/waves.yaml: no wave {wave_id}")

    @property
    def max_wave(self) -> int:
        return max((int(w["id"]) for w in self.waves.get("waves", [])), default=0)

    def location(self, server_id: str, after_wave: int) -> str:
        """Where a server runs once `after_wave` has finished: onprem, aws or gone."""
        if server_id.startswith(EXTERNAL_PREFIX):
            return "external"
        wave = self.wave_of(server_id)
        if wave is None or wave > after_wave:
            return "onprem"
        return "gone" if self.strategy(server_id) in ("retire", "repurchase") else "aws"

    def provider_after(self, consumer: str, provider: str, after_wave: int) -> str:
        """Apply the repoints planned up to `after_wave` to one dependency."""
        for wave in self.waves.get("waves", []):
            if int(wave["id"]) > after_wave:
                continue
            for repoint in wave.get("repoints", []) or []:
                if repoint["consumer"] == consumer and repoint["from"] == provider:
                    provider = repoint["to"]
        return provider

    def hybrid_links(self) -> set[tuple[str, str, int, int, int | None]]:
        """Dependencies whose two ends sit on different sides of the VPN after some wave.

        Returns (consumer, provider, port, from_wave, until_wave) with until_wave None while the link lasts.
        """
        links: dict[tuple[str, str, int], list[int]] = {}
        for dep in self.dependencies:
            consumer, provider, port = dep["consumer"], dep["provider"], int(dep["port"])
            if consumer.startswith(EXTERNAL_PREFIX) or provider.startswith(EXTERNAL_PREFIX):
                continue
            for after in range(0, self.max_wave + 1):
                current = self.provider_after(consumer, provider, after)
                ends = {self.location(consumer, after), self.location(current, after)}
                if ends == {"onprem", "aws"}:
                    links.setdefault((consumer, current, port), []).append(after)
        result = set()
        for (consumer, provider, port), afters in links.items():
            first, last = min(afters), max(afters)
            until = None if last == self.max_wave else last + 1
            result.add((consumer, provider, port, first, until))
        return result

    def migrated_database_ids(self) -> set[str]:
        source = self.target["database"]["source"]
        return {row["db_id"] for row in self.databases if row["server_id"] == source}

    def migrated_schemas(self) -> list[dict[str, str]]:
        ids = self.migrated_database_ids()
        return [row for row in self.databases if row["db_id"] in ids]

    def tables_without_pk(self) -> set[str]:
        names = set()
        for row in self.migrated_schemas():
            names.update(t.strip() for t in row["tables_without_pk"].split(";") if t.strip())
        return names

    def expected_table_count(self) -> int:
        """Tables the forward task must load: inventory tables minus the planned exclusions."""
        total = sum(int(row["tables"]) for row in self.migrated_schemas())
        return total - len(self.data_migration.get("exclusions", []) or [])
