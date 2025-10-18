#!/bin/bash
# Guardian Metrics Instrumentation
# Emits Prometheus metrics for Guardian cognitive operations

set -euo pipefail

PUSHGATEWAY="${PUSHGATEWAY:-http://localhost:9091}"
JOB_NAME="guardian"

# Source RL logger for structured logging
if [ -f "${HOME}/.claude/scripts/rl-logger.sh" ]; then
  source "${HOME}/.claude/scripts/rl-logger.sh"
fi

# ============================================================================
# Metric Emission Functions
# ============================================================================

emit_decision_confidence() {
  local confidence=$1  # 0-100
  local tier=${2:-0}

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/tier/${tier}" 2>/dev/null || true
# TYPE guardian_decision_confidence_score gauge
# HELP guardian_decision_confidence_score Decision confidence (0-100)
guardian_decision_confidence_score ${confidence}
METRICS

  log_metric "decision_confidence" "${confidence}" "tier=\"${tier}\""
}

emit_alternative_paths() {
  local count=$1
  local tier=${2:-0}

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/tier/${tier}" 2>/dev/null || true
# TYPE guardian_alternative_paths_considered_total counter
# HELP guardian_alternative_paths_considered_total Number of alternative paths considered
guardian_alternative_paths_considered_total ${count}
METRICS

  log_metric "alternative_paths" "${count}" "tier=\"${tier}\""
}

emit_verification_failure() {
  local reason=$1

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/reason/${reason}" 2>/dev/null || true
# TYPE guardian_verification_failure_reasons_total counter
# HELP guardian_verification_failure_reasons_total Verification failures by reason
guardian_verification_failure_reasons_total 1
METRICS

  log_metric "verification_failure" "1" "reason=\"${reason}\""
}

emit_resource_pressure() {
  local pressure=$1  # 0-100

  # Calculate pressure based on system metrics
  local mem_usage=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
  local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
  local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

  # Weighted average: memory 40%, CPU 30%, disk 30%
  local calculated_pressure=$(echo "scale=2; ($mem_usage * 0.4) + ($cpu_load * 10 * 0.3) + ($disk_usage * 0.3)" | bc)

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}" 2>/dev/null || true
# TYPE guardian_system_resource_pressure_score gauge
# HELP guardian_system_resource_pressure_score System resource pressure (0-100)
guardian_system_resource_pressure_score ${calculated_pressure}
METRICS

  log_metric "resource_pressure" "${calculated_pressure}" "mem=\"${mem_usage}\" cpu_load=\"${cpu_load}\" disk=\"${disk_usage}\""
}

emit_ai_agent_metrics() {
  local agent=$1
  local model=$2
  local prompt_tokens=$3
  local quality_score=$4  # 0-100
  local quota_remaining=${5:-999999}

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/agent/${agent}/model/${model}" 2>/dev/null || true
# TYPE ai_agent_prompt_token_count histogram
# HELP ai_agent_prompt_token_count AI agent prompt token distribution
ai_agent_prompt_token_count_bucket{le="1000"} 0
ai_agent_prompt_token_count_bucket{le="5000"} 0
ai_agent_prompt_token_count_bucket{le="10000"} 0
ai_agent_prompt_token_count_bucket{le="+Inf"} 1
ai_agent_prompt_token_count_sum ${prompt_tokens}
ai_agent_prompt_token_count_count 1

# TYPE ai_agent_response_quality_score gauge
# HELP ai_agent_response_quality_score AI agent response quality (0-100)
ai_agent_response_quality_score ${quality_score}

# TYPE ai_agent_model_quota_remaining gauge
# HELP ai_agent_model_quota_remaining AI model quota remaining
ai_agent_model_quota_remaining ${quota_remaining}
METRICS

  log_metric "ai_agent_invocation" "1" "agent=\"${agent}\" model=\"${model}\" tokens=\"${prompt_tokens}\" quality=\"${quality_score}\""
}

emit_autonomous_rate() {
  local rate=$1  # 0.0-1.0
  local variant=${2:-"baseline"}

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/variant/${variant}" 2>/dev/null || true
# TYPE guardian_autonomous_rate gauge
# HELP guardian_autonomous_rate Percentage of autonomous decisions (Tier 0/1)
guardian_autonomous_rate ${rate}
METRICS

  log_metric "autonomous_rate" "${rate}" "variant=\"${variant}\""
}

emit_rollback_event() {
  local reason=$1
  local variant=${2:-"baseline"}

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/variant/${variant}" 2>/dev/null || true
# TYPE guardian_rollback_total counter
# HELP guardian_rollback_total Total checkpoint rollbacks
guardian_rollback_total 1
METRICS

  log_error "rollback_triggered" "Rollback: ${reason}" "variant=\"${variant}\""
}

# ============================================================================
# A/B Testing Metrics
# ============================================================================

emit_ab_test_metrics() {
  local variant=$1
  local success_rate=$2  # 0.0-1.0
  local stage=$3  # 0.1, 0.5, 1.0
  local promotion_ready=$4  # 0 or 1

  cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/job/${JOB_NAME}/variant/${variant}" 2>/dev/null || true
# TYPE ab_test_variant_success_rate gauge
# HELP ab_test_variant_success_rate A/B test variant success rate
ab_test_variant_success_rate ${success_rate}

# TYPE ab_test_current_stage gauge
# HELP ab_test_current_stage Current A/B test stage (0.1, 0.5, 1.0)
ab_test_current_stage ${stage}

# TYPE ab_test_promotion_readiness gauge
# HELP ab_test_promotion_readiness Whether variant is ready for promotion (0/1)
ab_test_promotion_readiness ${promotion_ready}

# TYPE ab_test_start_timestamp gauge
# HELP ab_test_start_timestamp Unix timestamp when A/B test started
ab_test_start_timestamp $(date +%s)
METRICS

  log_info "ab_test_metrics" "Variant: ${variant}, Success: ${success_rate}, Stage: ${stage}, Ready: ${promotion_ready}" \
    "variant=\"${variant}\""
}

# ============================================================================
# CLI Usage
# ============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-help}" in
    decision)
      emit_decision_confidence "${2}" "${3:-0}"
      ;;
    alternatives)
      emit_alternative_paths "${2}" "${3:-0}"
      ;;
    verification-failure)
      emit_verification_failure "${2}"
      ;;
    resource-pressure)
      emit_resource_pressure
      ;;
    ai-agent)
      emit_ai_agent_metrics "${2}" "${3}" "${4}" "${5}" "${6:-999999}"
      ;;
    autonomous-rate)
      emit_autonomous_rate "${2}" "${3:-baseline}"
      ;;
    rollback)
      emit_rollback_event "${2}" "${3:-baseline}"
      ;;
    ab-test)
      emit_ab_test_metrics "${2}" "${3}" "${4}" "${5}"
      ;;
    help|*)
      cat <<EOF
Guardian Metrics Instrumentation

Usage:
  $0 decision <confidence_0-100> [tier]
  $0 alternatives <count> [tier]
  $0 verification-failure <reason>
  $0 resource-pressure
  $0 ai-agent <agent> <model> <tokens> <quality_0-100> [quota]
  $0 autonomous-rate <rate_0-1> [variant]
  $0 rollback <reason> [variant]
  $0 ab-test <variant> <success_rate_0-1> <stage> <ready_0-1>

Examples:
  # Decision made with 85% confidence (Tier 0)
  $0 decision 85 0

  # Considered 3 alternative paths
  $0 alternatives 3 1

  # Verification failed due to tests
  $0 verification-failure "tests_failed"

  # Check system resource pressure
  $0 resource-pressure

  # AI agent invocation
  $0 ai-agent "grok-code-reviewer" "grok-code-fast-1" 1234 92 50

  # Autonomous rate 95%
  $0 autonomous-rate 0.95 baseline

  # Rollback triggered
  $0 rollback "degradation_detected" "optimized_tier"

  # A/B test metrics
  $0 ab-test "optimized_tier" 0.97 0.1 0

Sourcing:
  # Use in other scripts
  source ${BASH_SOURCE[0]}
  emit_decision_confidence 90 0
EOF
      ;;
  esac
fi

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
  export -f emit_decision_confidence
  export -f emit_alternative_paths
  export -f emit_verification_failure
  export -f emit_resource_pressure
  export -f emit_ai_agent_metrics
  export -f emit_autonomous_rate
  export -f emit_rollback_event
  export -f emit_ab_test_metrics
fi
