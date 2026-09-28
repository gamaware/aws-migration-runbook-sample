#!/usr/bin/env bash
# Live test (STANDARD section 7). Manual only: it creates real, billed resources in the sandbox account.
#
#   make test-live            # asks for confirmation after showing the account
#   CONFIRM=yes make test-live
#   TEST_LIVE_EXTRA_TAGS="Key1=value1,Key2=value2"   # tags the account requires on every create; never commit values
#
# What it does: shows the caller identity of the `dev` profile, plans infra/terraform/tests/live and refuses to go on
# if scripts/check_private_plan.py finds anything internet-facing in that plan (private-only, ADR 0005), applies that
# exact plan, asserts on its outputs, destroys it, then checks that no resource tagged purpose=portfolio-test from
# this run is left and prints any leftover for manual deletion. If the destroy fails (an expired SSO session, for
# example), the state stays in build/live/ so the destroy can be run again. Logs, the plan and the state go to
# build/live/, which git ignores; never commit them.
# Expected cost: under USD 1 for a run of about 25 minutes (VPN connection, db.t4g.medium; no NAT gateway).
set -euo pipefail

PROFILE="${AWS_LIVE_PROFILE:-dev}"
REGION="${AWS_LIVE_REGION:-us-east-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_DIR="$ROOT/infra/terraform/tests/live"
LOG_DIR="$ROOT/build/live"
RUN_ID="$(openssl rand -hex 4)"

# Extra tags become a Terraform map; keys and values are limited to plain characters so they cannot break the HCL.
EXTRA_TAGS_HCL=""
IFS=',' read -r -a extra_pairs <<< "${TEST_LIVE_EXTRA_TAGS:-}"
for pair in "${extra_pairs[@]}"; do
  key="${pair%%=*}"
  value="${pair#*=}"
  if [[ "$pair" != *=* || ! "$key" =~ ^[A-Za-z0-9_.:/+@-]+$ || ! "$value" =~ ^[A-Za-z0-9_.:/+@=\ -]*$ ]]; then
    echo "TEST_LIVE_EXTRA_TAGS: '$pair' is not Key=value with plain characters" >&2
    exit 1
  fi
  EXTRA_TAGS_HCL+="${EXTRA_TAGS_HCL:+,}\"$key\"=\"$value\""
done

mkdir -p "$LOG_DIR"
echo "Live test run $RUN_ID with profile $PROFILE in $REGION"
aws sts get-caller-identity --profile "$PROFILE" --output table

if [[ "${CONFIRM:-}" != "yes" ]]; then
  read -r -p "Create billed test resources in this account? Type yes to continue: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

LIVE_VARS=(-var "aws_profile=$PROFILE" -var "region=$REGION" -var "run_id=$RUN_ID" -var "extra_tags={$EXTRA_TAGS_HCL}")
PLAN_FILE="$LOG_DIR/plan-$RUN_ID.bin"
PLAN_JSON="$LOG_DIR/plan-$RUN_ID.json"
STATE="$LOG_DIR/state-$RUN_ID.tfstate"

leftovers() {
  aws resourcegroupstaggingapi get-resources --profile "$PROFILE" --region "$REGION" \
    --tag-filters "Key=purpose,Values=portfolio-test" "Key=run,Values=$RUN_ID" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
}

# The tagging API keeps deleted resources listed for a while, so ask the owning service whether an ARN still exists.
# Types without a check here count as present.
still_exists() {
  local arn="$1" id="${1##*[:/]}"
  local aws_cli=(aws --profile "$PROFILE" --region "$REGION")
  case "$arn" in
    *:kms:*)
      [[ "$("${aws_cli[@]}" kms describe-key --key-id "$arn" --query 'KeyMetadata.KeyState' --output text)" \
        != "PendingDeletion" ]] ;;
    *:rds:*:db:*)
      "${aws_cli[@]}" rds describe-db-instances --db-instance-identifier "$id" > /dev/null 2>&1 ;;
    *:vpn-connection/*)
      [[ "$("${aws_cli[@]}" ec2 describe-vpn-connections --filters "Name=vpn-connection-id,Values=$id" \
        --query "VpnConnections[?State!='deleted'] | length(@)" --output text)" != "0" ]] ;;
    *:vpn-gateway/*)
      [[ "$("${aws_cli[@]}" ec2 describe-vpn-gateways --filters "Name=vpn-gateway-id,Values=$id" \
        --query "VpnGateways[?State!='deleted'] | length(@)" --output text)" != "0" ]] ;;
    *:customer-gateway/*)
      [[ "$("${aws_cli[@]}" ec2 describe-customer-gateways --filters "Name=customer-gateway-id,Values=$id" \
        --query "CustomerGateways[?State!='deleted'] | length(@)" --output text)" != "0" ]] ;;
    # EC2 drops the tags of a deleted resource at once, so describe-tags answers for the rest of the EC2 types.
    *:ec2:*)
      [[ "$("${aws_cli[@]}" ec2 describe-tags --filters "Name=resource-id,Values=$id" \
        --query 'length(Tags)' --output text)" != "0" ]] ;;
    *) true ;;
  esac
}

verify_clean() {
  local status=0 arn group groups=() arns=()
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
    if still_exists "$arn"; then
      echo "LEFTOVER $arn" >&2
      status=1
    fi
  done
  if (( status == 0 )); then
    echo "Teardown verified: no resource tagged run=$RUN_ID remains (KMS key pending deletion is expected)."
  fi
  return "$status"
}

on_exit() {
  local rc=$?
  set +e
  if [[ -f "$STATE" ]]; then
    echo "--- destroy"
    if terraform -chdir="$LIVE_DIR" destroy -input=false -auto-approve -no-color -state="$STATE" "${LIVE_VARS[@]}" \
      > "$LOG_DIR/destroy-$RUN_ID.log" 2>&1; then
      tail -n 1 "$LOG_DIR/destroy-$RUN_ID.log"
      rm -f "$STATE" "$STATE.backup"
    else
      tail -n 20 "$LOG_DIR/destroy-$RUN_ID.log" >&2
      echo "FAIL: destroy did not complete. The state is kept in $STATE; retry with:" >&2
      echo "  terraform -chdir=$LIVE_DIR destroy -state=$STATE -var aws_profile=$PROFILE -var region=$REGION -var run_id=$RUN_ID" >&2
      exit 1
    fi
  fi
  verify_clean || rc=1
  exit "$rc"
}
trap on_exit EXIT

terraform -chdir="$LIVE_DIR" init -backend=false -input=false >"$LOG_DIR/init-$RUN_ID.log"

# Pre-flight: plan, and refuse the run before anything exists if the plan contains an internet-facing resource.
# A plan creates nothing. The apply below uses this exact plan file.
terraform -chdir="$LIVE_DIR" plan -input=false -no-color -state="$STATE" -out="$PLAN_FILE" "${LIVE_VARS[@]}" \
  >"$LOG_DIR/plan-$RUN_ID.log"
terraform -chdir="$LIVE_DIR" show -json "$PLAN_FILE" >"$PLAN_JSON"
if ! python3 "$ROOT/scripts/check_private_plan.py" "$PLAN_JSON"; then
  echo "Live test refused: the plan is not private-only. Nothing was created." >&2
  exit 1
fi

echo "--- apply (the plan checked above)"
if ! terraform -chdir="$LIVE_DIR" apply -input=false -no-color -state-out="$STATE" "$PLAN_FILE" \
  > "$LOG_DIR/apply-$RUN_ID.log" 2>&1; then
  grep -A3 'Error' "$LOG_DIR/apply-$RUN_ID.log" >&2
  echo "FAIL: apply did not complete" >&2
  exit 1
fi
grep '^Apply complete' "$LOG_DIR/apply-$RUN_ID.log"

# Assertions on what the AWS APIs returned to Terraform; nothing is sent over the internet to the resources.
out() {
  terraform -chdir="$LIVE_DIR" output -state="$STATE" -raw "$1"
}
database_address="$(out database_address)"
vpn_connection_id="$(out vpn_connection_id)"
[[ "$database_address" =~ \.rds\.amazonaws\.com$ ]] || { echo "FAIL: RDS did not return an endpoint" >&2; exit 1; }
echo "ok   RDS endpoint returned"
[[ "$vpn_connection_id" == vpn-* ]] || { echo "FAIL: AWS rejected the VPN connection or its tunnel options" >&2; exit 1; }
echo "ok   VPN connection $vpn_connection_id created"
[[ "$(aws rds describe-db-instances --profile "$PROFILE" --region "$REGION" --db-instance-identifier "hg-live-$RUN_ID" \
  --query 'DBInstances[0].PubliclyAccessible' --output text)" == "False" ]] \
  || { echo "FAIL: the database is publicly accessible" >&2; exit 1; }
echo "ok   database not publicly accessible"
echo "--- live test passed"
