#!/bin/bash
# Pull Grafana configurations from Synology NAS to local
# Usage: ./scripts/sync-from-synology.sh [--dry-run] [--verbose]

set -euo pipefail

# Configuration
REMOTE_HOST="192.168.50.215"
REMOTE_PORT="1111"
REMOTE_USER="jclee"
REMOTE_PATH="/volume1/grafana"
LOCAL_PATH="/home/jclee/app/grafana"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN="--dry-run"
      shift
      ;;
    --verbose|-v)
      VERBOSE="-v"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--verbose]"
      exit 1
      ;;
  esac
done

# Logging function
log() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check if SSH connection works
log "Testing SSH connection to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}..."
if ! ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "echo 'SSH connection successful'" > /dev/null 2>&1; then
  log_error "Cannot connect to Synology NAS. Please check SSH configuration."
  exit 1
fi
log_success "SSH connection successful"

# Sync function (reverse direction: remote → local)
sync_directory() {
  local dest_dir=$1
  local src_subdir=$2
  local description=$3

  log "Pulling ${description}..."

  rsync -az ${DRY_RUN} ${VERBOSE} \
    --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude '*.swp' \
    --exclude '*.tmp' \
    -e "ssh -p ${REMOTE_PORT}" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${src_subdir}/" \
    "${LOCAL_PATH}/${dest_dir}/"

  if [[ -z "$DRY_RUN" ]]; then
    log_success "${description} pulled successfully"
  else
    log_warning "${description} - dry run (no changes made)"
  fi
}

# Main sync process
echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Pull Grafana Configuration from Synology"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -n "$DRY_RUN" ]]; then
  log_warning "DRY RUN MODE - No actual changes will be made"
  echo ""
fi

log_warning "This will overwrite local files with remote versions!"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log "Sync cancelled by user"
  exit 0
fi

# Sync directories (reverse: remote → local)
sync_directory "configs" "configs" "Configuration files"
sync_directory "compose" "compose" "Docker Compose files"
sync_directory "scripts" "scripts" "Management scripts"

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Pull completed successfully!"
echo ""
