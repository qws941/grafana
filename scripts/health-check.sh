#!/bin/bash
# Grafana Monitoring Stack - Health Check Script
# Validates all services are healthy and operational

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# ============================================
# Configuration
# ============================================
readonly SERVICES=(
  "https://grafana.jclee.me/api/health|Grafana"
  "https://prometheus.jclee.me/-/healthy|Prometheus"
  "https://loki.jclee.me/ready|Loki"
  "https://alertmanager.jclee.me/-/healthy|AlertManager"
)

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_SERVICE_UNHEALTHY=1
readonly EXIT_PARTIAL_FAILURE=2

# ============================================
# Health check functions
# ============================================
check_all_services() {
  local failed_count=0
  local total_count=${#SERVICES[@]}
  
  print_banner
  log_info "Checking health of $total_count services..."
  echo
  
  for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r url name <<< "$service_info"
    
    if check_service_health "$url" "$name"; then
      echo "✅ $name: OK"
    else
      echo "❌ $name: FAILED"
      ((failed_count++))
    fi
  done
  
  echo
  log_info "Results: $((total_count - failed_count))/$total_count services healthy"
  
  if [ $failed_count -eq 0 ]; then
    log_success "All services are healthy!"
    return $EXIT_SUCCESS
  elif [ $failed_count -eq $total_count ]; then
    log_error "All services are unhealthy!"
    return $EXIT_SERVICE_UNHEALTHY
  else
    log_warning "$failed_count service(s) unhealthy"
    return $EXIT_PARTIAL_FAILURE
  fi
}

check_prometheus_targets() {
  log_info "Checking Prometheus targets..."
  
  local targets_url="https://prometheus.jclee.me/api/v1/targets"
  local response
  
  if ! response=$(curl -sf "$targets_url" 2>&1); then
    log_error "Failed to query Prometheus targets API"
    return 1
  fi
  
  local down_targets=$(echo "$response" | jq -r '.data.activeTargets[] | select(.health != "up") | .labels.job' 2>/dev/null)
  
  if [ -z "$down_targets" ]; then
    log_success "All Prometheus targets are up"
    return 0
  else
    log_error "Down targets detected:"
    echo "$down_targets" | while read -r job; do
      echo "  ❌ $job"
    done
    return 1
  fi
}

check_loki_ingestion() {
  log_info "Checking Loki log ingestion..."
  
  local query_url="https://loki.jclee.me/loki/api/v1/query"
  local query='rate({job=~".+"}[5m])'
  local response
  
  if ! response=$(curl -sf --get --data-urlencode "query=$query" "$query_url" 2>&1); then
    log_error "Failed to query Loki API"
    return 1
  fi
  
  local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null)
  
  if [ "$result_count" -gt 0 ]; then
    log_success "Loki is ingesting logs ($result_count streams active)"
    return 0
  else
    log_warning "No active log streams found in Loki"
    return 1
  fi
}

check_grafana_dashboards() {
  log_info "Checking Grafana dashboards..."
  
  local dashboards_url="https://grafana.jclee.me/api/search?type=dash-db"
  local response
  
  # Note: This requires authentication, may fail if not configured
  if ! response=$(curl -sf "$dashboards_url" 2>&1); then
    log_warning "Cannot check dashboards (authentication required)"
    return 0  # Non-critical
  fi
  
  local dashboard_count=$(echo "$response" | jq -r '. | length' 2>/dev/null)
  
  if [ "$dashboard_count" -gt 0 ]; then
    log_success "Found $dashboard_count dashboards"
    return 0
  else
    log_warning "No dashboards found"
    return 1
  fi
}

# ============================================
# Docker compose validation
# ============================================
check_compose_config() {
  log_info "Validating docker-compose configuration..."
  
  if ! docker compose config > /dev/null 2>&1; then
    log_error "docker-compose.yml has syntax errors"
    return 1
  fi
  
  log_success "docker-compose.yml is valid"
  return 0
}

# ============================================
# Main execution
# ============================================
main() {
  local exit_code=0
  
  # Check docker compose configuration
  check_compose_config || exit_code=1
  echo
  
  # Check all services
  check_all_services || exit_code=$?
  echo
  
  # Check Prometheus targets
  if [ $exit_code -eq 0 ]; then
    check_prometheus_targets || exit_code=2
    echo
  fi
  
  # Check Loki ingestion
  if [ $exit_code -eq 0 ]; then
    check_loki_ingestion || exit_code=2
    echo
  fi
  
  # Summary
  if [ $exit_code -eq 0 ]; then
    log_success "✅ All health checks passed!"
  else
    log_error "⚠️  Some health checks failed (exit code: $exit_code)"
  fi
  
  return $exit_code
}

# Execute main function
main "$@"
