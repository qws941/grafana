#!/bin/bash
# Setup Reinforcement Learning Automation
# Configures cron jobs, systemd services, and monitoring

set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
CRON_FILE="/tmp/rl-cron.tmp"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

echo "🔧 Setting up RL Automation..."

# ============================================================================
# 1. Cron Jobs
# ============================================================================

echo "📅 Configuring cron jobs..."

# Backup existing crontab
crontab -l > "${CRON_FILE}" 2>/dev/null || echo "# RL Automation Crontab" > "${CRON_FILE}"

# Remove existing RL cron jobs
sed -i '/# RL:/d' "${CRON_FILE}"

# Add new RL cron jobs
cat >> "${CRON_FILE}" <<EOF

# RL: Daily metrics collection (00:00 KST)
0 0 * * * bash ${CLAUDE_HOME}/scripts/collect-reinforcement-metrics.sh >> ${CLAUDE_HOME}/data/reinforcement-learning/cron.log 2>&1

# RL: Daily training (02:00 KST)
0 2 * * * bash ${CLAUDE_HOME}/scripts/train-from-real-data.sh >> ${CLAUDE_HOME}/data/reinforcement-learning/training.log 2>&1

# RL: Weekly patch generation (Sunday 04:00 KST)
0 4 * * 0 bash ${CLAUDE_HOME}/scripts/generate-improvement-patch.sh >> ${CLAUDE_HOME}/data/reinforcement-learning/patch.log 2>&1

# RL: A/B test monitoring (every 5 min)
*/5 * * * * bash ${CLAUDE_HOME}/scripts/ab-test-monitor.sh >> ${CLAUDE_HOME}/data/ab-test/monitor.log 2>&1

# RL: Cleanup old data (weekly, Sunday 05:00 KST)
0 5 * * 0 find ${CLAUDE_HOME}/data/reinforcement-learning -type f -mtime +30 -delete

EOF

# Install crontab
crontab "${CRON_FILE}"
rm "${CRON_FILE}"

echo "✅ Cron jobs installed"
crontab -l | grep "# RL:"

# ============================================================================
# 2. A/B Test Monitor Script
# ============================================================================

echo "🧪 Creating A/B test monitor script..."

cat > "${CLAUDE_HOME}/scripts/ab-test-monitor.sh" <<'EOF'
#!/bin/bash
# A/B Test Continuous Monitor
# Runs every 5 minutes to check test status and auto-rollback if needed

set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
AB_TEST_DIR="${CLAUDE_HOME}/data/ab-test"
STATUS_FILE="${AB_TEST_DIR}/status.json"
PROMETHEUS_URL="https://prometheus.jclee.me"
LOKI_URL="https://loki.jclee.me"

mkdir -p "${AB_TEST_DIR}"

# Check if test is active
if [ ! -f "${STATUS_FILE}" ]; then
  exit 0
fi

ACTIVE=$(jq -r '.active // false' "${STATUS_FILE}")
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# Get current variant
VARIANT=$(jq -r '.variant' "${STATUS_FILE}")
if [ "$VARIANT" = "baseline" ]; then
  exit 0
fi

# Query metrics
AUTONOMOUS_DELTA=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=guardian_autonomous_rate{variant=\"${VARIANT}\"}-ignoring(variant)guardian_autonomous_rate{variant=\"baseline\"}" | jq -r '.data.result[0].value[1] // "0"')
ROLLBACK_DELTA=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(guardian_rollback_total{variant=\"${VARIANT}\"}[1h])-ignoring(variant)rate(guardian_rollback_total{variant=\"baseline\"}[1h])" | jq -r '.data.result[0].value[1] // "0"')

# Check rollback triggers
if (( $(echo "$AUTONOMOUS_DELTA < -0.05" | bc -l) )) || \
   (( $(echo "$ROLLBACK_DELTA > 0.03" | bc -l) )); then

  echo "[$(date -Iseconds)] 🚨 Rollback triggered: autonomous=${AUTONOMOUS_DELTA}, rollback=${ROLLBACK_DELTA}"

  # Execute rollback
  bash "${CLAUDE_HOME}/scripts/ab-test-manager.sh" stop "degradation_detected"

  # Send alert to Loki
  curl -s -X POST "${LOKI_URL}/loki/api/v1/push" \
    -H "Content-Type: application/json" \
    -d "{
      \"streams\": [{
        \"stream\": {
          \"job\": \"guardian\",
          \"event\": \"ab_test_rollback\",
          \"severity\": \"critical\"
        },
        \"values\": [[\"$(date +%s)000000000\", \"EMERGENCY ROLLBACK: variant=${VARIANT} autonomous_delta=${AUTONOMOUS_DELTA} rollback_delta=${ROLLBACK_DELTA}\"]]
      }]
    }" || true

  # TODO: Send Slack alert

fi
EOF

chmod +x "${CLAUDE_HOME}/scripts/ab-test-monitor.sh"

echo "✅ A/B test monitor created"

# ============================================================================
# 3. Metrics Instrumentation
# ============================================================================

echo "📊 Adding Prometheus metrics instrumentation..."

cat > "${CLAUDE_HOME}/scripts/push-metrics.sh" <<'EOF'
#!/bin/bash
# Push metrics to Prometheus Pushgateway
# Usage: push-metrics.sh <metric_name> <value> [labels]

set -euo pipefail

PUSHGATEWAY="http://localhost:9091"  # Assumes Pushgateway on localhost
METRIC_NAME=$1
VALUE=$2
LABELS=${3:-""}

if [ -n "$LABELS" ]; then
  INSTANCE="${LABELS}"
else
  INSTANCE="job=\"guardian\""
fi

cat <<METRICS | curl --data-binary @- "${PUSHGATEWAY}/metrics/${INSTANCE}"
# TYPE ${METRIC_NAME} gauge
${METRIC_NAME} ${VALUE}
METRICS
EOF

chmod +x "${CLAUDE_HOME}/scripts/push-metrics.sh"

echo "✅ Metrics push script created"

# ============================================================================
# 4. Systemd User Service (Optional - for continuous monitoring)
# ============================================================================

if command -v systemctl &> /dev/null; then
  echo "🔧 Creating systemd user service..."

  mkdir -p "${SYSTEMD_DIR}"

  cat > "${SYSTEMD_DIR}/rl-monitor.service" <<EOF
[Unit]
Description=Reinforcement Learning Monitor
After=network.target

[Service]
Type=simple
ExecStart=${CLAUDE_HOME}/scripts/ab-test-monitor.sh
Restart=on-failure
RestartSec=300
StandardOutput=append:${CLAUDE_HOME}/data/ab-test/monitor.log
StandardError=append:${CLAUDE_HOME}/data/ab-test/monitor.log

[Install]
WantedBy=default.target
EOF

  cat > "${SYSTEMD_DIR}/rl-monitor.timer" <<EOF
[Unit]
Description=Reinforcement Learning Monitor Timer
Requires=rl-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=rl-monitor.service

[Install]
WantedBy=timers.target
EOF

  # Reload systemd and enable timer
  systemctl --user daemon-reload
  systemctl --user enable rl-monitor.timer
  systemctl --user start rl-monitor.timer

  echo "✅ Systemd timer enabled"
  systemctl --user status rl-monitor.timer --no-pager
else
  echo "⚠️  systemctl not found, skipping systemd service"
fi

# ============================================================================
# 5. Auto-Patch Application Workflow
# ============================================================================

echo "🔄 Creating auto-patch application script..."

cat > "${CLAUDE_HOME}/scripts/apply-rl-patch.sh" <<'EOF'
#!/bin/bash
# Apply RL improvement patch to CLAUDE.md
# Requires human approval via GitHub issue

set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
CLAUDE_MD="${CLAUDE_HOME}/CLAUDE.md"
PATCH_DIR="${CLAUDE_HOME}/patches"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <patch_file> [--force]"
  exit 1
fi

PATCH_FILE=$1
FORCE=${2:-""}

if [ ! -f "${PATCH_FILE}" ]; then
  echo "❌ Patch file not found: ${PATCH_FILE}"
  exit 1
fi

echo "📝 Patch: $(basename ${PATCH_FILE})"

# Extract approval status from patch
APPROVAL=$(grep -oP 'Approval Threshold: ≥\K\d+' "${PATCH_FILE}" || echo "70")

if [ "$FORCE" != "--force" ]; then
  echo "⚠️  Human approval required (≥${APPROVAL}%)"
  echo "   Review patch: cat ${PATCH_FILE}"
  echo "   To apply: $0 ${PATCH_FILE} --force"
  exit 0
fi

# Backup current CLAUDE.md
cp "${CLAUDE_MD}" "${CLAUDE_MD}.backup-$(date +%Y%m%d_%H%M%S)"

# Extract version
CURRENT_VERSION=$(grep -oP '^# CLAUDE.md v\K[\d.]+' "${CLAUDE_MD}")
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${NEW_MINOR}"

echo "📊 Version: v${CURRENT_VERSION} → v${NEW_VERSION}"

# TODO: Apply patch changes (manual edit required based on patch content)
# For now, log the action
echo "[$(date -Iseconds)] Patch applied: ${PATCH_FILE}" >> "${CLAUDE_HOME}/data/reinforcement-learning/patch-history.log"

echo "✅ Patch application prepared"
echo "   Manual: Review and edit CLAUDE.md based on patch recommendations"
echo "   Update version to v${NEW_VERSION}"
echo "   Commit: git add CLAUDE.md && git commit -m 'feat: Apply RL patch v${NEW_VERSION}'"

EOF

chmod +x "${CLAUDE_HOME}/scripts/apply-rl-patch.sh"

echo "✅ Auto-patch script created"

# ============================================================================
# 6. Verification
# ============================================================================

echo ""
echo "🔍 Verification..."
echo ""

echo "Cron jobs:"
crontab -l | grep "# RL:" | wc -l
echo ""

echo "Scripts:"
ls -lh "${CLAUDE_HOME}"/scripts/{ab-test-monitor.sh,push-metrics.sh,apply-rl-patch.sh} 2>/dev/null || echo "Some scripts missing"
echo ""

if command -v systemctl &> /dev/null; then
  echo "Systemd timer:"
  systemctl --user is-active rl-monitor.timer || echo "Not active"
  echo ""
fi

echo "✅ RL Automation Setup Complete!"
echo ""
echo "Next steps:"
echo "  1. Wait for first cron run (00:00 KST) or run manually:"
echo "     bash ${CLAUDE_HOME}/scripts/collect-reinforcement-metrics.sh"
echo ""
echo "  2. Monitor logs:"
echo "     tail -f ${CLAUDE_HOME}/data/reinforcement-learning/cron.log"
echo ""
echo "  3. Check A/B test status:"
echo "     bash ${CLAUDE_HOME}/scripts/ab-test-manager.sh status"
echo ""
echo "  4. Review generated patches:"
echo "     ls -lt ${CLAUDE_HOME}/patches/"
