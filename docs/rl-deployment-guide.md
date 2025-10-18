# RL Automation Deployment Guide

Complete guide for deploying the Grafana-based Reinforcement Learning system.

## Quick Start

```bash
# 1. Verify prerequisites
bash ~/.claude/scripts/verify-mcp-servers.sh --full

# 2. Setup automation (if not done)
bash ~/.claude/scripts/setup-rl-automation.sh

# 3. Test metrics emission
bash ~/.claude/scripts/guardian-metrics.sh decision 85 0
bash ~/.claude/scripts/guardian-metrics.sh resource-pressure

# 4. Verify in Grafana
curl -s "https://prometheus.jclee.me/api/v1/query?query=guardian_decision_confidence_score" | jq
```

## Prerequisites

### Required Services

- ✅ **Grafana**: https://grafana.jclee.me (v10.2.3+)
- ✅ **Prometheus**: https://prometheus.jclee.me (v2.48.1+)
- ✅ **Loki**: https://loki.jclee.me (v2.9.3+)
- ✅ **Prometheus Pushgateway**: http://localhost:9091 (or configure `PUSHGATEWAY` env)

### System Requirements

- Bash 4.0+
- curl, jq, bc
- Cron daemon running
- Systemd (optional, for systemd services)
- SSH access to Synology NAS (for Grafana stack)

### Environment Variables

```bash
# Required
export LOKI_URL="https://loki.jclee.me"
export PROMETHEUS_URL="https://prometheus.jclee.me"
export PUSHGATEWAY="http://localhost:9091"  # or NAS pushgateway

# Optional
export CLAUDE_HOME="${HOME}/.claude"
export RL_DATA_DIR="${CLAUDE_HOME}/data/reinforcement-learning"
export AB_TEST_DIR="${CLAUDE_HOME}/data/ab-test"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Guardian Cognitive Loop                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Phase 0  │→ │ Phase 1  │→ │ Phase 2  │→ │ Phase 3  │   │
│  │  Audit   │  │ Analyze  │  │   Plan   │  │ Execute  │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │             │              │             │          │
│       └─────────────┴──────────────┴─────────────┘          │
│                          ↓                                   │
│              ┌───────────────────────┐                       │
│              │   Metrics Emission    │                       │
│              │  (guardian-metrics)   │                       │
│              └───────────┬───────────┘                       │
└──────────────────────────┼───────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ↓                  ↓                  ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Prometheus  │  │     Loki     │  │  Local Logs  │
│  Pushgateway │  │   (Grafana)  │  │ ~/.claude/   │
└──────┬───────┘  └──────┬───────┘  └──────────────┘
       │                 │
       ↓                 ↓
┌──────────────────────────────┐
│      Grafana Dashboards       │
│  • Cognitive Metrics          │
│  • A/B Test Results           │
└──────────────────────────────┘
       ↓
┌──────────────────────────────┐
│    RL Training Pipeline       │
│  Cron: Daily @ 02:00 KST      │
│  • Collect metrics            │
│  • Analyze performance        │
│  • Generate patches           │
│  • A/B test new variants      │
└──────────────────────────────┘
```

## Components

### 1. Scripts

| Script | Purpose | Schedule |
|--------|---------|----------|
| `guardian-metrics.sh` | Emit Prometheus metrics | On-demand |
| `rl-logger.sh` | Structured logging (Loki + local) | On-demand |
| `collect-reinforcement-metrics.sh` | Daily metrics collection | 00:00 KST |
| `train-from-real-data.sh` | Daily RL training | 02:00 KST |
| `generate-improvement-patch.sh` | Weekly patch generation | Sun 04:00 KST |
| `ab-test-monitor.sh` | Continuous A/B monitoring | Every 5 min |
| `ab-test-manager.sh` | A/B test lifecycle CLI | Manual |
| `apply-rl-patch.sh` | Patch application workflow | Manual |

### 2. Dashboards

**Guardian Cognitive Metrics** (`guardian-cognitive-metrics.json`):
- Decision confidence score (timeseries)
- Alternative paths considered (stat)
- System resource pressure (gauge)
- Verification failure reasons (piechart)
- AI agent prompt token count (timeseries)
- Response quality heatmap (heatmap)
- Model quota remaining (bargauge)

**A/B Test Results** (`ab-test-results.json`):
- Variant success rate comparison (timeseries)
- Autonomous rate delta vs baseline (timeseries with thresholds)
- Rollback rate delta vs baseline (timeseries with thresholds)
- Promotion readiness (stat)
- Current test stage (stat)
- Test duration (stat)
- Variant metrics comparison table (table)

### 3. Cron Jobs

```cron
# Daily metrics collection (00:00 KST)
0 0 * * * bash ~/.claude/scripts/collect-reinforcement-metrics.sh >> ~/.claude/data/reinforcement-learning/cron.log 2>&1

# Daily training (02:00 KST)
0 2 * * * bash ~/.claude/scripts/train-from-real-data.sh >> ~/.claude/data/reinforcement-learning/training.log 2>&1

# Weekly patch generation (Sunday 04:00 KST)
0 4 * * 0 bash ~/.claude/scripts/generate-improvement-patch.sh >> ~/.claude/data/reinforcement-learning/patch.log 2>&1

# A/B test monitoring (every 5 min)
*/5 * * * * bash ~/.claude/scripts/ab-test-monitor.sh >> ~/.claude/data/ab-test/monitor.log 2>&1

# Cleanup old data (weekly, Sunday 05:00 KST)
0 5 * * 0 find ~/.claude/data/reinforcement-learning -type f -mtime +30 -delete
```

### 4. Systemd Service (Optional)

**Service**: `~/.config/systemd/user/rl-monitor.service`
**Timer**: `~/.config/systemd/user/rl-monitor.timer`

Auto-start on boot, restart on failure, 5-minute interval.

## Manual Deployment Steps

### Step 1: Upload Grafana Dashboards

```bash
# Option A: Via Grafana UI
# 1. Open https://grafana.jclee.me
# 2. Login (admin / <password>)
# 3. Navigate to Dashboards → Import
# 4. Upload JSON files:
#    - ~/.claude/configs/grafana/dashboards/guardian-cognitive-metrics.json
#    - ~/.claude/configs/grafana/dashboards/ab-test-results.json

# Option B: Via API (if you have API key)
GRAFANA_API_KEY="<your-api-key>"

curl -X POST -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  https://grafana.jclee.me/api/dashboards/db \
  -d @~/.claude/configs/grafana/dashboards/guardian-cognitive-metrics.json

curl -X POST -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  https://grafana.jclee.me/api/dashboards/db \
  -d @~/.claude/configs/grafana/dashboards/ab-test-results.json
```

### Step 2: Configure Prometheus Pushgateway

**Option A: Use existing NAS Pushgateway**

```bash
# Check if Pushgateway exists on NAS
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep pushgateway"

# If not, deploy Pushgateway
ssh -p 1111 jclee@192.168.50.215 <<'EOF'
cd /volume1/grafana
cat >> docker-compose.yml <<'COMPOSE'
  pushgateway:
    image: prom/pushgateway:v1.7.0
    container_name: pushgateway-container
    restart: unless-stopped
    networks:
      - grafana-monitoring-net
    ports:
      - "9091:9091"
COMPOSE

sudo docker-compose up -d pushgateway
EOF

# Configure Prometheus to scrape Pushgateway
ssh -p 1111 jclee@192.168.50.215 <<'EOF'
cat >> /volume1/grafana/configs/prometheus.yml <<'PROM'
  - job_name: 'pushgateway'
    honor_labels: true
    static_configs:
      - targets: ['pushgateway-container:9091']
PROM

sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload
EOF
```

**Option B: Use SSH tunnel to local Pushgateway**

```bash
# In ~/.bashrc or session
ssh -N -L 9091:localhost:9091 -p 1111 jclee@192.168.50.215 &
```

### Step 3: Test Metrics Emission

```bash
# Test basic metrics
~/.claude/scripts/guardian-metrics.sh decision 85 0
~/.claude/scripts/guardian-metrics.sh alternatives 3 1
~/.claude/scripts/guardian-metrics.sh resource-pressure

# Verify in Prometheus
curl -s "https://prometheus.jclee.me/api/v1/query?query=guardian_decision_confidence_score" | jq '.data.result'

# Verify in Loki
curl -s "https://loki.jclee.me/loki/api/v1/query?query={job=\"guardian\"}&limit=10" | jq '.data.result'
```

### Step 4: Run Initial Training

```bash
# Manually trigger first training cycle
bash ~/.claude/scripts/collect-reinforcement-metrics.sh
bash ~/.claude/scripts/train-from-real-data.sh

# Check logs
tail -f ~/.claude/data/reinforcement-learning/training.log
```

### Step 5: Verify Dashboards

```bash
# Open Grafana
xdg-open https://grafana.jclee.me/d/guardian-cognitive-metrics
xdg-open https://grafana.jclee.me/d/ab-test-results

# Check for data in panels
# Expected: Some baseline data from Step 3 tests
```

## A/B Testing Workflow

### Start Test

```bash
# Start A/B test with new variant
bash ~/.claude/scripts/ab-test-manager.sh start "optimized_tier" "Improved decision confidence calculation"

# Monitor status
bash ~/.claude/scripts/ab-test-manager.sh status
```

### Monitor Test

```bash
# Automatic monitoring (every 5 min via cron + systemd)
sudo journalctl -u rl-monitor.timer -f

# Manual check
bash ~/.claude/scripts/ab-test-manager.sh monitor
```

### Rollout or Rollback

```bash
# If metrics look good, rollout to 50%
bash ~/.claude/scripts/ab-test-manager.sh rollout 0.5

# If metrics degrade, automatic rollback triggers
# Or manual stop:
bash ~/.claude/scripts/ab-test-manager.sh stop "manual_decision"
```

### Promote Variant

```bash
# After 7 days of stable performance at 100%
# Variant becomes new baseline in CLAUDE.md
# Apply patch:
bash ~/.claude/scripts/apply-rl-patch.sh ~/.claude/patches/TASK_ID.patch --force
```

## Troubleshooting

### No Data in Grafana Dashboards

```bash
# Check Prometheus targets
curl -s "https://prometheus.jclee.me/api/v1/targets" | jq '.data.activeTargets[] | select(.health != "up")'

# Check Pushgateway metrics
curl -s "http://localhost:9091/metrics" | grep guardian

# Re-emit test metrics
~/.claude/scripts/guardian-metrics.sh decision 85 0
```

### Cron Jobs Not Running

```bash
# Check crontab
crontab -l | grep "# RL:"

# Check cron logs
sudo tail -f /var/log/cron

# Check specific job logs
tail -f ~/.claude/data/reinforcement-learning/cron.log
tail -f ~/.claude/data/reinforcement-learning/training.log
```

### Systemd Service Not Running

```bash
# Check service status
systemctl --user status rl-monitor.timer
systemctl --user status rl-monitor.service

# Restart service
systemctl --user restart rl-monitor.timer

# View logs
journalctl --user -u rl-monitor.service -f
```

### Loki Logs Not Flowing

```bash
# Check RL logger
bash ~/.claude/scripts/rl-logger.sh info "test_event" "Test message" "key=value"

# Query Loki
curl -s "https://loki.jclee.me/loki/api/v1/query?query={job=\"guardian\"}&limit=5" | jq

# Check Promtail (if local)
sudo systemctl status promtail
```

### A/B Test Auto-Rollback Not Triggering

```bash
# Check monitor script
bash ~/.claude/scripts/ab-test-monitor.sh

# Check thresholds in script
grep -A5 "Check rollback triggers" ~/.claude/scripts/ab-test-monitor.sh

# Check Prometheus queries
curl -s "https://prometheus.jclee.me/api/v1/query?query=guardian_autonomous_rate" | jq
```

## Verification Checklist

### Pre-Production

- [ ] Grafana dashboards uploaded and accessible
- [ ] Prometheus scraping Pushgateway
- [ ] Loki receiving logs from rl-logger.sh
- [ ] Test metrics appear in dashboards
- [ ] Cron jobs installed (5 jobs)
- [ ] Systemd timer active (optional)
- [ ] Scripts executable and working

### Post-Production (24 hours)

- [ ] Daily metrics collection ran (00:00 KST)
- [ ] Daily training ran (02:00 KST)
- [ ] A/B test monitor ran (every 5 min)
- [ ] Logs accumulating in ~/.claude/logs/
- [ ] Data accumulating in ~/.claude/data/reinforcement-learning/
- [ ] No errors in cron logs

### Post-Production (7 days)

- [ ] Weekly patch generated (Sunday 04:00 KST)
- [ ] Patch file exists in ~/.claude/patches/
- [ ] Old data cleaned up (>30 days)
- [ ] System health metrics stable
- [ ] No unexpected rollbacks

## Next Steps

1. **Instrument Guardian Code**: Add `source guardian-metrics.sh` to actual Guardian scripts
2. **Create n8n Workflows**: Import 4 automation workflows to n8n.jclee.me
3. **Setup Alerts**: Configure AlertManager rules for critical thresholds
4. **Slack Integration**: Setup Slack webhook for rollback alerts
5. **Continuous Tuning**: Monitor metrics and adjust thresholds

## References

- [CLAUDE.md v11.16](../CLAUDE.md) - Constitutional framework with RL
- [Reinforcement Learning Deployment Summary](./reinforcement-learning-deployment-summary.md) - Complete implementation details
- [Guardian Metrics Script](../scripts/guardian-metrics.sh) - Metrics emission library
- [RL Logger Script](../scripts/rl-logger.sh) - Structured logging library
- [A/B Test Manager Script](../scripts/ab-test-manager.sh) - A/B testing CLI

---

**Status**: 2025-10-18 | Production Deployment Guide
**Version**: 1.0 | CLAUDE.md v11.16 Compatible
