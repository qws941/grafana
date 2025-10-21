#!/bin/bash
#
# Monitoring Trends Analysis
# Analyzes historical metrics and provides trend insights
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure synology context
CURRENT_CONTEXT=$(docker context show 2>/dev/null || echo "")
if [ "$CURRENT_CONTEXT" != "synology" ]; then
    docker context use synology >/dev/null 2>&1
fi

query_prometheus() {
    local query="$1"
    docker exec prometheus-container wget -qO- \
        "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null
}

query_prometheus_range() {
    local query="$1"
    local start="$2"  # e.g., -24h
    local end="now"
    local step="5m"
    
    docker exec prometheus-container wget -qO- \
        "http://localhost:9090/api/v1/query_range?query=${query}&start=${start}&end=${end}&step=${step}" 2>/dev/null
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Monitoring Trends & Predictive Analysis               ║"
echo "║            Last 24 Hours Performance Review                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Target Availability Trends
echo -e "${BLUE}📊 TARGET AVAILABILITY TRENDS (24h)${NC}"
echo "─────────────────────────────────────────────────────────────"

query_prometheus 'avg_over_time(up[24h]) * 100' | \
jq -r '.data.result[] | 
  "\(.metric.job | .[0:30] | . + (" " * (30 - length))): \(.value[1] | tonumber | floor)% [\(.metric.context)]"' | \
while IFS= read -r line; do
    pct=$(echo "$line" | grep -oP '\d+%' | tr -d '%')
    if (( pct >= 99 )); then
        echo -e "  ${GREEN}${line}${NC}"
    elif (( pct >= 95 )); then
        echo -e "  ${YELLOW}${line}${NC}"
    else
        echo -e "  ${RED}${line}${NC}"
    fi
done

echo ""
echo -e "${BLUE}🖥️  SYSTEM LOAD TREND${NC}"
echo "─────────────────────────────────────────────────────────────"

LOAD_NOW=$(query_prometheus "node_load1" | jq -r '.data.result[0].value[1] | tonumber')
LOAD_AVG_24H=$(query_prometheus "avg_over_time(node_load1[24h])" | jq -r '.data.result[0].value[1] | tonumber')
LOAD_MAX_24H=$(query_prometheus "max_over_time(node_load1[24h])" | jq -r '.data.result[0].value[1] | tonumber')

LOAD_TREND=$(echo "scale=1; ($LOAD_NOW - $LOAD_AVG_24H) / $LOAD_AVG_24H * 100" | bc)

echo "  Current:      $LOAD_NOW"
echo "  24h Average:  $LOAD_AVG_24H"
echo "  24h Peak:     $LOAD_MAX_24H"

if (( $(echo "$LOAD_TREND > 20" | bc -l) )); then
    echo -e "  Trend:        ${RED}↑ +${LOAD_TREND}% (Increasing significantly)${NC}"
elif (( $(echo "$LOAD_TREND > 5" | bc -l) )); then
    echo -e "  Trend:        ${YELLOW}↑ +${LOAD_TREND}% (Increasing)${NC}"
elif (( $(echo "$LOAD_TREND < -20" | bc -l) )); then
    echo -e "  Trend:        ${GREEN}↓ ${LOAD_TREND}% (Decreasing significantly)${NC}"
elif (( $(echo "$LOAD_TREND < -5" | bc -l) )); then
    echo -e "  Trend:        ${GREEN}↓ ${LOAD_TREND}% (Decreasing)${NC}"
else
    echo -e "  Trend:        ${CYAN}→ ${LOAD_TREND}% (Stable)${NC}"
fi

echo ""
echo -e "${BLUE}💾 MEMORY USAGE TREND${NC}"
echo "─────────────────────────────────────────────────────────────"

MEM_NOW=$(query_prometheus "node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes*100" | jq -r '.data.result[0].value[1] | tonumber | floor')
MEM_AVG_24H=$(query_prometheus "avg_over_time((node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes*100)[24h])" | jq -r '.data.result[0].value[1] | tonumber | floor')
MEM_MIN_24H=$(query_prometheus "min_over_time((node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes*100)[24h])" | jq -r '.data.result[0].value[1] | tonumber | floor')

echo "  Available Now:   ${MEM_NOW}%"
echo "  24h Average:     ${MEM_AVG_24H}%"
echo "  24h Minimum:     ${MEM_MIN_24H}%"

if (( MEM_MIN_24H < 20 )); then
    echo -e "  ${RED}⚠️  Memory critically low at times${NC}"
elif (( MEM_MIN_24H < 40 )); then
    echo -e "  ${YELLOW}⚠️  Memory pressure detected${NC}"
else
    echo -e "  ${GREEN}✓ Memory healthy${NC}"
fi

echo ""
echo -e "${BLUE}📈 N8N WORKFLOW ACTIVITY${NC}"
echo "─────────────────────────────────────────────────────────────"

WORKFLOW_RATE_NOW=$(query_prometheus "rate(n8n_workflow_started_total[5m])*60" | jq -r '(.data.result[0].value[1] // "0" | tonumber)')
WORKFLOW_RATE_AVG=$(query_prometheus "avg_over_time(rate(n8n_workflow_started_total[5m])[24h])*60" | jq -r '(.data.result[0].value[1] // "0" | tonumber)')
WORKFLOW_RATE_MAX=$(query_prometheus "max_over_time(rate(n8n_workflow_started_total[5m])[24h])*60" | jq -r '(.data.result[0].value[1] // "0" | tonumber)')

echo "  Current Rate:    $(printf "%.2f" "$WORKFLOW_RATE_NOW") workflows/min"
echo "  24h Average:     $(printf "%.2f" "$WORKFLOW_RATE_AVG") workflows/min"
echo "  24h Peak:        $(printf "%.2f" "$WORKFLOW_RATE_MAX") workflows/min"

# Calculate total workflows in last 24h
TOTAL_24H=$(query_prometheus "increase(n8n_workflow_started_total[24h])" | jq -r '(.data.result[0].value[1] // "0" | tonumber | floor)')
echo "  Total (24h):     ${TOTAL_24H} workflows"

echo ""
echo -e "${BLUE}🔥 TOP RESOURCE CONSUMERS${NC}"
echo "─────────────────────────────────────────────────────────────"

echo "  Top CPU Users (avg 1h):"
query_prometheus 'topk(5, avg_over_time(rate(container_cpu_usage_seconds_total{name!=""}[5m])[1h]) * 100)' | \
jq -r '.data.result[] | "    " + (.metric.name | .[0:40] | . + (" " * (40 - length))) + ": " + (.value[1] | tonumber | . * 100 | floor | . / 100 | tostring) + "%"'

echo ""
echo "  Top Memory Users (current):"
query_prometheus 'topk(5, container_memory_usage_bytes{name!=""})' | \
jq -r '.data.result[] | "    " + (.metric.name | .[0:40] | . + (" " * (40 - length))) + ": " + ((.value[1] | tonumber) / 1024 / 1024 | floor | tostring) + " MB"'

echo ""
echo -e "${BLUE}💡 RECOMMENDATIONS${NC}"
echo "─────────────────────────────────────────────────────────────"

# Generate recommendations based on metrics
RECOMMENDATIONS=0

if (( $(echo "$LOAD_AVG_24H > 10" | bc -l) )); then
    echo -e "  ${YELLOW}⚠${NC}  System load is high (avg: $LOAD_AVG_24H). Consider:"
    echo "     - Reducing concurrent processes"
    echo "     - Optimizing resource-intensive services"
    RECOMMENDATIONS=$((RECOMMENDATIONS + 1))
fi

if (( MEM_MIN_24H < 30 )); then
    echo -e "  ${YELLOW}⚠${NC}  Memory has been low (min: ${MEM_MIN_24H}%). Consider:"
    echo "     - Adding more RAM"
    echo "     - Optimizing container memory limits"
    RECOMMENDATIONS=$((RECOMMENDATIONS + 1))
fi

TARGET_ISSUES=$(query_prometheus 'count(up == 0)' | jq -r '.data.result[0].value[1] // "0"')
if (( TARGET_ISSUES > 0 )); then
    echo -e "  ${YELLOW}⚠${NC}  ${TARGET_ISSUES} target(s) are DOWN. Review:"
    echo "     - Run: ./scripts/monitoring-status.sh"
    echo "     - Check service logs"
    RECOMMENDATIONS=$((RECOMMENDATIONS + 1))
fi

if (( RECOMMENDATIONS == 0 )); then
    echo -e "  ${GREEN}✓ All metrics look healthy!${NC}"
fi

echo ""
echo -e "${CYAN}💡 Using Docker context: $(docker context show)${NC}"
echo ""
