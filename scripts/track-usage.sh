#!/bin/bash
#
# Track AI Usage - Record real AI API usage to metrics exporter
# Usage: ./track-usage.sh <provider> <model> <input_tokens> <output_tokens> [operation] [duration_ms]
#

set -euo pipefail

METRICS_URL="${METRICS_URL:-http://localhost:9091/usage}"

if [ $# -lt 4 ]; then
    echo "Usage: $0 <provider> <model> <input_tokens> <output_tokens> [operation] [duration_ms]"
    echo ""
    echo "Examples:"
    echo "  $0 claude claude-sonnet-4-5 5000 2000"
    echo "  $0 grok grok-code-fast-1 3000 1500 chat 2300"
    echo "  $0 gemini gemini-2.5-pro 8000 3500 chat 4200"
    exit 1
fi

PROVIDER="$1"
MODEL="$2"
INPUT_TOKENS="$3"
OUTPUT_TOKENS="$4"
OPERATION="${5:-chat}"
DURATION_MS="${6:-}"

# Build JSON payload
JSON=$(cat <<EOF
{
  "provider": "$PROVIDER",
  "model": "$MODEL",
  "operation": "$OPERATION",
  "status": "success",
  "inputTokens": $INPUT_TOKENS,
  "outputTokens": $OUTPUT_TOKENS
EOF
)

if [ -n "$DURATION_MS" ]; then
    JSON="$JSON,\"durationMs\": $DURATION_MS"
fi

JSON="$JSON}"

# Send to metrics exporter
RESPONSE=$(curl -s -X POST "$METRICS_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON")

# Parse response
if echo "$RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
    COST=$(echo "$RESPONSE" | jq -r '.cost')
    echo "✅ Recorded: $PROVIDER/$MODEL - ${INPUT_TOKENS}in + ${OUTPUT_TOKENS}out = \$$COST"
else
    echo "❌ Failed: $RESPONSE"
    exit 1
fi
