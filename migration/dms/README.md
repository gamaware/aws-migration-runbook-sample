# AWS DMS task definitions

Two replication tasks move the `harbor` database (DB-01). Terraform (`infra/terraform/modules/dms`) reads these files
with `file()`, so the JSON here is exactly what gets deployed.

| File | Used by | Purpose |
| --- | --- | --- |
| `table-mappings.json` | both tasks | Selects the five schemas and excludes `audit.request_log`, which has no primary key |
| `task-settings-forward.json` | `harbor-wave1-full-load-cdc` | Full load, then change data capture from the data center to RDS, with row-level validation |
| `task-settings-reverse.json` | `harbor-wave1-reverse-cdc` | Change data capture from RDS back to the data center, started at cutover so a rollback keeps new fulfillment orders |

Choices worth knowing:

- `TargetTablePrepMode: DO_NOTHING`. The schema is created on RDS beforehand with `pg_dump --schema-only`
  (manual step M-01 in `plan/data-migration.yaml`). DMS would otherwise create bare tables without secondary indexes,
  defaults or functions.
- `LimitedSizeLobMode` with `LobMaxSize: 64` (KB). The discovery data reports no LOB larger than 38 KB in
  `orders` or `audit`; limited mode is much faster than full LOB mode. Validation catches a truncated value.
- `BatchApplyEnabled: false`. Transactional apply keeps order lines and their order in the same commit, which the
  go/no-go validation queries rely on.
- `ValidationSettings.EnableValidation: true` on the forward task only. Validation reads both databases; on the reverse
  task it would add load to the on-premises server that serves as the rollback target.
- Both tasks fail closed: a data, truncation or apply error on a row suspends its table (DMS still records the row in
  `dms_control.awsdms_apply_exceptions`), and an escalation stops the task. PLAN-10 rejects `LOG_ERROR` and
  `IGNORE_RECORD`. Go/no-go criterion G-03 requires zero exception rows and zero suspended tables.

DMS does not copy sequences, roles or grants for PostgreSQL. The runbook covers them with manual steps M-01 to M-04.
