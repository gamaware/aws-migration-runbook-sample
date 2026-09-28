# Copilot code review instructions

This repository is a sample migration deliverable for a fictional company, Harbor Goods. When reviewing pull
requests:

- Flag any real account ID, ARN, public IP, email or company name. Allowed: `123456789012`, `111122223333`,
  `444455556666`, `example.com`, `203.0.113.0/24` and RFC 1918 ranges.
- The plan files in `plan/` and the inventory in `data/synthetic/` feed Terraform and the runbook. A change in one
  usually needs a change in the others; `make verify` proves they agree.
- Runbook steps need an ID, a T-offset, an owner and a rollback reference.
- Terraform must stay offline-testable: mock providers only, no data sources without an `override_data` in tests.
- Flag suppressed lint rules and blanket scanner skips. Checkov skips must sit next to the resource with a reason.
- Verify conventional commit format in PR titles and that documentation changes accompany behavior changes.
