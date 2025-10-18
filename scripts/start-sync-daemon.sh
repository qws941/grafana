#!/bin/bash
# Start real-time sync daemon in background

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="/tmp/grafana-sync.pid"
LOG_FILE="/tmp/grafana-sync.log"

# Check if already running
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if ps -p "$OLD_PID" > /dev/null 2>&1; then
    echo "✅ Sync daemon already running (PID: $OLD_PID)"
    exit 0
  else
    rm -f "$PID_FILE"
  fi
fi

# Start daemon
cd "$PROJECT_DIR"
nohup node scripts/realtime-sync.js >> "$LOG_FILE" 2>&1 &
NEW_PID=$!

echo "$NEW_PID" > "$PID_FILE"

sleep 1

if ps -p "$NEW_PID" > /dev/null 2>&1; then
  echo "✅ Sync daemon started successfully (PID: $NEW_PID)"
  echo "📝 Logs: tail -f $LOG_FILE"
else
  echo "❌ Failed to start sync daemon"
  rm -f "$PID_FILE"
  exit 1
fi
