#!/usr/bin/env bash
set -euo pipefail

# Optional callbacks (for workflow/local runs)
CALLBACK_URL="${CALLBACK_URL:-}"
CALLBACK_TOKEN="${CALLBACK_TOKEN:-}"
CALLBACK_STEP="${CALLBACK_STEP:-QBT_RUN}"

send_callback() {
  local status="$1"
  if [ -z "$CALLBACK_URL" ]; then
    return 0
  fi

  local payload
  payload=$(printf '{"step":"%s","stepStatus":"%s"}' "$CALLBACK_STEP" "$status")

  local headers=()
  headers+=(-H "Content-Type: application/json")
  if [ -n "$CALLBACK_TOKEN" ]; then
    headers+=(-H "Authorization: Bearer $CALLBACK_TOKEN")
  fi

  curl -sS -m 10 -X POST "${headers[@]}" -d "$payload" "$CALLBACK_URL" >/dev/null || true
}

send_callback "PENDING"

# Use project-local profiles.yml unless DBT_PROFILES_DIR is already set.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-$SCRIPT_DIR}"

# Required env vars for BigQuery profile + QuickBooks sources.
: "${DBT_GCP_PROJECT:?Set DBT_GCP_PROJECT}"
: "${DBT_RAW_DATASET:?Set DBT_RAW_DATASET}"
: "${DBT_ANALYTICS_DATASET:?Set DBT_ANALYTICS_DATASET}"

# Default raw project to target project if not provided.
DBT_RAW_PROJECT="${DBT_RAW_PROJECT:-$DBT_GCP_PROJECT}"

# Default command if none provided.
args=("$@")
if [ ${#args[@]} -eq 0 ]; then
  args=(run)
fi

# Inject vars unless the caller already provided --vars.
# Use package-scoped vars so the script works cleanly when this package
# is installed in another repo or run directly.
vars_arg=()
if ! printf '%s\n' "${args[@]}" | grep -q -- '--vars'; then
  vars_arg=(--vars "quickbooks:
  quickbooks_database: ${DBT_RAW_PROJECT}
  quickbooks_schema: ${DBT_RAW_DATASET}
  using_credit_card_payment_txn: true
  using_purchase_order: true
  using_purchase_tax_line: true
  using_tax_agency: true
  using_tax_rate: true")
fi

send_callback "RUNNING"
set +e
dbt "${args[@]}" "${vars_arg[@]}"
dbt_status=$?
set -e

if [ $dbt_status -eq 0 ]; then
  send_callback "SUCCEEDED"
else
  send_callback "FAILED"
fi

exit $dbt_status
