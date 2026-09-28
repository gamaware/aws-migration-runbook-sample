# Wave 1 cutover runbook: Harbor Goods warehouse core

> Fictional sample. Harbor Goods, its servers, addresses and people are invented; account and network values are
> AWS documentation examples. `scripts/check_runbook.py` validates this file's structure and its consistency with
> `plan/` and `data/synthetic/`.

## Scope

Wave 1 moves the warehouse web app (SRV-03, SRV-04), the inventory API (SRV-05, SRV-06), the HAProxy pair (SRV-01,
SRV-02) and the PostgreSQL primary (SRV-07) to AWS, and retires the streaming replica (SRV-08) at the end of hypercare.
Warehouse staff and handheld scanners reach `warehouse.example.com` from the corporate network; the storefront, which
already runs on AWS, reaches the inventory API at `api.example.com` from its own VPC. Both names move together. On AWS
both names resolve only privately: a Route 53 private hosted zone holds the weighted pairs, the corporate DNS servers
forward the two names to a Resolver inbound endpoint over the VPN, and the load balancer is internal (ADR 0006).

- Window: Sunday 00:30 to 04:30 US Central time. T-0 is 02:00, the start of the write freeze.
- Write-freeze budget: 30 minutes (`max_write_freeze_minutes` in `data/synthetic/applications.csv`).
- Rollback stays possible for seven days after the DNS switch, while the reverse DMS task keeps SRV-07 current.
- Target: `infra/terraform/envs/production`. Replication tasks: `harbor-wave1-full-load-cdc` (forward) and
  `harbor-wave1-reverse-cdc` (reverse), defined in `migration/dms/`.

## Roles

| Role | Name | Responsibility |
| --- | --- | --- |
| CL | Cutover lead | Runs the bridge call, keeps the timeline, calls every go/no-go and rollback |
| DBA | Database administrator | DMS tasks, validation queries, sequences, database roles |
| APP | Application owner | Images, maintenance mode, smoke tests, carrier label checks |
| NET | Network engineer | VPN, Route 53, load balancer |
| OPS | Operations engineer | Scheduled jobs, batch and BI servers |
| BIZ | Business approver | Approves the window and the go-live; owns communication to warehouse staff and the storefront team |

## Prerequisites

Every prerequisite is closed, with its evidence linked in the change record, before go/no-go checkpoint C-09.

| ID | Prerequisite | Owner | Due | Evidence |
| --- | --- | --- | --- | --- |
| P-01 | `example.com` is hosted in Route 53 and its delegation answers from the Route 53 name servers; the public zone keeps only the ACM validation records for the wave 1 names | NET | T-14d | `dig NS example.com` output |
| P-02 | Both Site-to-Site VPN tunnels are up, the corporate network routes 10.60.0.0/16 into them, the storefront team routes 10.60.0.0/16 through `terraform output storefront_peering_connection_id`, and `aws dms test-connection` succeeds from the replication instance to SRV-07 | NET | T-14d | Tunnel status, storefront route table and test-connection result |
| P-03 | The target environment is applied with default weights (onprem 100, aws 0), a fresh `terraform plan` shows no changes, and the `alb_dns_name`, `alb_zone_id` and `private_zone_id` outputs are copied into the change record for the break-glass path | CL | T-10d | Plan output in the change record |
| P-04 | EXT-CARRIER: the parcel carrier allowlists the NAT gateway addresses from `terraform output nat_public_ips` next to the current egress address | APP | T-10d | Provider confirmation |
| P-05 | EXT-NAS: the backup owner accepts RDS automated backups (14 days) plus the final dump in C-07 in place of the nightly NAS dump (JOB-03) | DBA | T-10d | Signed backup plan |
| P-06 | `wal_level = logical` on SRV-07; `dms_user` exists on SRV-07 with REPLICATION and superuser (the reverse target sets `session_replication_role`) and on RDS with the `rds_replication` and `rds_superuser` roles; both DMS secrets hold host, port, username and password | DBA | T-10d | `SHOW wal_level`, secret versions present |
| P-07 | Manual steps M-01 (schema from `pg_dump --schema-only`) and M-04 (roles, grants, application secret) are done on RDS | DBA | T-8d | Schema diff with zero differences |
| P-08 | The forward task `harbor-wave1-full-load-cdc` started at T-7d, finished its full load and has streamed changes since | DBA | T-5d | `aws dms describe-replication-tasks` status |
| P-09 | A full rehearsal on a restored copy measured the write freeze and closed every issue it found | CL | T-5d | Rehearsal log with timings |
| P-10 | Web and API images are built, scanned and pinned by digest, and their smoke tests pass against RDS in read-only mode | APP | T-3d | CI run and smoke report |
| P-11 | BIZ approves the window; the maintenance banner and the notice to warehouse staff are scheduled | BIZ | T-3d | Approved change record |
| P-12 | Dashboards and alarms exist for ALB 5xx and latency, RDS CPU and connections, and DMS `CDCLatencySource` and `CDCLatencyTarget`; ALB access logs arrive under `harbor-prod/alb` in the central log archive bucket | NET | T-3d | Dashboard link and a delivered log object |
| P-13 | The rollback path was rehearsed: reverse task started and stopped on the rehearsal copy, weight flip tested on `cutover-test.example.com` | CL | T-3d | Rehearsal log |

## Timed checklist

T-offsets are relative to T-0 (02:00). Durations are the rehearsal timings rounded up. The rollback column names the
procedure that applies if the step fails.

| ID | T-offset | Duration (min) | Owner | Action | Verification | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| C-01 | T-72h | 15 | NET | Lower the TTL of the public `warehouse.example.com` and `api.example.com` records from 3600 to 60 seconds | Authoritative answer shows TTL 60 | R-01 |
| C-02 | T-48h | 20 | NET | Point the corporate DNS servers' conditional forwarders for both names at `terraform output resolver_inbound_ips`, confirm they answer from the private hosted zone, then delete the public records with `runbooks/dns/remove-public-records.json` | A corporate workstation and a storefront task resolve both names to 203.0.113.x; public DNS answers NXDOMAIN | R-01 |
| C-03 | T-24h | 30 | DBA | Export the history of `audit.request_log` (excluded from DMS) with `pg_dump` to a private Amazon S3 bucket encrypted with SSE-KMS | Object row count equals `SELECT count(*)` on SRV-07 | R-01 |
| C-04 | T-24h | 10 | CL | Go/no-go checkpoint 1: criteria G-01 and G-04 | Decision recorded in the change record | R-01 |
| C-05 | T-90m | 10 | CL | Open the bridge call and confirm every role is present | Roll call logged | R-01 |
| C-06 | T-80m | 5 | OPS | Disable JOB-01 and JOB-02 on SRV-09, JOB-03 on SRV-07 and JOB-04 on SRV-10 (comment out the crontab lines) | `crontab -l` shows the four lines commented | R-01 |
| C-07 | T-70m | 55 | DBA | Take a final `pg_dump` of `harbor` to the backup NAS as the offline safety copy | Dump finishes; size within 5 percent of the last JOB-03 run | R-01 |
| C-08 | T-30m | 5 | APP | Show the maintenance banner announcing a short read-only period | Banner visible on `warehouse.example.com` | R-01 |
| C-09 | T-10m | 10 | CL | Go/no-go checkpoint 2: criteria G-02, G-03 and G-05 | Decision recorded; BIZ confirms | R-01 |
| C-10 | T-0 | 2 | APP | Start the write freeze: HAProxy serves the maintenance page for both names, and the API stops on SRV-05 and SRV-06 | V-01 returns 0 application sessions | R-02 |
| C-11 | T+02m | 3 | DBA | Confirm no writes reach SRV-07 and record `pg_current_wal_lsn()` | V-01 returns 0; LSN written in the log | R-02 |
| C-12 | T+05m | 3 | DBA | Wait for the forward task to apply the last change | `CDCLatencyTarget` at or below 5 seconds; V-04 matches on both sides | R-02 |
| C-13 | T+08m | 2 | DBA | Stop the forward task `harbor-wave1-full-load-cdc` and drop its replication slot on SRV-07, so SRV-07 does not keep WAL for seven days | Task status `stopped`; `pg_replication_slots` on SRV-07 shows no DMS slot | R-02 |
| C-14 | T+10m | 4 | DBA | Run manual steps M-02 (reset sequences with V-05), M-05 (copy the newest `audit.request_log` rows) and M-03 (`ANALYZE`) on RDS | V-05 returns no sequence behind its table | R-02 |
| C-15 | T+14m | 4 | DBA | Run validation queries V-02, V-03 and V-04 on SRV-07 and RDS and compare | Every count and checksum matches | R-02 |
| C-16 | T+18m | 2 | DBA | Start the reverse task `harbor-wave1-reverse-cdc` with no start position, before any user write lands on AWS; DMS creates its slot at the current RDS position, and writes are frozen, so nothing is missed | Task status `running`; V-07 returns 0 | R-02 |
| C-17 | T+20m | 4 | APP | Run the smoke tests against the load balancer with `curl --resolve` for both names, including one test order that is then cancelled | 12 of 12 tests in `runbooks/smoke-tests.md` pass | R-02 |
| C-18 | T+24m | 1 | CL | Go/no-go checkpoint 3: criteria G-06, G-07 and G-08 | Decision recorded; BIZ confirms go-live | R-02 |
| C-19 | T+25m | 2 | NET | DNS switch: apply `traffic_weights = { onprem = 0, aws = 100 }` (see DNS switch) | Both names resolve to the load balancer; freeze ends | R-03 |
| C-20 | T+27m | 3 | OPS | Repoint SRV-09 and SRV-10 to the RDS endpoint, re-enable JOB-01 and JOB-02, resume JOB-04; JOB-03 stays off for good | Test connections from SRV-09 and SRV-10 succeed over the VPN | R-03 |
| C-21 | T+30m | 30 | APP | Watch the first 30 minutes of live traffic: errors, latency, orders and shipping labels | Rollback triggers T-05 and T-06 stay below their thresholds | R-03 |
| C-22 | T+60m | 5 | CL | Remove the banner, announce go-live and start seven days of hypercare | Announcement sent | R-03 |
| C-23 | T+7d | 30 | CL | Close hypercare: confirm the acceptance criteria, stop the reverse task, delete the DMS resources and schedule the decommissioning of SRV-01 to SRV-08 | Every criterion in `runbooks/acceptance-criteria.md` met | none |

C-23 is the point of no return. Once the reverse task stops, SRV-07 no longer receives changes and rollback R-03 is
gone.

## Go/no-go criteria

Every criterion has a number. A missing value counts as no-go.

| ID | Checkpoint | Criterion | Threshold | Source | If no-go |
| --- | --- | --- | --- | --- | --- |
| G-01 | C-04 | Tables loaded by the forward task | = 54 of 54 | `aws dms describe-table-statistics` | R-01 |
| G-02 | C-09 | Change data capture keeps up | `CDCLatencyTarget` p95 over the last hour <= 30 s | CloudWatch metric for the forward task | R-01 |
| G-03 | C-09 | Validation and apply errors | ValidationFailedRecords = 0, suspended tables = 0, V-07 rows = 0 | Table statistics and V-07 | R-01 |
| G-04 | C-04 | Rehearsed write freeze | <= 27 min measured from C-10 to the end of C-19 | Rehearsal log (P-09) | R-01 |
| G-05 | C-09 | Prerequisites closed | = 13 of 13 | This runbook, Prerequisites | R-01 |
| G-06 | C-18 | Row counts and checksums | differences = 0 for V-02, V-03 and V-04 | `runbooks/sql/validation.sql` | R-02 |
| G-07 | C-18 | Smoke tests | = 12 of 12 passed | Smoke test report | R-02 |
| G-08 | C-18 | Write freeze so far | <= 25 min since C-10 | Bridge log | R-02 |

## DNS switch

The switch changes Route 53 weights only, in the private hosted zone. Both names have resolved from that zone since
C-02, through the Resolver inbound endpoint for the corporate network and through the zone association for the
storefront VPC, so the change reaches every client within one 60-second TTL.

Primary path, from `infra/terraform/envs/production` (the plan must show exactly four record updates):

```bash
terraform plan -var-file=production.tfvars -var 'traffic_weights={ onprem = 0, aws = 100 }' -out=switch.tfplan
terraform apply switch.tfplan
terraform output active_target   # aws
```

Check from a corporate workstation (over the VPN) and from a storefront task:

```bash
dig +short warehouse.example.com
dig +short api.example.com
curl -sS -o /dev/null -w '%{http_code}\n' https://warehouse.example.com/healthz
```

Break-glass path, if Terraform is unavailable: render `runbooks/dns/change-batch.json.tpl` for the target side
and send it in one call, which updates all four members at once. Reconcile Terraform with the matching
`traffic_weights` value right after.

```bash
set -u
# ALB_DNS_NAME, ALB_ZONE_ID and ZONE_ID (the private hosted zone) come from the change record (P-03), not from
# Terraform. A lookup by name would find the public example.com zone first.
export ALB_DNS_NAME="<from the change record>" ALB_ZONE_ID="<from the change record>"
ZONE_ID="<private_zone_id from the change record>"
export ONPREM_WEIGHT=0 AWS_WEIGHT=100
batch="$(mktemp)" && trap 'rm -f "$batch"' EXIT
envsubst '$ONPREM_WEIGHT $AWS_WEIGHT $ALB_ZONE_ID $ALB_DNS_NAME' < runbooks/dns/change-batch.json.tpl > "$batch"
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "file://$batch"
```

## Validation queries

The queries live in `runbooks/sql/validation.sql`, each under a `-- V-NN:` marker. Run them with `psql -f` against
SRV-07 and RDS and compare the output with `diff`.

| ID | Check | Run on | Pass condition |
| --- | --- | --- | --- |
| V-01 | Application sessions still connected | SRV-07 | 0 rows |
| V-02 | Exact row count of every migrated table | SRV-07 and RDS | Identical output |
| V-03 | Checksum of the last seven days of fulfillment orders and order lines | SRV-07 and RDS | Identical output |
| V-04 | Highest order ID and newest order timestamp | SRV-07 and RDS | Identical output |
| V-05 | Sequences whose value is behind the highest ID in their table | RDS | 0 rows |
| V-06 | Newest order on each side after the switch | SRV-07 and RDS | Same order ID within 60 s |
| V-07 | Rows in the DMS apply exceptions table | RDS (forward), SRV-07 (reverse) | 0 rows |

## Rollback triggers

Any trigger that fires starts the listed procedure. CL may roll back without a trigger; nobody may skip one.

| ID | Trigger | Threshold | Detection | Window | Procedure |
| --- | --- | --- | --- | --- | --- |
| T-01 | Forward replication does not drain | `CDCLatencyTarget` > 60 s at T+10m | CloudWatch | During the freeze | R-02 |
| T-02 | Data mismatch between SRV-07 and RDS | any difference > 0 in V-02, V-03 or V-04 | Validation queries | During the freeze | R-02 |
| T-03 | Smoke tests fail | < 12 of 12 passed | Smoke test report | During the freeze | R-02 |
| T-04 | Write freeze overruns | > 30 min since C-10 without a DNS switch | Bridge log | During the freeze | R-02 |
| T-05 | Error rate after the switch | ALB 5xx > 2 percent for 5 min | CloudWatch alarm | Hypercare | R-03 |
| T-06 | Shipping labels fail after the switch | label success rate < 95 percent for 10 min | Carrier API dashboard | Hypercare | R-03 |
| T-07 | Orders lost or duplicated | >= 1 confirmed case | V-06 and support tickets | Hypercare | R-03 |

## Rollback procedures

### R-01 Abort before the write freeze

Decision owner: CL. Time to complete: 15 min. Users see no change.

1. Announce the no-go on the bridge and record the failed criterion.
2. OPS re-enables JOB-01, JOB-02, JOB-03 and JOB-04; APP removes the banner if it is showing.
3. Leave the forward task running and the weights at onprem 100, so the next attempt starts from current data.
4. CL books the next window once the cause is fixed.

### R-02 Roll back during the write freeze

Decision owner: CL. Time to complete: 15 min. No user has written to AWS yet.

1. DBA stops the reverse task if C-16 started it: `aws dms stop-replication-task` on `harbor-wave1-reverse-cdc`.
2. NET confirms `terraform output active_target` still returns `onprem`; if C-19 ran, use R-03 instead.
3. APP starts the API on SRV-05 and SRV-06 and takes HAProxy out of maintenance.
4. OPS re-enables JOB-01, JOB-02, JOB-03 and JOB-04.
5. DBA marks the RDS copy stale: the smoke test wrote to it, so the next attempt reloads the target from scratch.
6. CL records the timeline and the cause.

### R-03 Roll back after the DNS switch

Decision owner: CL with BIZ. Time to complete: 25 min, within the 30-minute RTO. Orders written on AWS are kept,
because the reverse task has copied them to SRV-07.

1. APP puts AWS in maintenance: a priority-1 listener rule on the HTTPS listener returns a fixed 503 page.
2. DBA waits until the reverse task `CDCLatencyTarget` is at or below 5 seconds and V-06 shows the same newest order
   on both sides, confirms V-07 returns 0 on SRV-07 and the task has no suspended tables, then stops
   `harbor-wave1-reverse-cdc`.
3. DBA runs V-05 on SRV-07 and resets any sequence behind its table.
4. NET flips both names back in one change batch (break-glass path with `ONPREM_WEIGHT=100` and `AWS_WEIGHT=0`), then
   applies `traffic_weights = { onprem = 100, aws = 0 }` to reconcile Terraform.
5. APP starts the API on SRV-05 and SRV-06 and takes HAProxy out of maintenance.
6. OPS points SRV-09 back to SRV-07 and SRV-10 back to SRV-08, which followed SRV-07 throughout.
7. CL confirms V-06 and the smoke tests against the data center, then announces the rollback.

## Acceptance and sign-off

Wave 1 exits when every criterion in [acceptance-criteria.md](acceptance-criteria.md) is met and CL completes C-23.
BIZ signs the change record.
