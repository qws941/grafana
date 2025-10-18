#!/bin/bash
# Common functions library for Grafana Monitoring Stack scripts
# Source this file in your scripts: source "$(dirname "$0")/lib/common.sh"

# ============================================
# Color codes
# ============================================
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# ============================================
# Logging functions
# ============================================
log() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_sync() {
  echo -e "${GREEN}[SYNC]${NC} $1"
}

# ============================================
# Error handling
# ============================================
die() {
  log_error "$1"
  exit "${2:-1}"
}

check_command() {
  local cmd="$1"
  if ! command -v "$cmd" &> /dev/null; then
    die "Required command not found: $cmd" 127
  fi
}

# ============================================
# Configuration
# ============================================
readonly REMOTE_HOST="${REMOTE_HOST:-192.168.50.215}"
readonly REMOTE_PORT="${REMOTE_PORT:-1111}"
readonly REMOTE_USER="${REMOTE_USER:-jclee}"
readonly REMOTE_PATH="${REMOTE_PATH:-/volume1/grafana}"
readonly LOCAL_PATH="${LOCAL_PATH:-/home/jclee/app/grafana}"

# ============================================
# Validation functions
# ============================================
check_remote_connection() {
  log_info "Checking connection to Synology NAS..."
  if ! ssh -p "$REMOTE_PORT" -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "echo 'Connected'" &>/dev/null; then
    die "Cannot connect to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}" 1
  fi
  log_success "Connected to Synology NAS"
}

check_docker_context() {
  log_info "Checking Docker context..."
  if [ -f ".docker-context" ]; then
    local context=$(cat .docker-context)
    log_info "Docker context: $context"
  else
    log_warning "No .docker-context file found (expected for grafana project)"
  fi
}

# ============================================
# Service health check
# ============================================
check_service_health() {
  local service_url="$1"
  local service_name="$2"
  
  if curl -sf --connect-timeout 5 "$service_url" > /dev/null 2>&1; then
    log_success "$service_name is healthy"
    return 0
  else
    log_error "$service_name is unhealthy or unreachable"
    return 1
  fi
}

# ============================================
# File operations
# ============================================
ensure_dir() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || die "Failed to create directory: $dir" 1
    log_success "Created directory: $dir"
  fi
}

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$file" "$backup" || die "Failed to backup file: $file" 1
    log_success "Backed up: $file -> $backup"
  fi
}

# ============================================
# Docker operations
# ============================================
check_docker_compose() {
  log_info "Validating docker-compose.yml..."
  if docker compose config > /dev/null 2>&1; then
    log_success "docker-compose.yml is valid"
    return 0
  else
    log_error "docker-compose.yml has syntax errors"
    return 1
  fi
}

# ============================================
# Prometheus operations
# ============================================
reload_prometheus() {
  local prom_url="${1:-https://prometheus.jclee.me}"
  log_info "Reloading Prometheus configuration..."
  
  if curl -sf -X POST "${prom_url}/-/reload" > /dev/null 2>&1; then
    log_success "Prometheus configuration reloaded"
    return 0
  else
    log_error "Failed to reload Prometheus configuration"
    return 1
  fi
}

# ============================================
# Grafana operations
# ============================================
reload_grafana() {
  log_info "Grafana auto-provisions dashboards every 10 seconds"
  log_warning "Manual reload not needed, but you can restart the container if required"
}

# ============================================
# Utility functions
# ============================================
get_timestamp() {
  date +%Y%m%d_%H%M%S
}

get_iso_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ============================================
# Banner
# ============================================
print_banner() {
  cat << 'BANNER'
╔═══════════════════════════════════════════╗
║   Grafana Monitoring Stack - Utilities   ║
╚═══════════════════════════════════════════╝
BANNER
}

# ============================================
# Initialization check
# ============================================
# Set shell options for safety
set -euo pipefail

# Export functions for subshells
export -f log log_success log_warning log_error log_info die
