#!/bin/bash
# Reinforcement Learning Logger
# Structured logging to both Loki and local files

set -euo pipefail

LOKI_URL="${LOKI_URL:-https://loki.jclee.me}"
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "${LOG_DIR}"

# ============================================================================
# Logging Functions
# ============================================================================

log_to_loki() {
  local level=$1
  local event=$2
  local message=$3
  shift 3
  local extra_labels="$*"

  local timestamp=$(date +%s)000000000
  local labels="{\"job\":\"guardian\",\"level\":\"${level}\",\"event\":\"${event}\""

  # Add extra labels
  if [ -n "$extra_labels" ]; then
    labels="${labels},${extra_labels}"
  fi
  labels="${labels}}"

  curl -s -X POST "${LOKI_URL}/loki/api/v1/push" \
    -H "Content-Type: application/json" \
    -d "{
      \"streams\": [{
        \"stream\": ${labels},
        \"values\": [[\"${timestamp}\", \"${message}\"]]
      }]
    }" > /dev/null 2>&1 || true
}

log_to_file() {
  local level=$1
  local event=$2
  local message=$3

  local log_file="${LOG_DIR}/rl-$(date +%Y%m%d).log"
  echo "[$(date -Iseconds)] [${level}] [${event}] ${message}" >> "${log_file}"
}

log() {
  local level=$1
  local event=$2
  local message=$3
  shift 3

  # Log to both file and Loki
  log_to_file "$level" "$event" "$message"
  log_to_loki "$level" "$event" "$message" "$@"

  # Also echo to stdout
  echo "[${level}] ${message}"
}

# Convenience functions
log_info() {
  log "INFO" "$1" "$2" "${@:3}"
}

log_warn() {
  log "WARN" "$1" "$2" "${@:3}"
}

log_error() {
  log "ERROR" "$1" "$2" "${@:3}"
}

log_metric() {
  local metric_name=$1
  local value=$2
  shift 2
  local labels="$*"

  log "METRIC" "metric_${metric_name}" "${metric_name}=${value}" "$labels"
}

# ============================================================================
# Export functions if sourced
# ============================================================================

if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
  export -f log_to_loki
  export -f log_to_file
  export -f log
  export -f log_info
  export -f log_warn
  export -f log_error
  export -f log_metric
fi

# ============================================================================
# CLI Usage
# ============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-help}" in
    info)
      log_info "$2" "$3" "${@:4}"
      ;;
    warn)
      log_warn "$2" "$3" "${@:4}"
      ;;
    error)
      log_error "$2" "$3" "${@:4}"
      ;;
    metric)
      log_metric "$2" "$3" "${@:4}"
      ;;
    help|*)
      cat <<EOF
RL Logger - Structured logging to Loki and files

Usage:
  $0 info <event> <message> [extra_labels]
  $0 warn <event> <message> [extra_labels]
  $0 error <event> <message> [extra_labels]
  $0 metric <name> <value> [labels]

Examples:
  # Log info
  $0 info training_start "Starting 24h training" "variant=baseline"

  # Log warning
  $0 warn degradation_detected "Autonomous rate dropped 5%" "variant=optimized_tier"

  # Log error
  $0 error rollback_failed "Failed to restore checkpoint" "reason=file_not_found"

  # Log metric
  $0 metric system_health 89.42 "source=prometheus"

Sourcing:
  # Use in other scripts
  source /home/jclee/.claude/scripts/rl-logger.sh
  log_info "my_event" "My message" "key=value"
EOF
      ;;
  esac
fi
