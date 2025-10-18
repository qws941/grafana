#!/bin/bash
# Unified Log Collection Verification Tool
# Combines quick health check and detailed verification
# Usage: ./log-collection-check.sh [--quick|--full]

set -euo pipefail

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || {
    # Fallback colors if common.sh not available
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}ℹ${NC} $*"; }
    log_success() { echo -e "${GREEN}✅${NC} $*"; }
    log_error() { echo -e "${RED}❌${NC} $*"; }
    log_warning() { echo -e "${YELLOW}⚠️${NC}  $*"; }
}

# Configuration
SYNOLOGY_HOST="${SYNOLOGY_HOST:-192.168.50.215}"
SYNOLOGY_PORT="${SYNOLOGY_PORT:-1111}"
SYNOLOGY_USER="${SYNOLOGY_USER:-jclee}"
GRAFANA_API="https://grafana.jclee.me"
PROMETHEUS_API="https://prometheus.jclee.me"
LOKI_API="https://loki.jclee.me"

# Mode selection
MODE="${1:---quick}"

# Critical services that must have logs
CRITICAL_SERVICES=(
    "grafana-container"
    "prometheus-container"
    "loki-container"
    "alertmanager-container"
    "promtail-container"
    "n8n-container"
    "n8n-postgres-container"
    "n8n-redis-container"
    "node-exporter-container"
    "cadvisor-container"
)

# SSH helper
ssh_exec() {
    ssh -p "${SYNOLOGY_PORT}" "${SYNOLOGY_USER}@${SYNOLOGY_HOST}" "$@" 2>/dev/null
}

# Docker helper
docker_exec() {
    ssh_exec "sudo docker exec $*"
}

# Prometheus query helper
query_prometheus() {
    local query="$1"
    curl -sf "${PROMETHEUS_API}/api/v1/query?query=${query}" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0"
}

# Quick health check
quick_check() {
    log_info "Running Quick Health Check"
    echo "==============================="
    echo ""

    # 1. Promtail status
    echo "1️⃣  Promtail Status"
    PROMTAIL_STATUS=$(ssh_exec "sudo docker ps --filter name=promtail --format '{{.Status}}'" | head -1)
    if [[ $PROMTAIL_STATUS == Up* ]]; then
        log_success "Promtail: $PROMTAIL_STATUS"
    else
        log_error "Promtail: Not running"
        return 1
    fi
    echo ""

    # 2. Log ingestion rate
    echo "2️⃣  Log Ingestion Rate"
    LOG_RATE=$(query_prometheus "rate(loki_distributor_lines_received_total[5m])")
    if (( $(echo "$LOG_RATE > 0" | bc -l 2>/dev/null || echo "0") )); then
        log_success "Ingestion: $LOG_RATE lines/sec"
    else
        log_warning "No logs being ingested"
    fi
    echo ""

    # 3. Recent Promtail errors
    echo "3️⃣  Promtail Errors (last 20 lines)"
    ERROR_COUNT=$(docker_exec promtail-container cat /tmp/positions.yaml 2>/dev/null | wc -l || echo "0")
    RECENT_ERRORS=$(ssh_exec "sudo docker logs promtail-container --tail 100 2>&1" | grep -icE 'error|warn|fail' || echo "0")

    if [ "$RECENT_ERRORS" -eq 0 ]; then
        log_success "No errors found"
    else
        log_warning "$RECENT_ERRORS warnings/errors in last 100 lines"
        ssh_exec "sudo docker logs promtail-container --tail 100 2>&1" | grep -iE 'error|warn|fail' | tail -5
    fi
    echo ""

    # 4. Summary
    echo "📊 Quick Summary"
    echo "==============================="
    echo "Promtail: $(echo $PROMTAIL_STATUS | cut -d' ' -f1-2)"
    echo "Log Rate: $LOG_RATE lines/sec"
    echo "Recent Errors: $RECENT_ERRORS"
    echo ""
}

# Full verification
full_check() {
    log_info "Running Full Verification"
    echo "==============================="
    echo ""

    # Run quick check first
    if ! quick_check; then
        log_error "Quick check failed, aborting full verification"
        return 1
    fi

    # 5. Check running containers
    echo "5️⃣  Running Containers"
    CONTAINERS=$(ssh_exec "sudo docker ps --format '{{.Names}}'" | sort)
    TOTAL_CONTAINERS=$(echo "$CONTAINERS" | wc -l)
    log_info "Total: $TOTAL_CONTAINERS containers"
    echo "$CONTAINERS" | nl
    echo ""

    # 6. Check Loki labels
    echo "6️⃣  Loki Labels Verification"
    LABELS=$(curl -sf "$LOKI_API/loki/api/v1/labels" 2>/dev/null | jq -r '.data[]' 2>/dev/null | sort)

    REQUIRED_LABELS=("service_type" "criticality" "container_name" "job")
    for label in "${REQUIRED_LABELS[@]}"; do
        if echo "$LABELS" | grep -q "$label"; then
            log_success "$label label found"
        else
            log_warning "$label label NOT found"
        fi
    done
    echo ""

    # 7. Test label queries
    echo "7️⃣  Testing Label Queries"
    if echo "$LABELS" | grep -q "service_type"; then
        for TYPE in monitoring workflow infrastructure application; do
            COUNT=$(curl -sf "$LOKI_API/loki/api/v1/query?query=count_over_time(%7Bservice_type%3D%22$TYPE%22%7D%5B1h%5D)" 2>/dev/null | \
                jq -r '.data.result | length' 2>/dev/null || echo "0")
            if [ "$COUNT" -gt 0 ]; then
                log_success "service_type=$TYPE: $COUNT streams"
            else
                log_warning "service_type=$TYPE: No logs"
            fi
        done
    else
        log_warning "Skipping query tests (labels not found)"
    fi
    echo ""

    # 8. Check alert rules
    echo "8️⃣  Alert Rules Status"
    ALERT_RULES=$(curl -sf "$PROMETHEUS_API/api/v1/rules?type=alert" 2>/dev/null | \
        jq -r '.data.groups[] | select(.name=="log_collection_alerts") | .rules[].name' 2>/dev/null)
    RULE_COUNT=$(echo "$ALERT_RULES" | wc -l)

    if [ "$RULE_COUNT" -ge 10 ]; then
        log_success "Alert rules: $RULE_COUNT active"
        echo "$ALERT_RULES" | sed 's/^/   - /'
    else
        log_warning "Expected 10+ alert rules, found: $RULE_COUNT"
    fi
    echo ""

    # 9. Critical services logs
    echo "9️⃣  Critical Services Verification"
    for service in "${CRITICAL_SERVICES[@]}"; do
        LOG_COUNT=$(curl -sf "$LOKI_API/loki/api/v1/query?query=count_over_time(%7Bcontainer_name%3D%22$service%22%7D%5B5m%5D)" 2>/dev/null | \
            jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

        if [ "$LOG_COUNT" -gt 0 ]; then
            log_success "$service: $LOG_COUNT log entries (5m)"
        else
            log_warning "$service: No logs found"
        fi
    done
    echo ""

    # 10. Final summary
    echo "📊 Full Verification Summary"
    echo "==============================="
    TOTAL_LINES=$(query_prometheus "loki_distributor_lines_received_total")
    echo "Total Containers: $TOTAL_CONTAINERS"
    echo "Critical Services: ${#CRITICAL_SERVICES[@]}"
    echo "Log Rate: $LOG_RATE lines/sec"
    echo "Total Lines Collected: $TOTAL_LINES"
    echo "Alert Rules: $RULE_COUNT"
    echo "Loki Labels: $(echo "$LABELS" | wc -l)"
    echo ""

    log_success "Full Verification Complete"
    echo ""
    echo "💡 Next Steps:"
    echo "   - View logs: https://grafana.jclee.me/explore"
    echo "   - Query: {job=\"docker-containers\"} | json"
    echo "   - Alerts: https://prometheus.jclee.me/alerts"
}

# Main
main() {
    case "$MODE" in
        --quick|-q)
            quick_check
            ;;
        --full|-f)
            full_check
            ;;
        --help|-h)
            echo "Usage: $0 [--quick|--full]"
            echo ""
            echo "Options:"
            echo "  --quick, -q    Quick health check (default)"
            echo "  --full, -f     Full verification with detailed tests"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            log_error "Invalid option: $MODE"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
