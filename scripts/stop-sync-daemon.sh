#!/bin/bash
# Stop real-time sync daemon

PID_FILE="/tmp/grafana-sync.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "❌ No PID file found. Daemon not running?"
  exit 1
fi

PID=$(cat "$PID_FILE")

if ps -p "$PID" > /dev/null 2>&1; then
  kill "$PID"
  sleep 1

  if ps -p "$PID" > /dev/null 2>&1; then
    echo "⚠️  Process still running, forcing kill..."
    kill -9 "$PID"
  fi

  rm -f "$PID_FILE"
  echo "✅ Sync daemon stopped (PID: $PID)"
else
  echo "⚠️  Process not running (stale PID file removed)"
  rm -f "$PID_FILE"
fi
