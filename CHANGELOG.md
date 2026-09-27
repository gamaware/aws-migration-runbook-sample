# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). As an assessment sample, the project marks releases as
dated revisions rather than semantic versions of an interface.

## [Unreleased]

### Added

- Repository layout, pre-commit hooks, Makefile entry points and editor hooks.
- Synthetic discovery inventory for the fictional Harbor Goods estate: 12 servers, 8 applications, 23 dependencies.
- 7R classification with rationale and rejected options, a three-wave plan with repoints and computed hybrid links,
  target sizing and a data-migration plan.
- Terraform for wave 1: network with Site-to-Site VPN, ALB and ECS Fargate, RDS for PostgreSQL 16 Multi-AZ, AWS DMS
  forward (full load plus CDC) and reverse (CDC) tasks, and Route 53 weighted records; 38 mocked `terraform test` runs
  and a manual live-test root.
- Wave 1 cutover runbook with prerequisites, a timed checklist, go/no-go criteria, DNS switch, validation queries,
  rollback triggers and procedures; smoke tests and post-migration acceptance criteria.
- Plan, runbook and report checks (PLAN-01 to PLAN-10, RUN-01 to RUN-16, REPORT-01 to REPORT-04) with pytest cases
  that plant each mistake; generated evidence E-01 to E-08.
- Report (Markdown and PDF), methodology, ADRs 0001 to 0004, system context and target diagrams, social preview.
- CI calling the shared `gamaware/.github` workflows pinned to a commit SHA, plus OSSF Scorecard.
