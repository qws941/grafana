#!/bin/bash
# Grafana Monitoring Stack - Metrics Validation Script
# Validates that all metrics used in dashboards actually exist in Prometheus

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# ============================================
# Configuration
# ============================================
readonly PROM_URL="${PROMETHEUS_URL:-https://prometheus.jclee.me}"
readonly DASHBOARDS_DIR="${DASHBOARDS_DIR:-configs/provisioning/dashboards}"
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1

# ============================================
# Metric extraction functions
# ============================================
extract_metrics_from_dashboard() {
  local dashboard_file="$1"
  
  # Extract all expr fields from JSON and get unique metric names
  jq -r '.. | .expr? // empty' "$dashboard_file" 2>/dev/null | \
    grep -oP '^[a-zA-Z_][a-zA-Z0-9_:]*' | \
    sort -u
}

query_metric_exists() {
  local metric="$1"
  local query_url="${PROM_URL}/api/v1/query"
  
  # Query the metric
  local response
  response=$(curl -sf --get --data-urlencode "query=${metric}" "$query_url" 2>&1)
  
  if [ $? -ne 0 ]; then
    return 2  # API error
  fi
  
  # Check if result has data
  local result_count
  result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null)
  
  if [ "$result_count" -gt 0 ]; then
    return 0  # Metric exists
  else
    return 1  # No data
  fi
}

# ============================================
# Validation functions
# ============================================
validate_dashboard_metrics() {
  local dashboard_file="$1"
  local dashboard_name=$(basename "$dashboard_file" .json)
  local failed_metrics=()
  local missing_metrics=()
  
  log_info "Validating: $dashboard_name"
  
  # Extract metrics
  local metrics
  metrics=$(extract_metrics_from_dashboard "$dashboard_file")
  
  if [ -z "$metrics" ]; then
    log_warning "  No metrics found in dashboard"
    return 0
  fi
  
  local total_count=0
  local valid_count=0
  
  # Validate each metric
  while IFS= read -r metric; do
    ((total_count++))
    
    if query_metric_exists "$metric"; then
      ((valid_count++))
      echo "  ✅ $metric"
    else
      if [ $? -eq 2 ]; then
        failed_metrics+=("$metric")
        echo "  ⚠️  $metric (API error)"
      else
        missing_metrics+=("$metric")
        echo "  ❌ $metric (no data)"
      fi
    fi
  done <<< "$metrics"
  
  # Summary
  if [ ${#missing_metrics[@]} -eq 0 ] && [ ${#failed_metrics[@]} -eq 0 ]; then
    log_success "  All $total_count metrics valid"
    return 0
  else
    log_warning "  $valid_count/$total_count metrics valid"
    return 1
  fi
}

validate_all_dashboards() {
  local failed_dashboards=0
  local total_dashboards=0
  
  print_banner
  log_info "Validating metrics in all dashboards..."
  log_info "Prometheus URL: $PROM_URL"
  echo
  
  # Find all dashboard JSON files
  while IFS= read -r dashboard; do
    ((total_dashboards++))
    
    if ! validate_dashboard_metrics "$dashboard"; then
      ((failed_dashboards++))
    fi
    echo
  done < <(find "$DASHBOARDS_DIR" -name "*.json" -type f)
  
  # Final summary
  log_info "Validation complete: $((total_dashboards - failed_dashboards))/$total_dashboards dashboards valid"
  
  if [ $failed_dashboards -eq 0 ]; then
    log_success "✅ All dashboard metrics are valid!"
    return $EXIT_SUCCESS
  else
    log_error "❌ $failed_dashboards dashboard(s) have invalid metrics"
    return $EXIT_VALIDATION_FAILED
  fi
}

list_all_prometheus_metrics() {
  log_info "Fetching all available metrics from Prometheus..."
  
  local label_url="${PROM_URL}/api/v1/label/__name__/values"
  local response
  
  if ! response=$(curl -sf "$label_url" 2>&1); then
    die "Failed to fetch metrics from Prometheus" 1
  fi
  
  echo "$response" | jq -r '.data[]' 2>/dev/null | sort
}

# ============================================
# CLI functions
# ============================================
print_usage() {
  cat << USAGE
Usage: $(basename "$0") [OPTIONS]

Validate that all metrics used in Grafana dashboards exist in Prometheus.

OPTIONS:
  -h, --help              Show this help message
  -l, --list              List all available Prometheus metrics
  -d, --dashboard FILE    Validate specific dashboard file
  -p, --prometheus URL    Prometheus URL (default: https://prometheus.jclee.me)
  
EXAMPLES:
  # Validate all dashboards
  $(basename "$0")
  
  # Validate specific dashboard
  $(basename "$0") -d configs/provisioning/dashboards/core-monitoring/01-monitoring-stack-health.json
  
  # List all available metrics
  $(basename "$0") --list
  
USAGE
}

# ============================================
# Main execution
# ============================================
main() {
  local mode="validate"
  local dashboard_file=""
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_usage
        exit 0
        ;;
      -l|--list)
        mode="list"
        shift
        ;;
      -d|--dashboard)
        mode="validate-single"
        dashboard_file="$2"
        shift 2
        ;;
      -p|--prometheus)
        PROM_URL="$2"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Execute based on mode
  case "$mode" in
    validate)
      validate_all_dashboards
      ;;
    validate-single)
      if [ ! -f "$dashboard_file" ]; then
        die "Dashboard file not found: $dashboard_file" 1
      fi
      validate_dashboard_metrics "$dashboard_file"
      ;;
    list)
      list_all_prometheus_metrics
      ;;
  esac
}

# Execute main function
main "$@"
