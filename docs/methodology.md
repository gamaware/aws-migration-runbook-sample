# Methodology

How this sample gets from a discovery export to a cutover runbook, and what each step checks. The company, Harbor
Goods, is fictional; the method is the one a real engagement follows.

## 1. Discover

Collect five views of the estate: servers with their 95th-percentile CPU and memory, applications with owners and
recovery targets, network dependencies, databases per schema, and scheduled jobs. Add the DNS zone export. In a real
engagement these come from a discovery agent, `pg_stat_*` views, crontabs and interviews; here they are synthetic CSV
files in `data/synthetic/`.

Output: [E-01](../evidence/E-01-inventory.md).

## 2. Classify with the 7 Rs

Give every server one strategy from AWS Prescriptive Guidance (retire, retain, rehost, relocate, repurchase,
replatform, refactor), the target, the reason and the option rejected. Prefer the smallest change that removes an
operational burden; refactor only when a business driver pays for it.

Check: PLAN-01 and PLAN-02. Output: [E-02](../evidence/E-02-classification.md).

## 3. Plan waves from dependencies

Group servers into waves so that each wave can be cut over and rolled back on its own. For every dependency, compute
where each end runs after each wave. A link whose ends sit on different sides of the VPN is a hybrid link; it needs a
route, a security group rule and a line in the plan. A server cannot retire while something still reads from it,
unless the plan repoints the consumer first.

Checks: PLAN-03 to PLAN-06. Output: [E-03](../evidence/E-03-dependencies.md).

## 4. Size the target from measurements

Size each target from the source's p95 use plus 25 percent headroom, one ECS task per source server, and allocate
twice the database size in storage. Round up to a valid Fargate size and a real instance class.

Checks: PLAN-07 and PLAN-08. Output: [E-04](../evidence/E-04-sizing.md).

## 5. Plan the data move

Choose full load plus change data capture when a dump and restore would not fit the write freeze. Select every
schema, exclude tables DMS cannot replicate safely and give each exclusion a reason and a manual step. List what DMS
does not copy for PostgreSQL: sequences, roles, grants, statistics. Keep a reverse task so a rollback after go-live
keeps new writes.

Checks: PLAN-09 and PLAN-10. Output: [E-05](../evidence/E-05-dms-coverage.md).

## 6. Write the runbook as data

Write prerequisites, a timed checklist, go/no-go criteria, validation queries, rollback triggers and rollback
procedures as tables with IDs, so a script can check them:

- every step has an owner, a T-offset and a rollback procedure that fits its phase;
- the write freeze fits the business budget and the rollback fits the RTO;
- every go/no-go criterion and trigger has a number;
- the DNS TTL drops at least twice its old value before the switch;
- every job that writes to the database stops before the freeze, and the ones that stay restart after it;
- every outside party a moving server depends on has a prerequisite.

Checks: RUN-01 to RUN-16. Output: [E-06](../evidence/E-06-plan-checks.txt) and
[E-07](../evidence/E-07-runbook-checks.txt).

## 7. Build the target as code and test it offline

Terraform reads the plan files, so the tested numbers are the deployed numbers. Mocked `terraform test` runs assert
the properties the runbook relies on: private tasks and database, digest-pinned images, 100/0 weights, the forward and
reverse DMS tasks and the on-premises hosts the database admits. A separate live test, run by hand, proves what a mock
cannot.

Output: [E-08](../evidence/E-08-terraform-tests.txt).

## Tool versions

Terraform 1.14.5 with AWS provider 6.x, TFLint 0.61 with the AWS ruleset 0.49.0, Checkov 3.3.19, Python 3.13 with
PyYAML 6.0.3, ruff 0.16.9, pandoc 3 and Typst 0.15 for the PDF.
