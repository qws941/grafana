#!/bin/bash
#
# Setup Automated Monitoring Cron Jobs
# Configures periodic health checks, status reports, and trend analysis
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs/monitoring"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Monitoring Automation Setup                           ║"
echo "║        Configuring Cron Jobs for Grafana Stack              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Create log directory
echo -e "${BLUE}📁 Creating log directory...${NC}"
mkdir -p "$LOG_DIR"
echo "  ✅ Log directory: $LOG_DIR"
echo ""

# Check if scripts exist
echo -e "${BLUE}🔍 Verifying monitoring scripts...${NC}"
SCRIPTS_OK=true

if [ ! -f "$SCRIPT_DIR/health-check.sh" ]; then
  echo -e "${YELLOW}  ⚠️  health-check.sh not found${NC}"
  SCRIPTS_OK=false
fi

if [ ! -f "$SCRIPT_DIR/monitoring-status.sh" ]; then
  echo -e "${YELLOW}  ⚠️  monitoring-status.sh not found${NC}"
  SCRIPTS_OK=false
fi

if [ ! -f "$SCRIPT_DIR/monitoring-trends.sh" ]; then
  echo -e "${YELLOW}  ⚠️  monitoring-trends.sh not found${NC}"
  SCRIPTS_OK=false
fi

if [ "$SCRIPTS_OK" = false ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Some scripts are missing. Cron jobs will not work properly.${NC}"
  echo "Please ensure all monitoring scripts are present before running this setup."
  exit 1
fi

echo "  ✅ All scripts verified"
echo ""

# Generate cron configuration
echo -e "${BLUE}⚙️  Generating cron configuration...${NC}"

cat > /tmp/monitoring-cron << CRONEOF
# Grafana Monitoring Stack - Automated Tasks
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Health check every 5 minutes
*/5 * * * * cd $SCRIPT_DIR && ./health-check.sh >> $LOG_DIR/health-check.log 2>&1

# Status dashboard every hour
0 * * * * cd $SCRIPT_DIR && ./monitoring-status.sh > $LOG_DIR/status-\$(date +\%Y\%m\%d-\%H00).txt 2>&1

# Daily summary at 09:00
0 9 * * * cd $SCRIPT_DIR && ./monitoring-trends.sh > $LOG_DIR/trends-\$(date +\%Y\%m\%d).txt 2>&1

# Log rotation (keep last 30 days)
0 0 * * * find $LOG_DIR -name "*.txt" -mtime +30 -delete
0 0 * * * find $LOG_DIR -name "*.log" -size +100M -exec truncate -s 50M {} \;

CRONEOF

echo "  ✅ Cron configuration generated"
echo ""

# Display the configuration
echo -e "${BLUE}📋 Proposed Cron Jobs:${NC}"
echo "─────────────────────────────────────────────────────────────"
grep -v "^#" /tmp/monitoring-cron | grep -v "^$"
echo "─────────────────────────────────────────────────────────────"
echo ""

# Ask for confirmation
echo -e "${YELLOW}⚠️  This will add/update cron jobs for the current user.${NC}"
echo ""
read -p "Do you want to proceed? (yes/no): " -r REPLY
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "❌ Installation cancelled."
  rm -f /tmp/monitoring-cron
  exit 0
fi

# Backup existing crontab
echo -e "${BLUE}💾 Backing up existing crontab...${NC}"
if crontab -l > /dev/null 2>&1; then
  crontab -l > "$LOG_DIR/crontab-backup-$(date +%Y%m%d-%H%M%S).txt"
  echo "  ✅ Backup saved"
else
  echo "  ℹ️  No existing crontab found"
fi
echo ""

# Remove old monitoring jobs if exist
echo -e "${BLUE}🧹 Removing old monitoring jobs...${NC}"
if crontab -l > /dev/null 2>&1; then
  crontab -l | grep -v "health-check.sh" | grep -v "monitoring-status.sh" | grep -v "monitoring-trends.sh" | crontab - 2>/dev/null || true
  echo "  ✅ Old jobs removed"
else
  echo "  ℹ️  No old jobs to remove"
fi
echo ""

# Install new cron jobs
echo -e "${BLUE}📥 Installing new cron jobs...${NC}"
(crontab -l 2>/dev/null || true; cat /tmp/monitoring-cron) | crontab -
echo "  ✅ Cron jobs installed"
echo ""

# Verify installation
echo -e "${BLUE}✅ Verifying installation...${NC}"
if crontab -l | grep -q "health-check.sh"; then
  echo "  ✅ Health check job: Active"
else
  echo "  ❌ Health check job: Not found"
fi

if crontab -l | grep -q "monitoring-status.sh"; then
  echo "  ✅ Status dashboard job: Active"
else
  echo "  ❌ Status dashboard job: Not found"
fi

if crontab -l | grep -q "monitoring-trends.sh"; then
  echo "  ✅ Trend analysis job: Active"
else
  echo "  ❌ Trend analysis job: Not found"
fi
echo ""

# Cleanup
rm -f /tmp/monitoring-cron

# Summary
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Installation Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ Monitoring automation is now active!${NC}"
echo ""
echo "Scheduled Tasks:"
echo "  - Health checks: Every 5 minutes"
echo "  - Status reports: Every hour"
echo "  - Trend analysis: Daily at 09:00"
echo "  - Log rotation: Daily at midnight"
echo ""
echo "Log Directory: $LOG_DIR"
echo ""
echo "To view current cron jobs: crontab -l"
echo "To remove cron jobs: crontab -e (and delete the monitoring lines)"
echo "To view logs: ls -lh $LOG_DIR"
echo ""
echo -e "${BLUE}💡 TIP: Check logs in 5 minutes to verify health-check is running${NC}"
echo ""
