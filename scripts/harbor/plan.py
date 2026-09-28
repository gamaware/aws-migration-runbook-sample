"""Rules that tie the inventory to the 7R classification, the wave plan, the target sizing and the DMS tasks."""

from __future__ import annotations

import ipaddress
import math

from .checks import Result
from .model import EXTERNAL_PREFIX, STRATEGIES, Migration

HEADROOM = 1.25


def _fargate_memory_options(cpu: int) -> list[int]:
    """Valid Fargate memory sizes (MiB) for a CPU size (units), from the ECS task size table."""
    table = {
        256: [512, 1024, 2048],
        512: list(range(1024, 4096 + 1, 1024)),
        1024: list(range(2048, 8192 + 1, 1024)),
        2048: list(range(4096, 16384 + 1, 1024)),
        4096: list(range(8192, 30720 + 1, 1024)),
        8192: list(range(16384, 61440 + 1, 4096)),
        16384: list(range(32768, 122880 + 1, 8192)),
    }
    return table.get(cpu, [])


def every_server_classified_once(m: Migration) -> Result:
    r = Result("PLAN-01", "every discovered server has exactly one 7R strategy")
    for sid in sorted(set(m.servers) - set(m.classification)):
        r.fail(f"{sid} ({m.servers[sid]['hostname']}) has no strategy in plan/classification.yaml")
    for sid in sorted(set(m.classification) - set(m.servers)):
        r.fail(f"{sid} is classified but not in data/synthetic/servers.csv")
    return r


def strategies_are_justified(m: Migration) -> Result:
    r = Result("PLAN-02", "strategies come from the 7 Rs and state a rationale and a rejected option")
    for sid, entry in sorted(m.classification.items()):
        if entry.get("strategy") not in STRATEGIES:
            r.fail(f"{sid}: '{entry.get('strategy')}' is not one of {', '.join(STRATEGIES)}")
        for key in ("target", "rationale", "rejected"):
            if not str(entry.get(key) or "").strip():
                r.fail(f"{sid}: '{key}' is empty")
    return r


def every_server_has_a_place(m: Migration) -> Result:
    r = Result("PLAN-03", "every server is in exactly one wave, or retained, never both")
    retained = set(m.waves.get("retained", []) or [])
    seen: dict[str, int] = {}
    for wave in m.waves.get("waves", []):
        for sid in wave.get("components", []):
            if sid in seen:
                r.fail(f"{sid} is in wave {seen[sid]} and wave {wave['id']}")
            seen[sid] = int(wave["id"])
            if sid not in m.servers:
                r.fail(f"wave {wave['id']} lists unknown server {sid}")
    for sid in sorted(m.servers):
        strategy = m.strategy(sid)
        if strategy == "retain":
            if sid not in retained:
                r.fail(f"{sid} is classified retain but not listed under retained")
            if sid in seen:
                r.fail(f"{sid} is classified retain but planned in wave {seen[sid]}")
        elif sid not in seen:
            r.fail(f"{sid} ({strategy}) is not planned in any wave")
    for sid in sorted(retained):
        if m.strategy(sid) != "retain":
            r.fail(f"{sid} is listed under retained but classified {m.strategy(sid)}")
    return r


def retirements_leave_no_orphans(m: Migration) -> Result:
    r = Result("PLAN-04", "no consumer still depends on a server after it retires")
    for dep in m.dependencies:
        consumer, provider = dep["consumer"], dep["provider"]
        if provider.startswith(EXTERNAL_PREFIX) or m.strategy(provider) not in ("retire", "repurchase"):
            continue
        retire_wave = m.wave_of(provider)
        if retire_wave is None or consumer.startswith(EXTERNAL_PREFIX):
            continue
        consumer_location = m.location(consumer, retire_wave)
        repointed = m.provider_after(consumer, provider, retire_wave) != provider
        if consumer_location != "gone" and not repointed and consumer != provider:
            r.fail(
                f"{provider} retires in wave {retire_wave} but {consumer} still needs it on port {dep['port']}"
                f" ({dep['purpose']}); add a repoint in wave {retire_wave} or move {consumer} earlier"
            )
    return r


def hybrid_links_match(m: Migration) -> Result:
    r = Result("PLAN-05", "declared hybrid links equal the links computed from dependencies and waves")
    declared = {
        (link["consumer"], link["provider"], int(link["port"]), int(link["from_wave"]), link.get("until_wave"))
        for link in m.waves.get("hybrid_links", []) or []
    }
    computed = m.hybrid_links()
    for link in sorted(computed - declared, key=str):
        r.fail(
            f"missing from plan/waves.yaml hybrid_links: {link[0]} -> {link[1]}:{link[2]} waves {link[3]}..{link[4]}"
        )
    for link in sorted(declared - computed, key=str):
        r.fail(f"declared but not implied by the dependencies: {link[0]} -> {link[1]}:{link[2]}")
    onprem = ipaddress.ip_network(m.target["onprem_cidr"])
    for link in computed:
        for sid in link[:2]:
            ip = ipaddress.ip_address(m.servers[sid]["private_ip"])
            if ip not in onprem:
                r.fail(f"{sid} ({ip}) is outside onprem_cidr {onprem}; the VPN would not route it")
    if onprem.overlaps(ipaddress.ip_network(m.target["vpc_cidr"])):
        r.fail(f"vpc_cidr {m.target['vpc_cidr']} overlaps onprem_cidr {onprem}")
    return r


def dns_records_move_with_their_servers(m: Migration) -> Result:
    r = Result("PLAN-06", "public names follow their servers: switched when they move, removed when they retire")
    targets = {rec["name"]: rec for rec in m.target.get("records", [])}
    for name, rec in sorted(m.dns_records.items()):
        servers = rec["served_by"].split(";")
        waves = {m.wave_of(sid) for sid in servers}
        strategies = {m.strategy(sid) for sid in servers}
        if len(waves) != 1:
            r.fail(f"{name} is served by {', '.join(servers)}, which are planned in different waves")
            continue
        wave = waves.pop()
        if wave is None:
            if name in targets:
                r.fail(f"{name} is served by retained servers but plan/target.yaml switches it")
            continue
        if strategies <= {"retire", "repurchase"}:
            if name not in (m.wave(wave).get("dns_removals", []) or []):
                r.fail(f"{name} is served by servers retiring in wave {wave}; list it in dns_removals")
            continue
        if wave == 1 and name not in targets:
            r.fail(f"{name} is served by servers moving in wave 1, but plan/target.yaml does not switch it")
    for name, rec in sorted(targets.items()):
        inventory = m.dns_records.get(name)
        if inventory is None:
            r.fail(f"plan/target.yaml switches {name}, which is not in data/synthetic/dns-records.csv")
        elif inventory["value"] != rec["onprem_value"]:
            r.fail(f"{name}: plan says {rec['onprem_value']}, inventory says {inventory['value']}")
        if rec.get("service") not in m.target.get("services", {}):
            r.fail(f"{name} points at unknown service {rec.get('service')}")
    fronts = {sid for name in targets if name in m.dns_records for sid in m.dns_records[name]["served_by"].split(";")}
    for dep in m.dependencies:
        external = dep["consumer"].startswith(EXTERNAL_PREFIX)
        if external and m.wave_of(dep["provider"]) == 1 and dep["provider"] not in fronts:
            r.fail(f"{dep['consumer']} reaches {dep['provider']} directly, but no switched name serves it")
    return r


def services_are_sized_from_discovery(m: Migration) -> Result:
    r = Result("PLAN-07", "ECS task sizes cover each source server's p95 use with 25 percent headroom")
    for name, svc in sorted(m.target.get("services", {}).items()):
        sources = svc.get("sources", [])
        if svc.get("desired_count") != len(sources):
            r.fail(f"{name}: desired_count {svc.get('desired_count')} but {len(sources)} source servers")
        cpu, memory = int(svc["cpu"]), int(svc["memory"])
        if memory not in _fargate_memory_options(cpu):
            r.fail(f"{name}: {cpu} CPU units with {memory} MiB is not a valid Fargate size")
        for sid in sources:
            server = m.servers.get(sid)
            if server is None:
                r.fail(f"{name}: unknown source {sid}")
                continue
            if m.strategy(sid) != "replatform":
                r.fail(f"{name}: source {sid} is classified {m.strategy(sid)}, not replatform")
            need_cpu = float(server["vcpu"]) * float(server["cpu_p95_pct"]) / 100 * HEADROOM
            need_mem = float(server["ram_gb"]) * float(server["mem_p95_pct"]) / 100 * HEADROOM * 1024
            if cpu / 1024 < need_cpu - 1e-9:
                r.fail(f"{name}: {cpu / 1024:.2f} vCPU < {need_cpu:.2f} needed for {sid}")
            if memory < math.ceil(need_mem - 1e-6):
                r.fail(f"{name}: {memory} MiB < {math.ceil(need_mem)} MiB needed for {sid}")
    return r


def database_is_sized_from_discovery(m: Migration) -> Result:
    r = Result("PLAN-08", "RDS covers the source CPU, memory, storage and version")
    db = m.target["database"]
    source = m.servers[db["source"]]
    need_cpu = float(source["vcpu"]) * float(source["cpu_p95_pct"]) / 100 * HEADROOM
    need_mem = float(source["ram_gb"]) * float(source["mem_p95_pct"]) / 100
    if db["instance_vcpu"] < need_cpu:
        r.fail(f"{db['instance_class']}: {db['instance_vcpu']} vCPU < {need_cpu:.1f} needed")
    if db["instance_memory_gb"] < need_mem:
        r.fail(f"{db['instance_class']}: {db['instance_memory_gb']} GB < {need_mem:.1f} GB needed")
    size = sum(float(row["size_gb"]) for row in m.migrated_schemas())
    if db["allocated_storage_gb"] < 2 * size:
        r.fail(f"allocated_storage_gb {db['allocated_storage_gb']} < 2 x {size:.1f} GB source size")
    if db["max_allocated_storage_gb"] < db["allocated_storage_gb"]:
        r.fail("max_allocated_storage_gb is below allocated_storage_gb")
    source_major = int(m.migrated_schemas()[0]["version"].split(".")[0])
    target_major = int(db["engine_version"])
    if target_major < source_major:
        r.fail(f"target PostgreSQL {target_major} is older than source {source_major}")
    if int(m.data_migration["target_engine_major"]) != target_major:
        r.fail("plan/data-migration.yaml target_engine_major differs from plan/target.yaml engine_version")
    if m.strategy(db["source"]) != "replatform":
        r.fail(f"{db['source']} is the database source but classified {m.strategy(db['source'])}")
    return r


def _selected(m: Migration, schema: str, table: str) -> bool:
    """Apply the DMS selection rules the way DMS does: the most specific matching rule wins, exclude beats include."""
    matches = []
    for rule in m.table_mappings.get("rules", []):
        if rule.get("rule-type") != "selection":
            continue
        loc = rule["object-locator"]
        if loc["schema-name"] in (schema, "%") and loc["table-name"] in (table, "%"):
            specificity = (loc["schema-name"] != "%") + (loc["table-name"] != "%")
            matches.append((specificity, rule["rule-action"] == "exclude", rule["rule-action"]))
    if not matches:
        return False
    return max(matches)[2] == "include"


def dms_covers_the_database(m: Migration) -> Result:
    r = Result("PLAN-09", "DMS selects every schema and excludes exactly the tables without a primary key")
    for row in m.migrated_schemas():
        if not _selected(m, row["schema"], "any_table"):
            r.fail(f"schema {row['schema']} is not selected by migration/dms/table-mappings.json")
    no_pk = m.tables_without_pk()
    excluded = {e["table"] for e in m.data_migration.get("exclusions", []) or []}
    for table in sorted(no_pk):
        schema, name = table.split(".", 1)
        if _selected(m, schema, name):
            r.fail(f"{table} has no primary key but DMS still selects it")
        if table not in excluded:
            r.fail(f"{table} has no primary key but plan/data-migration.yaml gives no exclusion reason")
    for entry in m.data_migration.get("exclusions", []) or []:
        if entry["table"] not in no_pk:
            r.fail(f"{entry['table']} is excluded but the inventory does not list it as lacking a primary key")
        if not str(entry.get("reason") or "").strip():
            r.fail(f"{entry['table']}: exclusion has no reason")
    return r


def dms_tasks_are_safe(m: Migration) -> Result:
    r = Result("PLAN-10", "DMS tasks: full load plus CDC forward, CDC only back, validation on, LOBs fit")
    tasks = m.data_migration["tasks"]
    if tasks["forward"]["migration_type"] != "full-load-and-cdc":
        r.fail("forward task must be full-load-and-cdc")
    if tasks["reverse"]["migration_type"] != "cdc":
        r.fail("reverse task must be cdc only")
    fwd = m.forward_settings
    if not fwd.get("ValidationSettings", {}).get("EnableValidation"):
        r.fail("forward task settings: ValidationSettings.EnableValidation must be true")
    if fwd.get("FullLoadSettings", {}).get("TargetTablePrepMode") != "DO_NOTHING":
        r.fail("forward task settings: TargetTablePrepMode must be DO_NOTHING (schema comes from M-01)")
    for label, settings in (("forward", fwd), ("reverse", m.reverse_settings)):
        meta = settings.get("TargetMetadata", {})
        if meta.get("BatchApplyEnabled"):
            r.fail(f"{label} task settings: BatchApplyEnabled splits transactions; keep it false")
        largest = max((int(row["max_lob_kb"]) for row in m.migrated_schemas()), default=0)
        if meta.get("LimitedSizeLobMode") and int(meta.get("LobMaxSize", 0)) < largest:
            r.fail(f"{label} task settings: LobMaxSize {meta.get('LobMaxSize')} KB < largest LOB {largest} KB")
    return r


PLAN_RULES = [
    every_server_classified_once,
    strategies_are_justified,
    every_server_has_a_place,
    retirements_leave_no_orphans,
    hybrid_links_match,
    dns_records_move_with_their_servers,
    services_are_sized_from_discovery,
    database_is_sized_from_discovery,
    dms_covers_the_database,
    dms_tasks_are_safe,
]


def run(m: Migration) -> list[Result]:
    return [rule(m) for rule in PLAN_RULES]
