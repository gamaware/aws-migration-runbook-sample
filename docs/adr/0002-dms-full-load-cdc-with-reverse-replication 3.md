# 0002. Move the data with AWS DMS full load plus CDC, and keep a reverse task for rollback

## Status

Accepted

## Context

The `harbor` database holds 182 GB and changes about 500 MB per hour. A dump and restore inside the window would
exceed the 30-minute write freeze. Once users write to RDS, a rollback that points DNS back to the data center
would lose every order written on AWS, unless those writes flow back.

## Decision

- A forward DMS task (`harbor-wave1-full-load-cdc`, `full-load-and-cdc`) starts at T-7d. The full load copies the
  data while the application keeps running; change data capture keeps RDS current until the write freeze.
- A reverse task (`harbor-wave1-reverse-cdc`, `cdc` only) starts inside the freeze, before users reach AWS. It
  keeps SRV-07 current for the seven days of hypercare, so rollback R-03 keeps new orders.
- RDS runs with `rds.logical_replication = 1` so it can serve as the reverse source.
- The schema is created on RDS with `pg_dump --schema-only` (`TargetTablePrepMode: DO_NOTHING`). Sequences, roles
  and the table without a primary key are handled by manual steps M-01 to M-05.

## Consequences

- The write freeze covers only the drain of the last changes, sequence resets and validation: 27 minutes planned.
- The replication instance and the reverse task run, and cost money, until hypercare ends (C-23).
- A reverse task adds load to SRV-07 during hypercare; validation is off on that task for this reason.
- Neither task starts on `terraform apply`; only the runbook starts and stops them.

## Compliance

PLAN-09 and PLAN-10 check that every schema is selected, that tables without a primary key are excluded with a reason,
that the forward task validates rows and that the LOB limit fits the inventory. RUN-14 checks that the runbook stops
the forward task and starts the reverse task between the freeze and the DNS switch. The DMS Terraform tests read the
same JSON files and fail on a full-load-only forward task or a reverse task that would reload data.

## Notes

Endpoints use `ssl_mode = require`. Certificate verification (`verify-full`) is tracked as RISK-09 in the report.
