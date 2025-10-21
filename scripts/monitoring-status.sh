#!/bin/bash
#
# Monitoring Status Dashboard (Optimized with Docker Context)
# Uses Docker context instead of manual SSH for cleaner code
#
# Prerequisites: 
#   - Docker context 'synology' configured
#   - Run: docker context use synology
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure synology context is active
CURRENT_CONTEXT=$(docker context show 2>/dev/null || echo "")
if [ "$CURRENT_CONTEXT" != "synology" ]; then
    echo -e "${YELLOW}⚠️  Switching to synology context...${NC}"
    docker context use synology >/dev/null 2>&1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Grafana Monitoring Stack - Status Dashboard              ║"
echo "║     $(date '+%Y-%m-%d %H:%M:%S %Z')                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Helper function for Prometheus queries
query_prometheus() {
    local query="$1"
    docker exec prometheus-container wget -qO- \
        "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null
}

# Context-based Target Status
echo -e "${BLUE}📊 PROMETHEUS TARGETS BY CONTEXT${NC}"
echo "─────────────────────────────────────────────────────────────"

docker exec prometheus-container wget -qO- "http://localhost:9090/api/v1/targets" 2>/dev/null | \
jq -r '.data.activeTargets[] | {context: .labels.context, job: .labels.job, health: .health}' | \
jq -s 'group_by(.context) | .[] | {
  context: .[0].context,
  total: length,
  up: ([.[] | select(.health == "up")] | length),
  down: ([.[] | select(.health == "down")] | length),
  jobs: [.[] | {job: .job, health: .health}]
}' | jq -r '
  "Context: \(.context)" +
  "\n  Total: \(.total) | UP: \(.up) | DOWN: \(.down)" +
  "\n  Jobs:" +
  "\n" + (.jobs | map("    - \(.job) [\(.health)]") | join("\n")) +
  "\n"
'

echo ""
echo -e "${BLUE}🖥️  SYSTEM METRICS (Synology NAS)${NC}"
echo "─────────────────────────────────────────────────────────────"

LOAD=$(query_prometheus "node_load1" | jq -r '.data.result[0].value[1]')
MEM=$(query_prometheus "node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes*100" | jq -r '.data.result[0].value[1] | tonumber | floor')
DISK=$(query_prometheus '(node_filesystem_size_bytes{mountpoint="/"}-node_filesystem_avail_bytes{mountpoint="/"})/node_filesystem_size_bytes{mountpoint="/"}*100' | jq -r '.data.result[0].value[1] | tonumber | floor')

# Color-code based on thresholds
if (( $(echo "$LOAD > 15" | bc -l) )); then
  LOAD_COLOR=$RED
elif (( $(echo "$LOAD > 10" | bc -l) )); then
  LOAD_COLOR=$YELLOW
else
  LOAD_COLOR=$GREEN
fi

if (( MEM < 20 )); then
  MEM_COLOR=$RED
elif (( MEM < 40 )); then
  MEM_COLOR=$YELLOW
else
  MEM_COLOR=$GREEN
fi

if (( DISK > 80 )); then
  DISK_COLOR=$RED
elif (( DISK > 60 )); then
  DISK_COLOR=$YELLOW
else
  DISK_COLOR=$GREEN
fi

echo -e "  System Load (1m): ${LOAD_COLOR}${LOAD}${NC}"
echo -e "  Memory Available: ${MEM_COLOR}${MEM}%${NC}"
echo -e "  Disk Usage (/):   ${DISK_COLOR}${DISK}%${NC}"

echo ""
echo -e "${BLUE}🐳 CONTAINER STATUS${NC}"
echo "─────────────────────────────────────────────────────────────"
docker ps --filter name=container --format '  {{.Names}}: {{.Status}}' | head -12

echo ""
echo -e "${BLUE}📈 APPLICATION METRICS (n8n)${NC}"
echo "─────────────────────────────────────────────────────────────"

WORKFLOWS=$(query_prometheus "n8n_active_workflow_count" | jq -r '.data.result[0].value[1]')
RATE=$(query_prometheus "rate(n8n_workflow_started_total[5m])*60" | jq -r '(.data.result[0].value[1] // "0" | tonumber | . * 100 | floor | . / 100)')

echo "  Active Workflows: ${WORKFLOWS}"
echo "  Workflow Start Rate: ${RATE} /min"

echo ""
echo -e "${BLUE}🚨 ACTIVE ALERTS${NC}"
echo "─────────────────────────────────────────────────────────────"

ALERT_COUNT=$(query_prometheus 'ALERTS{alertstate="firing"}' | jq -r '.data.result | length')

if [ "$ALERT_COUNT" -eq 0 ]; then
  echo -e "  ${GREEN}✅ No active alerts${NC}"
else
  echo -e "  ${RED}⚠️  $ALERT_COUNT alert(s) firing${NC}"
  query_prometheus 'ALERTS{alertstate="firing"}' | \
  jq -r '.data.result[] | "    - " + .metric.alertname + " [" + .metric.severity + "]"'
fi

echo ""
echo -e "${BLUE}🌐 SERVICE ENDPOINTS${NC}"
echo "─────────────────────────────────────────────────────────────"
echo "  Grafana:      https://grafana.jclee.me"
echo "  Prometheus:   https://prometheus.jclee.me"
echo "  Loki:         https://loki.jclee.me"
echo "  AlertManager: https://alertmanager.jclee.me"

echo ""
echo -e "${BLUE}📌 SUMMARY${NC}"
echo "─────────────────────────────────────────────────────────────"

TOTAL_TARGETS=$(docker exec prometheus-container wget -qO- "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '.data.activeTargets | length')
UP_TARGETS=$(docker exec prometheus-container wget -qO- "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '[.data.activeTargets[] | select(.health == "up")] | length')

UPTIME_PCT=$((UP_TARGETS * 100 / TOTAL_TARGETS))

if (( UPTIME_PCT == 100 )); then
  STATUS_COLOR=$GREEN
  STATUS="Excellent"
elif (( UPTIME_PCT >= 80 )); then
  STATUS_COLOR=$YELLOW
  STATUS="Good"
else
  STATUS_COLOR=$RED
  STATUS="Degraded"
fi

echo -e "  Overall Status: ${STATUS_COLOR}${STATUS}${NC}"
echo "  Targets: ${UP_TARGETS}/${TOTAL_TARGETS} UP (${UPTIME_PCT}%)"
echo "  Alerts: ${ALERT_COUNT} firing"
echo ""

echo -e "${CYAN}💡 Using Docker context: $(docker context show)${NC}"
echo ""
