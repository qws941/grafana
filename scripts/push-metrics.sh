#!/bin/bash
# Push metrics to Prometheus Pushgateway
# Usage: push-metrics.sh <metric_name> <value> [labels]

set -euo pipefail

PUSHGATEWAY="http://localhost:9091"  # Assumes Pushgateway on localhost
METRIC_NAME=$1
VALUE=$2
LABELS=${3:-""}

if [ -n "$LABELS" ]; then
  INSTANCE="${LABELS}"
else
  INSTANCE="job=\"guardian\""
fi

cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/${INSTANCE}"
# TYPE ${METRIC_NAME} gauge
${METRIC_NAME} ${VALUE}
METRICS
