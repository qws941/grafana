# Grafana Stack Operational Runbook
**Version**: 1.0
**Last Updated**: 2025-10-13
**Audience**: Operations team, SREs, DevOps engineers
**Stack Location**: Synology NAS (192.168.50.215:1111)

---

## Quick Reference

### Service URLs
| Service | URL | Port |
|---------|-----|------|
| Grafana | https://grafana.jclee.me | 3000 |
| Prometheus | https://prometheus.jclee.me | 9090 |
| Loki | https://loki.jclee.me | 3100 |
| AlertManager | https://alertmanager.jclee.me | 9093 |

### Default Credentials
- **Username**: `admin`
- **Password**: See `.env` file (`GRAFANA_ADMIN_PASSWORD`)

### SSH Access
```bash
ssh -p 1111 jclee@192.168.50.215
```

---

## Daily Operations

### 1. Health Check (Quick Verification)

**Command**:
```bash
# From local machine
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps --filter name=grafana-container --filter name=prometheus-container --filter name=loki-container --format 'table {{.Names}}\t{{.Status}}'"
```

**Expected Output**:
```
NAMES                  STATUS
grafana-container      Up X hours
prometheus-container   Up X hours
loki-container         Up X hours
```

**Automated Verification Script**:
```bash
# Run comprehensive verification
cd /home/jclee/app/grafana
./tests/deployment-verification.sh --quick
```

**Success Criteria**: All tests pass (exit code 0)

---

### 2. Check Prometheus Targets

**Purpose**: Verify all scrape targets are reachable

**Web UI**:
1. Open https://prometheus.jclee.me
2. Navigate to **Status → Targets**
3. Verify all targets show **UP** status

**CLI Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/targets" | \
  jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'
```

**Expected Output**:
```
prometheus: up
grafana: up
loki: up
alertmanager: up
node-exporter: up
cadvisor: up
n8n: up
# ... all targets showing "up"
```

**Troubleshooting**: If targets are DOWN, see section "Troubleshooting → Target DOWN"

---

### 3. View Recent Alerts

**Web UI**:
1. Open https://prometheus.jclee.me
2. Navigate to **Alerts**
3. Check for any PENDING or FIRING alerts

**CLI Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/alerts" | \
  jq '.data.alerts[] | select(.state != "inactive") | {alert: .labels.alertname, state: .state, value: .value}'
```

**Expected Output**: Empty (no active alerts) or only expected warnings

**Action Required**: If CRITICAL alerts are firing, see "Incident Response" section

---

### 4. Check Log Ingestion

**Purpose**: Verify logs are flowing from containers to Loki

**Web UI**:
1. Open https://grafana.jclee.me
2. Navigate to **Explore**
3. Select **Loki** datasource
4. Run query: `{job="docker-containers"}`

**CLI Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/query?query=rate(loki_distributor_lines_received_total[5m])'" | \
  jq -r '.data.result[0].value[1] // "0"'
```

**Expected Output**: Non-zero value (e.g., "150.5" logs/second)

**Troubleshooting**: If ingestion rate is 0, see "Troubleshooting → No Logs in Loki"

---

## Configuration Changes

### 1. Add New Prometheus Scrape Target

**File**: `configs/prometheus.yml`

**Steps**:
1. Edit configuration locally:
   ```bash
   cd /home/jclee/app/grafana
   vim configs/prometheus.yml
   ```

2. Add new scrape job:
   ```yaml
   scrape_configs:
     - job_name: 'my-new-service'
       static_configs:
         - targets: ['my-service.jclee.me:8080']
       metrics_path: '/metrics'
       scrape_interval: 15s
   ```

3. Save file (automatically synced within 1-2 seconds)

4. Validate syntax:
   ```bash
   ./tests/config-validation.sh
   ```

5. Hot reload Prometheus (no downtime):
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
   ```

6. Verify target appeared:
   ```bash
   # Check Prometheus UI: Status → Targets
   # Or CLI:
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/targets" | \
     jq '.data.activeTargets[] | select(.labels.job == "my-new-service")'
   ```

---

### 2. Update Alert Rules

**File**: `configs/alert-rules.yml`

**Steps**:
1. Edit alert rules locally:
   ```bash
   cd /home/jclee/app/grafana
   vim configs/alert-rules.yml
   ```

2. Add or modify alert rule:
   ```yaml
   - alert: MyNewAlert
     expr: my_metric > 100
     for: 5m
     labels:
       severity: warning
     annotations:
       summary: "My metric is too high"
       description: "Value: {{ $value }}"
   ```

3. Validate syntax:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container promtool check rules /etc/prometheus-configs/alert-rules.yml"
   ```

4. Hot reload Prometheus:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
   ```

5. Verify rule loaded:
   ```bash
   # Check Prometheus UI: Alerts
   # Or CLI:
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/rules" | \
     jq '.data.groups[].rules[] | select(.name == "MyNewAlert")'
   ```

---

### 3. Create New Dashboard

**Directory**: `configs/provisioning/dashboards/`

**Steps**:
1. Create dashboard in Grafana UI:
   - Open https://grafana.jclee.me
   - Create dashboard with panels
   - Set unique UID (e.g., `my-dashboard`)

2. Export dashboard JSON:
   - Click **Dashboard settings** (gear icon)
   - Click **JSON Model**
   - Copy JSON

3. Save to file locally:
   ```bash
   cd /home/jclee/app/grafana/configs/provisioning/dashboards
   vim 07-my-dashboard.json
   # Paste JSON
   ```

4. Set important fields:
   ```json
   {
     "uid": "my-dashboard",
     "title": "07 - My Dashboard",
     "id": null,
     "version": 1
   }
   ```

5. Validate JSON:
   ```bash
   jq empty 07-my-dashboard.json
   ```

6. Wait 10 seconds for auto-reload, or restart Grafana:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
   ```

7. Verify dashboard appears:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
     http://localhost:3000/api/dashboards/uid/my-dashboard"
   ```

---

### 4. Update Loki Configuration

**File**: `configs/loki-config.yaml`

**Steps**:
1. Edit configuration:
   ```bash
   cd /home/jclee/app/grafana
   vim configs/loki-config.yaml
   ```

2. Modify retention or other settings

3. Restart Loki (configuration changes require restart):
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart loki-container"
   ```

4. Wait ~10 seconds for startup

5. Verify Loki is ready:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec loki-container wget -qO- http://localhost:3100/ready"
   ```

**Expected Output**: `ready`

---

## Service Management

### 1. Restart Individual Container

**When to use**: After configuration changes (Loki, Grafana), or if container is unhealthy

**Command**:
```bash
# Restart specific container
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart <container-name>"

# Examples:
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart loki-container"
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"
```

**Downtime**:
- Grafana: ~10 seconds
- Loki: ~5 seconds
- Promtail: ~3 seconds
- Prometheus: Use hot reload instead (see below)

**Verification**:
```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps --filter name=<container-name>"
```

---

### 2. Hot Reload Prometheus (No Downtime)

**When to use**: After updating `prometheus.yml` or `alert-rules.yml`

**Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

**Expected Output**: Empty response (HTTP 200)

**Verification**:
```bash
# Check configuration was reloaded (timestamp should be recent)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/status/config" | \
  jq -r '.data.yaml' | head -20
```

---

### 3. Restart Entire Stack

**When to use**: Major configuration changes, version upgrades, emergency recovery

**⚠️ WARNING**: This will cause ~2-3 minutes of monitoring downtime

**Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && sudo docker compose restart"
```

**Startup Order** (automatic):
1. Prometheus, Loki, AlertManager (independent services)
2. Grafana (depends on Prometheus, Loki)
3. Promtail (depends on Loki)

**Verification**:
```bash
# Wait 30 seconds, then check all containers
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps"

# Run deployment verification
cd /home/jclee/app/grafana
./tests/deployment-verification.sh --quick
```

---

### 4. View Container Logs

**Real-time logs**:
```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f <container-name>"

# Examples:
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f grafana-container"
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f prometheus-container"
```

**Last 100 lines**:
```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs --tail 100 <container-name>"
```

**Search for errors**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs <container-name>" | grep -i error
```

---

## Troubleshooting

### 1. Prometheus Target DOWN

**Symptoms**:
- Target shows "DOWN" in Prometheus UI (Status → Targets)
- Alert: `PrometheusTargetDown` is firing

**Diagnosis**:
```bash
# 1. Check target details in Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, error: .lastError}'

# 2. Test connectivity from Prometheus container
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://<target-host>:<port>/metrics" | head -20

# 3. Check if target container is running
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps --filter name=<target-container>"
```

**Common Causes**:

1. **Target container not running**
   ```bash
   # Restart target container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart <target-container>"
   ```

2. **Wrong hostname or port in prometheus.yml**
   ```bash
   # Check config
   vim configs/prometheus.yml
   # Fix target address, hot reload Prometheus
   ```

3. **Network connectivity issue**
   ```bash
   # Verify target container is on monitoring-net network
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker inspect <target-container> --format '{{.NetworkSettings.Networks}}'"
   ```

4. **Metrics endpoint not available**
   ```bash
   # Check if /metrics endpoint exists
   curl -s http://<target-host>:<port>/metrics | head -20
   ```

---

### 2. No Logs in Loki

**Symptoms**:
- Query `{job="docker-containers"}` returns no results
- Log Analysis dashboard shows "No data"
- Alert: `LokiLowIngestionRate` firing

**Diagnosis**:
```bash
# 1. Check Loki ingestion rate
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/query?query=rate(loki_distributor_lines_received_total[5m])'" | \
  jq -r '.data.result[0].value[1] // "0"'

# 2. Check Promtail status
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs --tail 50 promtail-container"

# 3. Check Promtail targets
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs promtail-container" | grep -i "Adding target"
```

**Common Causes**:

1. **Promtail container not running**
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"
   ```

2. **Promtail not discovering containers**
   ```bash
   # Check docker_sd_configs is working
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs promtail-container" | grep "docker_sd"
   ```

3. **Loki rejecting logs (too old)**
   - Loki rejects logs older than 3 days
   - Check Loki logs for "entry out of order" errors
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs loki-container" | grep "out of order"
   ```

4. **Promtail position file corrupted**
   ```bash
   # Reset Promtail positions (re-reads all logs)
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec promtail-container sh -c 'echo \"positions:\" > /tmp/positions.yaml'"
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"
   ```

---

### 3. Grafana Dashboard Shows "No Data"

**Symptoms**:
- Dashboard panels show "No data" despite metrics existing
- Query in Explore works, but not in dashboard

**Diagnosis**:
```bash
# 1. Check datasource connection
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/datasources" | jq '.[] | {name: .name, type: .type, url: .url}'

# 2. Test datasource health
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=up"
```

**Common Causes**:

1. **Time range issue**
   - Check dashboard time range (top-right corner)
   - Verify data exists for selected time range

2. **Incorrect datasource UID**
   - Open dashboard JSON
   - Verify `datasource.uid` matches actual datasource UID
   ```bash
   # Get datasource UIDs
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
     http://localhost:3000/api/datasources" | jq '.[] | {uid: .uid, name: .name}'
   ```

3. **Query syntax error**
   - Copy query from panel
   - Test in Explore to verify it returns data

4. **Dashboard refresh rate**
   - Click dashboard refresh button manually
   - Check auto-refresh interval (top-right)

---

### 4. Real-time Sync Not Working

**Symptoms**:
- Local file changes not appearing on Synology NAS
- Dashboards/configs not updating after edits

**Diagnosis**:
```bash
# 1. Check sync service status
sudo systemctl status grafana-sync

# 2. View recent sync logs
sudo journalctl -u grafana-sync -n 50

# 3. Check for sync errors
sudo journalctl -u grafana-sync | grep -i error
```

**Common Causes**:

1. **Sync service not running**
   ```bash
   sudo systemctl start grafana-sync
   sudo systemctl enable grafana-sync  # Auto-start on boot
   ```

2. **SSH connection issue**
   ```bash
   # Test SSH connectivity
   ssh -p 1111 jclee@192.168.50.215 "echo 'Connection OK'"
   ```

3. **File permissions issue**
   ```bash
   # Check file ownership
   ls -la configs/
   # Should be owned by current user
   ```

4. **Debounce delay**
   - Normal behavior: 1-2 second delay after file change
   - Wait 5 seconds and check again

**Manual sync trigger**:
```bash
# If auto-sync fails, manually sync
rsync -avz --exclude .git --exclude node_modules \
  -e "ssh -p 1111" \
  /home/jclee/app/grafana/ \
  jclee@192.168.50.215:/volume1/grafana/
```

---

### 5. High Memory Usage

**Symptoms**:
- Prometheus/Grafana container using excessive memory
- System slowness
- Alert: `N8NHighMemoryUsage` or similar firing

**Diagnosis**:
```bash
# 1. Check container memory usage
ssh -p 1111 jclee@192.168.50.215 "sudo docker stats --no-stream"

# 2. Check Prometheus cardinality
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series'"

# 3. Check Prometheus ingestion rate
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/query?query=rate(prometheus_tsdb_head_samples_appended_total[5m])'"
```

**Solutions**:

1. **Reduce scrape frequency** (if cardinality is high)
   ```yaml
   # In prometheus.yml
   scrape_interval: 30s  # Change from 15s to 30s
   ```

2. **Reduce retention period** (if storage is high)
   ```yaml
   # In docker-compose.yml, Prometheus command:
   - '--storage.tsdb.retention.time=15d'  # Change from 30d
   ```

3. **Restart container** (temporary relief)
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart prometheus-container"
   ```

4. **Drop unnecessary metrics** (advanced)
   ```yaml
   # In prometheus.yml, add metric_relabel_configs
   metric_relabel_configs:
     - source_labels: [__name__]
       regex: 'unnecessary_metric_.*'
       action: drop
   ```

---

## Incident Response

### 1. Critical Alert Fired

**Severity**: CRITICAL
**Response Time**: Immediate (<5 minutes)

**Steps**:

1. **Acknowledge alert** (if using AlertManager webhook → n8n)

2. **Identify affected service**:
   ```bash
   # Check recent alerts
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/alerts" | \
     jq '.data.alerts[] | select(.state == "firing" and .labels.severity == "critical")'
   ```

3. **Access relevant runbook**:
   - See `docs/ALERT-TUNING-GUIDE.md` for alert-specific runbooks
   - Check alert annotation `runbook_url` field

4. **Check Grafana dashboard** (linked in alert annotation `grafana_url`)

5. **Execute runbook procedures**

6. **Document incident** (create incident report if service was impacted)

---

### 2. Service Completely Down

**Severity**: CRITICAL
**Impact**: Full monitoring stack unavailable

**Steps**:

1. **Check Synology NAS is reachable**:
   ```bash
   ping 192.168.50.215
   ssh -p 1111 jclee@192.168.50.215 "uptime"
   ```

2. **Check if containers crashed**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps -a"
   ```

3. **Check Docker service**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo systemctl status docker"
   ```

4. **Restart stack**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && sudo docker compose up -d"
   ```

5. **Verify all containers started**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps"
   ```

6. **Run deployment verification**:
   ```bash
   cd /home/jclee/app/grafana
   ./tests/deployment-verification.sh
   ```

7. **Check for recent configuration changes** (git log):
   ```bash
   cd /home/jclee/app/grafana
   git log --oneline -10
   ```

8. **If issue persists, rollback recent changes**:
   ```bash
   git revert <commit-hash>
   # Wait for auto-sync, then restart affected services
   ```

---

### 3. Data Loss or Corruption

**Severity**: HIGH
**Impact**: Metrics or logs missing

**Steps**:

1. **Identify scope of data loss**:
   - Check time range of missing data
   - Check which services affected (Prometheus/Loki)

2. **For Prometheus**:
   - Prometheus has 30-day retention
   - No backup/restore capability (re-scrape from source)
   - Focus on preventing future data loss

3. **For Loki**:
   - Loki has 3-day retention
   - No backup/restore capability
   - Focus on preventing future data loss

4. **Check volume integrity**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "df -h /volume1/docker/grafana"
   ssh -p 1111 jclee@192.168.50.215 "du -sh /volume1/docker/grafana/*"
   ```

5. **Check for disk space issues**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "df -h"
   ```

6. **Document incident** and implement preventive measures

---

## Maintenance Tasks

### 1. Check Disk Space Usage

**Frequency**: Weekly

**Command**:
```bash
ssh -p 1111 jclee@192.168.50.215 "df -h /volume1 && du -sh /volume1/docker/grafana/*"
```

**Expected Usage**:
- Prometheus: ~5-10 GB (30-day retention)
- Loki: ~2-5 GB (3-day retention)
- Grafana: ~100-500 MB
- AlertManager: ~50-100 MB

**Action if high**:
- Reduce Prometheus retention: `--storage.tsdb.retention.time=15d`
- Reduce Loki retention: Change `retention_period` in `loki-config.yaml`

---

### 2. Review Alert Firing Frequency

**Frequency**: Monthly

**Steps**:
1. Check AlertManager UI: https://alertmanager.jclee.me
2. Identify noisy alerts (firing too frequently)
3. Tune thresholds using methodology in `docs/ALERT-TUNING-GUIDE.md`
4. Update `configs/alert-rules.yml`

---

### 3. Update Docker Images

**Frequency**: Quarterly (or when security patches released)

**⚠️ WARNING**: Test in staging before production

**Steps**:
```bash
# 1. Backup current state
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' > /tmp/grafana-images-backup.txt"

# 2. Pull latest images
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && sudo docker compose pull"

# 3. Recreate containers with new images
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && sudo docker compose up -d"

# 4. Verify all services healthy
cd /home/jclee/app/grafana
./tests/deployment-verification.sh

# 5. If issues, rollback
# ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && sudo docker compose down"
# # Manually revert to old image IDs, then docker compose up -d
```

---

### 4. Clean Up Old Docker Images

**Frequency**: Monthly

**Command**:
```bash
# Remove unused images
ssh -p 1111 jclee@192.168.50.215 "sudo docker image prune -a -f"

# Remove unused volumes (⚠️ DANGEROUS - only if volumes not in use)
# ssh -p 1111 jclee@192.168.50.215 "sudo docker volume prune -f"
```

---

## Performance Tuning

### 1. Optimize Dashboard Query Performance

**Check Query Performance Dashboard**: https://grafana.jclee.me/d/query-performance

**If P95 latency > 2s**:

1. **Reduce query time range**:
   - Change default time range from 24h to 6h
   - Use time range variables

2. **Add recording rules** (pre-compute expensive queries):
   ```yaml
   # In configs/alert-rules.yml
   groups:
     - name: recording_rules
       interval: 30s
       rules:
         - record: job:container_memory_usage:sum
           expr: sum(container_memory_usage_bytes{name!=""}) by (name)
   ```

3. **Use query caching** (enable in Grafana):
   - Settings → Data Sources → Prometheus
   - Enable "Cache timeout"

---

### 2. Reduce Prometheus Cardinality

**If cardinality > 500k time series**:

1. **Drop unnecessary labels**:
   ```yaml
   # In prometheus.yml
   metric_relabel_configs:
     - source_labels: [verbose_label]
       action: labeldrop
   ```

2. **Aggregate before storage**:
   ```yaml
   # Use recording rules for aggregations
   - record: job:http_requests:rate5m
     expr: sum(rate(http_requests_total[5m])) by (job)
   ```

---

## Backup and Recovery

### Current State: No Automated Backups

**Data Retention**:
- Prometheus: 30 days (no backup, data is ephemeral)
- Loki: 3 days (no backup, data is ephemeral)
- Grafana: Persistent (dashboards provisioned from git)

**Recovery Strategy**:
1. **Configuration**: All configs in git (`/home/jclee/app/grafana`)
2. **Dashboards**: Provisioned from JSON files (in git)
3. **Metrics**: Re-scrape from source (Prometheus)
4. **Logs**: Historical logs not recoverable (3-day retention)

**Disaster Recovery**:
1. Clone repository: `git clone https://github.com/qws941/grafana.git`
2. Run volume structure script: `./scripts/create-volume-structure.sh`
3. Deploy stack: `sudo docker compose up -d`
4. Verify deployment: `./tests/deployment-verification.sh`

---

## Contact Information

**Primary Contact**: Operations Team
**Escalation**: SRE Team
**Documentation**: `/home/jclee/app/grafana/docs/`
**Issues**: https://github.com/qws941/grafana/issues

---

## Appendix: Quick Command Reference

```bash
# Health Check
./tests/deployment-verification.sh --quick

# View Logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f <container-name>"

# Restart Container
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart <container-name>"

# Hot Reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# Check Sync Status
sudo systemctl status grafana-sync
sudo journalctl -u grafana-sync -f

# Validate Configuration
./tests/config-validation.sh

# Check Prometheus Targets
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/targets" | \
  jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'

# Check Loki Ingestion
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- 'http://localhost:9090/api/v1/query?query=rate(loki_distributor_lines_received_total[5m])'" | \
  jq -r '.data.result[0].value[1]'
```

---

**Version History**:
- v1.0 (2025-10-13): Initial runbook creation
