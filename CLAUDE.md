# CLAUDE.md

Sample migration deliverable for **Harbor Goods, a fictional retailer**. Public portfolio repository.

## Rules

- Fictional data only. Allowed identifiers: `123456789012`, `111122223333`, `444455556666`, `example.com`,
  `203.0.113.0/24` and RFC 1918 ranges. No real names, accounts, employers or client names. No AI mentions.
- One source of truth: `data/synthetic/` (inventory) and `plan/` (decisions) feed Terraform
  (`infra/terraform/envs/production` reads them with `yamldecode` and `csvdecode`), the checks in `scripts/` and the
  runbook. Change the source, then run `make evidence` and update `report/REPORT.md` so prose and evidence agree.
- `evidence/` and `report/REPORT.pdf` are generated; a PreToolUse hook blocks hand edits.
- `make verify` must pass before every commit. It is offline: never run anything against AWS except through
  `make test-live`, which only the maintainer runs.

## Layout

| Path | Content |
| --- | --- |
| `data/synthetic/` | Discovery inventory (CSV) |
| `plan/` | 7R classification, waves, target sizing, data-migration plan (YAML) |
| `migration/dms/` | DMS table mappings and task settings (JSON), read by Terraform |
| `infra/terraform/modules/` | network, app, database, dms, dns, each with mocked `tests/` |
| `infra/terraform/envs/production/` | Wave 1 composition root |
| `infra/terraform/tests/` | Shared mocks and the live-test root |
| `runbooks/` | Cutover runbook, smoke tests, acceptance criteria, validation SQL, DNS change batches |
| `scripts/harbor/` | Plan, runbook, evidence and report rules; CLIs in `scripts/*.py` |
| `tests/` | pytest suite: every rule passes on the repository and fails on a planted mistake |
| `report/` | `REPORT.md` (canonical) and the generated PDF |

## Conventions

- Python 3.13, PyYAML only, ruff 0.16.9 (pinned in the Makefile and pre-commit). Rules return `Result` objects
  and never swallow errors; CLIs exit 2 when a source file cannot be read.
- Runbook tables are parsed: keep the column headers, the `X-NN` ID formats and one table per section.
- Terraform: `>= 1.9`, AWS provider `>= 6.0, < 7.0`, tests with `mock_provider` and shared defaults in
  `infra/terraform/tests/mocks`. Checkov skips sit inside the resource with a reason; a skip that defers work names a
  `RISK-NN` row in the report.
- ADRs in `docs/adr/` use the FoSA2 format with a Compliance section.
- Pre-commit hooks are pinned by commit SHA with a `# frozen:` comment.
