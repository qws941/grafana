# Alert System Setup Guide

**Date**: 2025-10-13
**Status**: ✅ Configuration Complete - Awaiting n8n Workflow Import

---

## Overview

The Grafana monitoring stack now includes a comprehensive alerting system:

- **Alert Rules**: 20 rules across 4 categories (prometheus_monitoring, n8n_monitoring, log_collection_alerts, grafana_monitoring)
- **AlertManager**: Configured to send webhooks to n8n
- **n8n Workflow**: Webhook handler for alert notifications
- **Grafana Dashboard**: Alert visualization and monitoring

---

## Architecture

```
┌─────────────┐    Alert Rules    ┌──────────────┐
│ Prometheus  │ ───────────────► │ AlertManager │
└─────────────┘                   └──────────────┘
                                          │
                                          │ Webhook (POST)
                                          │ http://n8n-container:5678/webhook/alerts
                                          ▼
                                  ┌──────────────┐
                                  │  n8n Webhook │
                                  │   Workflow   │
                                  └──────────────┘
                                          │
                        ┌─────────────────┼─────────────────┐
                        │                 │                 │
                        ▼                 ▼                 ▼
                  ┌──────────┐     ┌──────────┐     ┌──────────┐
                  │ Critical │     │ Warning  │     │   Loki   │
                  │  Alerts  │     │  Alerts  │     │   Logs   │
                  │ (Console)│     │ (Console)│     │ (Storage)│
                  └──────────┘     └──────────┘     └──────────┘
```

---

## Setup Status

### ✅ Completed Components

1. **Alert Rules** (`/home/jclee/app/grafana/configs/alert-rules.yml`)
   - 4 rule groups
   - 20 alert rules
   - Already loaded in Prometheus

2. **AlertManager Configuration** (`/home/jclee/app/grafana/configs/alertmanager.yml`)
   - Webhook receivers configured
   - Routing rules by severity
   - Already reloaded and active

3. **Grafana Dashboard** (`alert-overview.json`)
   - Active alerts count
   - Alert timeline
   - Alerts by service
   - Notification success rate
   - Auto-provisioned and accessible

4. **n8n Workflow JSON** (`/home/jclee/app/grafana/configs/n8n-workflows/alertmanager-webhook.json`)
   - Created and ready for import
   - Handles webhook from AlertManager
   - Routes by severity
   - Logs to Loki

### ⏳ Pending: n8n Workflow Import

The n8n workflow needs to be imported manually via n8n UI.

---

## Step-by-Step: Import n8n Workflow

### Option 1: n8n UI Import (Recommended)

1. **Access n8n**:
   ```bash
   https://n8n.jclee.me
   ```

2. **Import Workflow**:
   - Click **"Workflows"** in left menu
   - Click **"+"** → **"Import from File"**
   - Select: `/home/jclee/app/grafana/configs/n8n-workflows/alertmanager-webhook.json`

   Or copy from Synology NAS:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "cat /tmp/alertmanager-webhook.json"
   ```

3. **Activate Workflow**:
   - Open the imported workflow
   - Click **"Active"** toggle (top right)
   - Ensure status shows "Active"

4. **Copy Webhook URL**:
   - Click on "AlertManager Webhook" node
   - Copy the webhook URL (should be: `http://n8n.jclee.me/webhook/alerts` or similar)
   - Verify it matches AlertManager configuration

### Option 2: n8n CLI Import (Advanced)

```bash
# SSH to Synology NAS
ssh -p 1111 jclee@192.168.50.215

# Import via n8n CLI (if available)
sudo docker exec n8n-container n8n import:workflow --input=/tmp/alertmanager-webhook.json

# Activate workflow
sudo docker exec n8n-container n8n import:workflow --activate
```

---

## Verification

### 1. Check Workflow is Active

```bash
ssh -p 1111 jclee@192.168.50.215 "curl -s 'http://localhost:5678/api/v1/workflows' | jq -r '.data[] | select(.name | contains(\"AlertManager\")) | {id: .id, name: .name, active: .active}'"
```

Expected output:
```json
{
  "id": "...",
  "name": "AlertManager Webhook Handler",
  "active": true
}
```

### 2. Check AlertManager Configuration

```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker exec alertmanager-container wget -qO- http://localhost:9093/api/v2/status 2>/dev/null | jq -r '.config.receivers[] | select(.name == \"web.hook\")'"
```

Should show:
```json
{
  "name": "web.hook",
  "webhook_configs": [
    {
      "url": "http://n8n-container:5678/webhook/alerts",
      "send_resolved": true,
      "max_alerts": 0
    }
  ]
}
```

### 3. View Active Alerts

```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | jq -r '.data.alerts[] | select(.state == \"firing\") | {alert: .labels.alertname, severity: .labels.severity, summary: .annotations.summary}'"
```

---

## Testing Alert Flow

### Method 1: Trigger Test Alert (Safe)

Create a temporary alert rule that will immediately fire:

```bash
# SSH to Synology
ssh -p 1111 jclee@192.168.50.215

# Create test alert rule
cat >> /volume1/grafana/configs/test-alert.yml <<'EOF'
groups:
  - name: test_alerts
    interval: 10s
    rules:
      - alert: TestAlert
        expr: vector(1)
        for: 0s
        labels:
          severity: warning
          service: test
        annotations:
          summary: "Test alert for n8n webhook verification"
          description: "This is a test alert to verify the alerting pipeline"
          grafana_url: "https://grafana.jclee.me"
EOF

# Reload Prometheus with test rule
sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload
```

**Check alert fired**:
```bash
# Wait 30 seconds, then check
sleep 30
ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | jq -r '.data.alerts[] | select(.labels.alertname == \"TestAlert\")'"
```

**Check n8n received webhook**:
```bash
# Check n8n workflow executions
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs n8n-container --tail 50 | grep -i 'test alert'"
```

**Clean up test alert**:
```bash
ssh -p 1111 jclee@192.168.50.215 "sudo rm /volume1/grafana/configs/test-alert.yml && sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

### Method 2: Use AlertManager amtool

```bash
# SSH to Synology
ssh -p 1111 jclee@192.168.50.215

# Send test alert via amtool
sudo docker exec alertmanager-container amtool alert add \
  --annotation=summary="Test Alert from amtool" \
  --annotation=description="This is a test alert sent directly to AlertManager" \
  --label=alertname=TestAmtoolAlert \
  --label=severity=warning \
  --label=service=test \
  TestAmtoolAlert
```

### Method 3: Check Existing Alerts

If any alerts are currently firing, they will automatically be sent to n8n:

```bash
# View firing alerts
ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | jq -r '.data.alerts[] | select(.state == \"firing\")'"
```

---

## Grafana Dashboard Access

**Alert Overview Dashboard**:
- URL: https://grafana.jclee.me/d/alert-overview
- Refresh: 10 seconds
- Features:
  - Active alerts count (total, critical, warning)
  - Alert notifications rate
  - Active alerts details table
  - Alert timeline graph
  - Alerts by service (pie chart)
  - Notification success rate

---

## Alert Rules Reference

### Prometheus Monitoring Alerts

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| `PrometheusTargetDown` | critical | 2 min | Critical services (prometheus, grafana, loki, n8n) down |
| `PrometheusHTTPErrorRateHigh` | warning | >1% for 5min | Prometheus HTTP error rate high |
| `PrometheusScrapeFailureRateHigh` | warning | >5% for 5min | Prometheus scrape errors |
| `PrometheusTSDBCorruption` | critical | >0 in 1h | TSDB corruption detected |

### n8n Monitoring Alerts

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| `N8nWorkflowFailureRateHigh` | warning | >5 failures/min | Workflow failure rate high |
| `N8nEventLoopLagHigh` | critical | >0.5s for 5min | Event loop lag critical |
| `N8nMemoryUsageHigh` | warning | >2GB for 5min | Memory usage high |
| `N8nGarbageCollectionSlow` | warning | >0.1s avg for 5min | GC duration high |
| `N8nNoActiveWorkflows` | critical | 0 workflows for 10min | No active workflows (possible crash) |

### Log Collection Alerts

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| `PromtailDown` | critical | 2 min | Promtail is down |
| `LokiDown` | critical | 2 min | Loki is down |
| `NoLogsIngested` | warning | 5 min | No logs being ingested |
| `ClaudeCodeLogsStale` | warning | >1h for 10min | Claude Code logs not updating |
| `HighLogIngestionErrors` | warning | >5% for 5min | High log ingestion error rate |
| `LokiStorageAlmostFull` | warning | >80% for 10min | Loki storage almost full |
| `PromtailFileReadErrors` | warning | >0 for 5min | Promtail file read errors |
| `ContainerLogsMissing` | warning | <14 containers | Some containers not logging |

### Grafana Monitoring Alerts

| Alert | Severity | Threshold | Description |
|-------|----------|-----------|-------------|
| `GrafanaHTTPErrorRateHigh` | warning | >1% for 5min | Grafana HTTP error rate high |
| `GrafanaResponseTimeSlow` | warning | P95 >2s for 5min | Grafana response time slow |
| `GrafanaAlertingEngineDown` | critical | 0 configs for 5min | Grafana alerting not active |

---

## n8n Workflow Details

### Workflow: "AlertManager Webhook Handler"

**Webhook Endpoint**: `http://n8n-container:5678/webhook/alerts`

**Workflow Steps**:

1. **Webhook Receiver** (AlertManager Webhook)
   - Receives POST requests from AlertManager
   - Payload: AlertManager webhook format

2. **Parse Alerts** (Function Node)
   - Extracts alert details (severity, service, instance)
   - Formats message for notifications
   - Prepares log entry for Loki

3. **Filter Critical Alerts** (IF Node)
   - Routes critical alerts to console logging
   - For future: Can add Discord/Slack/Email notifications

4. **Filter Warning Alerts** (IF Node)
   - Routes warning alerts to console logging
   - For future: Can add different notification channels

5. **Format Loki Log** (Function Node)
   - Converts alert to Loki log format
   - Adds labels: job=alertmanager, severity, alertname, service

6. **Push to Loki** (HTTP Request Node)
   - Sends log to Loki for persistent storage
   - URL: `http://loki-container:3100/loki/api/v1/push`

**Console Log Output Example**:
```
=== CRITICAL ALERT ===
🔥 🚨 **PrometheusTargetDown** (critical)
**Service**: prometheus | localhost:9090
**Summary**: Critical Prometheus target down
**Description**: Prometheus target prometheus (localhost:9090) is down
**Dashboard**: https://prometheus.jclee.me/targets
**Status**: firing
**Started**: 2025-10-13 01:30:00
=====================
```

**Loki Log Entry Example**:
```json
{
  "timestamp": "2025-10-13T01:30:00.000Z",
  "level": "error",
  "alertname": "PrometheusTargetDown",
  "service": "prometheus",
  "instance": "localhost:9090",
  "status": "firing",
  "summary": "Critical Prometheus target down",
  "description": "Prometheus target prometheus (localhost:9090) is down",
  "fingerprint": "abc123..."
}
```

---

## Future Enhancements

### 1. Discord/Slack Integration

Replace console logging nodes with Discord/Slack webhook nodes:

```javascript
// Discord Webhook Node
{
  "content": "",
  "embeds": [{
    "title": $json.alertname,
    "description": $json.summary,
    "color": $json.severity === 'critical' ? 15158332 : 16776960,
    "fields": [
      {"name": "Service", "value": $json.service, "inline": true},
      {"name": "Instance", "value": $json.instance, "inline": true},
      {"name": "Status", "value": $json.status, "inline": true}
    ],
    "timestamp": new Date().toISOString()
  }]
}
```

### 2. Email Notifications

Add Email node for critical alerts:
- SMTP configuration in n8n settings
- HTML email template with alert details
- Send only for critical severity

### 3. Alert Aggregation

Add aggregation logic in n8n:
- Group alerts by service
- Send digest emails every hour
- Reduce notification fatigue

### 4. Alert Acknowledgment

Add bidirectional integration:
- Discord/Slack buttons to acknowledge alerts
- Update AlertManager silence via API
- Track who acknowledged alerts

### 5. On-Call Rotation

Integrate with PagerDuty/Opsgenie:
- Route critical alerts to on-call engineer
- Escalation policies
- Incident management

---

## Troubleshooting

### Alert Not Firing

1. **Check alert rule syntax**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container promtool check rules /etc/prometheus-configs/alert-rules.yml"
   ```

2. **Check Prometheus evaluation**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/rules' 2>/dev/null | jq -r '.data.groups[] | select(.name == \"YOUR_GROUP\")'"
   ```

3. **Check alert state**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/alerts' 2>/dev/null | jq -r '.data.alerts[] | select(.labels.alertname == \"YOUR_ALERT\")'"
   ```

### AlertManager Not Sending Webhooks

1. **Check AlertManager config**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec alertmanager-container amtool config show"
   ```

2. **Check webhook connectivity**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec alertmanager-container wget -qO- http://n8n-container:5678/webhook/alerts 2>&1"
   ```

3. **Check AlertManager logs**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs alertmanager-container --tail 100 | grep -i webhook"
   ```

### n8n Workflow Not Executing

1. **Check workflow is active**:
   - Open n8n UI
   - Ensure "Active" toggle is ON

2. **Check webhook URL**:
   - Verify webhook path matches AlertManager config
   - Check for typos in URL

3. **Check n8n logs**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs n8n-container --tail 100"
   ```

4. **Test webhook manually**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "curl -X POST 'http://n8n-container:5678/webhook/alerts' -H 'Content-Type: application/json' -d '{\"alerts\": [{\"status\": \"firing\", \"labels\": {\"alertname\": \"TestAlert\", \"severity\": \"warning\"}, \"annotations\": {\"summary\": \"Test\", \"description\": \"Manual test\"}}]}'"
   ```

### Loki Not Receiving Alert Logs

1. **Check Loki connectivity from n8n**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec n8n-container wget -qO- http://loki-container:3100/ready"
   ```

2. **Check Loki ingestion logs**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs loki-container --tail 100 | grep -E 'POST /loki/api/v1/push'"
   ```

3. **Query Loki for alert logs**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker exec grafana-container curl -s -u 'admin:bingogo1' 'http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=%7Bjob%3D%22alertmanager%22%7D&start=$(date -u -d '1 hour ago' +%s)000000000&end=$(date -u +%s)000000000' | jq -r '.data.result[].values[] | .[1]'"
   ```

---

## Next Steps

1. **Import n8n Workflow** (Manual step required)
   - Follow "Step-by-Step: Import n8n Workflow" section above

2. **Test Alert Flow**
   - Use test alert method to verify end-to-end flow

3. **Monitor Alert Dashboard**
   - Open https://grafana.jclee.me/d/alert-overview
   - Verify metrics are populating

4. **Enhance Notifications** (Optional)
   - Add Discord/Slack webhooks
   - Configure email notifications
   - Set up on-call rotation

---

## Summary

| Component | Status | Action Required |
|-----------|--------|-----------------|
| Alert Rules | ✅ Active | None |
| AlertManager Config | ✅ Active | None |
| Grafana Dashboard | ✅ Loaded | None |
| n8n Workflow JSON | ✅ Created | **Manual Import Required** |
| Alert Routing | ⏳ Pending | Import n8n workflow |
| Notification Channels | ⏳ Pending | Configure Discord/Slack (optional) |

**Current State**: Alert rules are active and evaluating. AlertManager is configured to send webhooks to n8n. The final step is to import the n8n workflow to complete the alerting pipeline.

---

**Last Updated**: 2025-10-13 01:45 KST
**Next Review**: After n8n workflow import and testing
