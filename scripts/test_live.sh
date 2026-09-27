#!/usr/bin/env bash
# Live test (STANDARD section 7). Manual only: it creates real, billed resources in the sandbox account.
#
#   make test-live            # asks for confirmation after showing the account
#   CONFIRM=yes make test-live
#
# What it does: shows the caller identity of the `dev` profile, runs `terraform test` in
# infra/terraform/tests/live (apply, assert, destroy), then checks that no resource tagged
# purpose=portfolio-test from this run is left and prints any leftover for manual deletion. Logs go to build/live/, which git ignores; never commit them.
# Expected cost: under USD 1 for a run of about 25 minutes (VPN connection, NAT gateways, db.t4g.medium).
set -euo pipefail

PROFILE="${AWS_LIVE_PROFILE:-dev}"
REGION="${AWS_LIVE_REGION:-us-east-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_DIR="$ROOT/infra/terraform/tests/live"
LOG_DIR="$ROOT/build/live"
RUN_ID="$(openssl rand -hex 4)"

mkdir -p "$LOG_DIR"
echo "Live test run $RUN_ID with profile $PROFILE in $REGION"
aws sts get-caller-identity --profile "$PROFILE" --output table

if [[ "${CONFIRM:-}" != "yes" ]]; then
  read -r -p "Create billed test resources in this account? Type yes to continue: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

leftovers() {
  aws resourcegroupstaggingapi get-resources --profile "$PROFILE" --region "$REGION" \
    --tag-filters "Key=purpose,Values=portfolio-test" "Key=run,Values=$RUN_ID" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
}

verify_clean() {
  local status=0 arn state group groups=() arns=()
  # RDS writes its own log groups, untagged, which terraform destroy does not remove.
  read -r -a groups <<< "$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" \
    --log-group-name-prefix "/aws/rds/instance/hg-live-$RUN_ID" \
    --query 'logGroups[].logGroupName' --output text)"
  for group in "${groups[@]}"; do
    [[ "$group" == "None" ]] && continue
    aws logs delete-log-group --profile "$PROFILE" --region "$REGION" --log-group-name "$group"
  done
  local raw
  raw="$(leftovers)" || { echo "Cannot list tagged resources; check them by hand (tag run=$RUN_ID)." >&2; return 1; }
  read -r -a arns <<< "$raw"
  for arn in "${arns[@]}"; do
    [[ "$arn" == "None" ]] && continue
    if [[ "$arn" == *":kms:"* ]]; then
      state="$(aws kms describe-key --profile "$PROFILE" --region "$REGION" --key-id "$arn" \
        --query 'KeyMetadata.KeyState' --output text)"
      [[ "$state" == "PendingDeletion" ]] && continue
    fi
    echo "LEFTOVER $arn" >&2
    status=1
  done
  if (( status == 0 )); then
    echo "Teardown verified: no resource tagged run=$RUN_ID remains (KMS key pending deletion is expected)."
  fi
  return "$status"
}

on_exit() {
  local rc=$?
  # terraform test destroys on success and on assertion failure. Its state lives only in memory, so an interrupted
  # run cannot be destroyed with Terraform afterwards: verify_clean lists what is left, tagged run=<id>, for manual
  # deletion (console Resource Groups tag search or the delete command of each service).
  verify_clean || rc=1
  exit "$rc"
}
trap on_exit EXIT

terraform -chdir="$LIVE_DIR" init -backend=false -input=false >"$LOG_DIR/init-$RUN_ID.log"
terraform -chdir="$LIVE_DIR" test -no-color \
  -var "aws_profile=$PROFILE" -var "region=$REGION" -var "run_id=$RUN_ID" | tee "$LOG_DIR/test-$RUN_ID.log"
