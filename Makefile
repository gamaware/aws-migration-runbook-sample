# Every target except test-live runs offline: no AWS account, no credentials. CI runs `make verify`, so a green
# local run means a green pipeline. Tool downloads (Python packages, the Terraform provider, the TFLint ruleset)
# happen on first use and are cached.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := verify

PYTHON    := uv run --quiet --frozen python
PYTEST    := uv run --quiet --frozen pytest
RUFF      := uvx --quiet ruff@0.16.9
CHECKOV   := uvx --quiet checkov==3.3.19
TERRAFORM ?= terraform
TFLINT    ?= tflint
BUILD     := build

TF_MODULES := network app database dms dns
TF_ROOTS   := $(addprefix infra/terraform/modules/,$(TF_MODULES)) infra/terraform/envs/production
TF_VALIDATE_ONLY := infra/terraform/tests/live

export TF_IN_AUTOMATION := 1
export TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache

.PHONY: verify python-lint test plan-check runbook-check evidence evidence-check terraform tflint checkov \
	report-check report sql-check test-live clean

## verify: every offline check, in the order CI runs them
verify: python-lint test plan-check runbook-check terraform tflint checkov evidence-check report-check
	@echo "verify: all checks passed"

## python-lint: ruff lint and format check on scripts/ and tests/
python-lint:
	$(RUFF) check scripts tests
	$(RUFF) format --check scripts tests

## test: pytest; every plan and runbook rule is shown to fail on the mistake it exists to catch
test:
	$(PYTEST)

## plan-check: inventory, 7R classification, waves, sizing and DMS tasks agree (PLAN-01 to PLAN-10)
plan-check:
	$(PYTHON) scripts/check_plan.py

## runbook-check: runbook structure, timeline, rollback coverage and agreement with the plan (RUN-01 to RUN-16)
runbook-check:
	$(PYTHON) scripts/check_runbook.py

## terraform: fmt, validate and the mocked terraform test suite in every root; writes build/evidence/E-08
terraform: | $(BUILD)/evidence
	@mkdir -p "$(TF_PLUGIN_CACHE_DIR)"
	$(TERRAFORM) fmt -check -recursive infra/terraform
	@: > $(BUILD)/evidence/E-08-terraform-tests.txt
	@for root in $(TF_ROOTS); do \
	  echo "== $$root"; \
	  $(TERRAFORM) -chdir=$$root init -backend=false -input=false -lockfile=readonly > /dev/null; \
	  $(TERRAFORM) -chdir=$$root validate -no-color; \
	  echo "== $$root" >> $(BUILD)/evidence/E-08-terraform-tests.txt; \
	  $(TERRAFORM) -chdir=$$root test -no-color | grep -v '^$$' | tee -a $(BUILD)/evidence/E-08-terraform-tests.txt; \
	done
	@for root in $(TF_VALIDATE_ONLY); do \
	  $(TERRAFORM) -chdir=$$root init -backend=false -input=false -lockfile=readonly > /dev/null; \
	  $(TERRAFORM) -chdir=$$root validate -no-color; \
	done

## tflint: terraform and AWS rulesets on every module
tflint:
	$(TFLINT) --init --config "$(CURDIR)/.tflint.hcl" > /dev/null
	$(TFLINT) --recursive --config "$(CURDIR)/.tflint.hcl" --chdir infra/terraform --format compact

## checkov: IaC policy scan; each skip sits next to its resource with a reason
checkov:
	$(CHECKOV) --config-file .checkov.yaml

## evidence: regenerate evidence/ (E-01 to E-08); review the diff before committing
evidence: terraform
	$(PYTHON) scripts/build_evidence.py --out evidence
	cp $(BUILD)/evidence/E-08-terraform-tests.txt evidence/

## evidence-check: rebuild the evidence into build/ and fail if it differs from the committed copy
evidence-check: terraform
	$(PYTHON) scripts/build_evidence.py --out $(BUILD)/evidence > /dev/null
	diff -ru evidence $(BUILD)/evidence

## report-check: report cites existing evidence, carries its fictional label, local links resolve
report-check:
	$(PYTHON) scripts/check_report.py

## report: render report/REPORT.pdf from report/REPORT.md with the pandoc/latex image CI uses (needs Docker)
report:
	scripts/build_report.sh

## sql-check: run the validation queries on PostgreSQL 14 and 16 in Docker (not part of verify)
sql-check:
	scripts/sql_check.sh

## test-live: MANUAL. Real AWS in the dev sandbox profile, tagged purpose=portfolio-test, destroyed in the same run
test-live:
	scripts/test_live.sh

$(BUILD)/evidence:
	mkdir -p $@

clean:
	rm -rf $(BUILD) .pytest_cache .ruff_cache
