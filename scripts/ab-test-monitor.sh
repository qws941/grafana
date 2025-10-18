#!/bin/bash
# A/B Test Continuous Monitor
# Runs every 5 minutes to check test status and auto-rollback if needed

set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
AB_TEST_DIR="${CLAUDE_HOME}/data/ab-test"
STATUS_FILE="${AB_TEST_DIR}/status.json"
PROMETHEUS_URL="https://prometheus.jclee.me"
LOKI_URL="https://loki.jclee.me"

mkdir -p "${AB_TEST_DIR}"

# Check if test is active
if [ ! -f "${STATUS_FILE}" ]; then
  exit 0
fi

ACTIVE=$(jq -r '.active // false' "${STATUS_FILE}")
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# Get current variant
VARIANT=$(jq -r '.variant' "${STATUS_FILE}")
if [ "$VARIANT" = "baseline" ]; then
  exit 0
fi

# Query metrics
AUTONOMOUS_DELTA=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=guardian_autonomous_rate{variant=\"${VARIANT}\"}-ignoring(variant)guardian_autonomous_rate{variant=\"baseline\"}" | jq -r '.data.result[0].value[1] // "0"')
ROLLBACK_DELTA=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(guardian_rollback_total{variant=\"${VARIANT}\"}[1h])-ignoring(variant)rate(guardian_rollback_total{variant=\"baseline\"}[1h])" | jq -r '.data.result[0].value[1] // "0"')

# Check rollback triggers
if (( $(echo "$AUTONOMOUS_DELTA < -0.05" | bc -l) )) || \
   (( $(echo "$ROLLBACK_DELTA > 0.03" | bc -l) )); then

  echo "[$(date -Iseconds)] 🚨 Rollback triggered: autonomous=${AUTONOMOUS_DELTA}, rollback=${ROLLBACK_DELTA}"

  # Execute rollback
  bash "${CLAUDE_HOME}/scripts/ab-test-manager.sh" stop "degradation_detected"

  # Send alert to Loki
  curl -s -X POST "${LOKI_URL}/loki/api/v1/push" \
    -H "Content-Type: application/json" \
    -d "{
      \"streams\": [{
        \"stream\": {
          \"job\": \"guardian\",
          \"event\": \"ab_test_rollback\",
          \"severity\": \"critical\"
        },
        \"values\": [[\"$(date +%s)000000000\", \"EMERGENCY ROLLBACK: variant=${VARIANT} autonomous_delta=${AUTONOMOUS_DELTA} rollback_delta=${ROLLBACK_DELTA}\"]]
      }]
    }" || true

  # TODO: Send Slack alert

fi
