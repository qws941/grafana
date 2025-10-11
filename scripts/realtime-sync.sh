#!/bin/bash
# Real-time directory sync to Synology NAS using inotify
# Usage: ./scripts/realtime-sync.sh

set -euo pipefail

# Configuration
REMOTE_HOST="192.168.50.215"
REMOTE_PORT="1111"
REMOTE_USER="jclee"
REMOTE_PATH="/volume1/grafana"
LOCAL_PATH="/home/jclee/app/grafana"

# Directories to watch
WATCH_DIRS=("configs" "compose" "scripts")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_sync() {
  echo -e "${GREEN}[SYNC]${NC} $1"
}

# Check dependencies
if ! command -v inotifywait &> /dev/null; then
  echo "❌ inotify-tools not installed"
  echo "Install with: sudo dnf install inotify-tools"
  exit 1
fi

# Initial sync
log "🚀 Starting initial sync..."
for dir in "${WATCH_DIRS[@]}"; do
  rsync -az --delete \
    -e "ssh -p ${REMOTE_PORT}" \
    "${LOCAL_PATH}/${dir}/" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${dir}/"
  log_sync "Initial sync: ${dir}/"
done

log "✅ Initial sync complete"
log "👀 Watching for changes in: ${WATCH_DIRS[*]}"
log "Press Ctrl+C to stop"
echo ""

# Build inotifywait paths
WATCH_PATHS=()
for dir in "${WATCH_DIRS[@]}"; do
  WATCH_PATHS+=("${LOCAL_PATH}/${dir}")
done

# Watch and sync
inotifywait -m -r -e modify,create,delete,move \
  --format '%w%f %e' \
  "${WATCH_PATHS[@]}" | while read -r filepath event; do

  # Determine which directory changed
  changed_dir=""
  for dir in "${WATCH_DIRS[@]}"; do
    if [[ "$filepath" == *"/${dir}/"* ]]; then
      changed_dir="$dir"
      break
    fi
  done

  if [[ -n "$changed_dir" ]]; then
    log_sync "Detected: ${event} in ${changed_dir}/"

    rsync -az --delete \
      -e "ssh -p ${REMOTE_PORT}" \
      "${LOCAL_PATH}/${changed_dir}/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${changed_dir}/" \
      2>/dev/null && echo "  ✓ Synced" || echo "  ✗ Failed"
  fi
done
