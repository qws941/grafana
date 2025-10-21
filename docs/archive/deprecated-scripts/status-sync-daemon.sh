#!/bin/bash
# Check sync daemon status

PID_FILE="/tmp/grafana-sync.pid"
LOG_FILE="/tmp/grafana-sync.log"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Grafana Real-time Sync Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ! -f "$PID_FILE" ]; then
  echo "Status: ❌ Not running"
  echo ""
  echo "Start with: ./scripts/start-sync-daemon.sh"
  exit 1
fi

PID=$(cat "$PID_FILE")

if ps -p "$PID" > /dev/null 2>&1; then
  echo "Status: ✅ Running"
  echo "PID: $PID"
  echo "Uptime: $(ps -o etime= -p "$PID" | tr -d ' ')"
  echo ""
  echo "Recent logs:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  tail -20 "$LOG_FILE"
else
  echo "Status: ❌ Not running (stale PID file)"
  rm -f "$PID_FILE"
fi
