#!/usr/bin/env bash
# Apply the member baseline (terraform/live/member) to every active account
# in AWS Organizations - one Terraform workspace per account.
#
#   ACTION=plan  ./scripts/tf-members.sh          # default: show what would change
#   ACTION=apply ./scripts/tf-members.sh          # apply to every account
#   ACTION=apply ./scripts/tf-members.sh 222222222222 333333333333   # only these
#
# Schedule it (nightly CI job) and new or acquired accounts are onboarded
# without anyone touching this repository.
#
#   EXCLUDE   space-separated account IDs to skip (management, log archive, ...)
#   ORG_PROFILE  AWS profile allowed to call organizations:ListAccounts
set -euo pipefail

ACTION="${ACTION:-plan}"
EXCLUDE="${EXCLUDE:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MON="$ROOT/terraform/live/monitoring"
MEM="$ROOT/terraform/live/member"
BACKEND="$ROOT/terraform/backend.hcl"

# Inputs produced by the monitoring configuration.
terraform -chdir="$MON" output -json member_inputs > "$MEM/member.auto.tfvars.json"

if [ "$#" -gt 0 ]; then
  ACCOUNTS="$*"
else
  ACCOUNTS=$(aws organizations list-accounts ${ORG_PROFILE:+--profile "$ORG_PROFILE"} \
    --query "Accounts[?State=='ACTIVE' || Status=='ACTIVE'].Id" --output text)
fi

terraform -chdir="$MEM" init -input=false -reconfigure \
  -backend-config="$BACKEND" -backend-config="key=disk-monitoring/member.tfstate" >/dev/null

failed=()
for id in $ACCOUNTS; do
  case " $EXCLUDE " in *" $id "*) echo "skip $id (excluded)"; continue ;; esac
  echo "==> $id"
  terraform -chdir="$MEM" workspace select -or-create "$id" >/dev/null
  if [ "$ACTION" = "apply" ]; then
    terraform -chdir="$MEM" apply -input=false -auto-approve -var "account_id=$id" || failed+=("$id")
  else
    terraform -chdir="$MEM" plan -input=false -var "account_id=$id" || failed+=("$id")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "Failed accounts: ${failed[*]}" >&2
  exit 1
fi
