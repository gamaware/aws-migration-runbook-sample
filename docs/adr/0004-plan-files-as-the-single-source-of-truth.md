# 0004. Keep the plan in data files that Terraform, the checks and the runbook share

## Status

Accepted

## Context

A migration plan written only as prose drifts from the infrastructure code and the runbook: a resized task, a renamed
DMS task or a new dependency changes one document and not the others. The drift surfaces on cutover night.

## Decision

The inventory lives in `data/synthetic/*.csv` and every decision in `plan/*.yaml` and `migration/dms/*.json`.
Terraform reads them with `csvdecode`, `yamldecode` and `file`: sizes, addresses, task identifiers and the
on-premises hosts the database admits all come from there. `scripts/check_plan.py` and `scripts/check_runbook.py`
check the same files against each other and against the runbook, and `scripts/build_evidence.py` renders the evidence
the report cites.

## Consequences

- A change to the plan shows up in the Terraform plan, the checks and the evidence in one commit.
- The runbook tables follow a fixed format so a script can parse them.
- Readers of the Terraform must open `plan/` to see the numbers.

## Compliance

`make verify` runs the checks, the Terraform tests and `evidence-check`, which rebuilds the evidence and fails on any
difference from the committed copy. The production Terraform test asserts that the database admits exactly the hosts
from the plan's hybrid links and that the DMS task identifiers match the plan.

## Notes

Alternatives considered: a spreadsheet as the plan of record, which Terraform and the checks cannot read, and
Terraform variables as the only source, which the runbook checks and the evidence builder would have to parse out of
HCL.
