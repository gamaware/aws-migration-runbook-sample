# 0001. Replatform the warehouse application tier to ECS Fargate and Amazon RDS

## Status

Accepted

## Context

Wave 1 moves eight servers: an HAProxy pair, two warehouse web app servers, two inventory API servers, the
PostgreSQL primary and its streaming replica. The platform team patches every one of them by hand, and discovery found
configuration drift between the two web app servers. The web app and the API already read their settings from
environment variables and hold no local state. The business accepts a write freeze of at most 30 minutes.

Options considered:

- **Rehost** all eight servers with AWS Application Migration Service. Fastest, but it carries the drift, the OS
  patching and the failover scripts into AWS.
- **Replatform** the web and API tiers to containers on ECS Fargate, the load balancers to an ALB and the database
  to Amazon RDS for PostgreSQL.
- **Refactor** the API to AWS Lambda. The JVM start time and the pooled database connections need code changes that
  no business driver pays for.

## Decision

We replatform. Two ECS Fargate services (web and api, two tasks each) replace the four application servers, an
Application Load Balancer replaces HAProxy, and RDS for PostgreSQL 16 Multi-AZ replaces the primary and the replica.
Task and instance sizes come from the discovery p95 figures with 25 percent headroom (`plan/target.yaml`).

## Consequences

- No servers to patch in wave 1; Multi-AZ covers the failover the replica provided.
- Images must be built, scanned and pinned by digest before cutover (prerequisite P-10).
- The database changes major version (14 to 16) during the move. DMS copies rows logically, so no `pg_upgrade` step
  is needed, but the rehearsal must run the application against 16.
- The batch server keeps local-disk dependencies, so it is rehosted in wave 2 instead (see
  `plan/classification.yaml`).

## Compliance

`scripts/check_plan.py` rules PLAN-07 and PLAN-08 fail if a task or the RDS instance is smaller than the discovery
p95 figures allow, or if the Fargate size is invalid. The Terraform tests assert private tasks, non-root read-only
containers, digest-pinned images and a Multi-AZ, encrypted, private database.

## Notes

Aurora PostgreSQL was left for a later evaluation: it would add a storage-model change to a move that already
changes the major version.
