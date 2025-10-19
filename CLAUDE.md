# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Grafana Monitoring Stack on **Synology NAS** (192.168.50.215:1111). Local `/home/jclee/app/grafana` is **NFS-mounted** from `192.168.50.215:/volume1/grafana`.

**Critical**: NOT local. All services run on NAS. Changes via NFS are instant.

## ⚡ Quick Reference

### Most Used Commands

```bash
# Verify NFS mount
mount | grep grafana

# Validate metrics (MANDATORY before dashboards)
./scripts/validate-metrics.sh --list | grep <pattern>

# Reload Prometheus (hot reload)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# Restart Grafana
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"

# Check container health
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep -E 'grafana|prometheus|loki'"

# Run health check
./scripts/health-check.sh
```

### Access Points

- Grafana: https://grafana.jclee.me (admin / from .env)
- Prometheus: https://prometheus.jclee.me
- Loki: https://loki.jclee.me
- AlertManager: https://alertmanager.jclee.me
- SSH: `ssh -p 1111 jclee@192.168.50.215`

### Critical Rules

1. **Always validate metrics before creating dashboards** (2025-10-13 incident: P95 doesn't exist, only P50/P90/P99)
2. **Use full container names** in configs (e.g., `prometheus-container:9090`)
3. **Dashboard methodology**: REDS (applications), USE (infrastructure)
4. **Never create dashboards manually in UI** (auto-provisioned every 10s, will be overwritten)
5. **Grafana auto-provisions dashboards every 10 seconds** from `configs/provisioning/dashboards/*.json`

## Deployment Architecture

```
Local Machine (Development)          Synology NAS (192.168.50.215:1111)
───────────────────────────          ──────────────────────────────────
/home/jclee/app/grafana/             /volume1/grafana/
(NFS Mount)               ◄═══════► (NFS Share)
├── configs/                          ├── configs/
├── scripts/                          ├── scripts/
├── docker-compose.yml                ├── docker-compose.yml
└── docs/                             └── data/
                                          ├── grafana/
NFS Mount Details:                        ├── prometheus/
├── Source: 192.168.50.215:/volume1/grafana    ├── loki/
├── Type: NFS v3                                └── alertmanager/
├── Options: rw,noatime,hard
└── Auto-mount: /etc/fstab           Docker Services:
                                     - grafana-container      (3000)
                                     - prometheus-container   (9090)
                                     - loki-container         (3100)
                                     - alertmanager-container (9093)
                                     - promtail-container
                                     - node-exporter-container
                                     - cadvisor-container
```

## Essential Operations

### NFS Mount Troubleshooting

```bash
# Remount if connection issues
sudo umount /home/jclee/app/grafana
sudo mount -a

# Verify mount options
cat /etc/fstab | grep grafana
# Should show: 192.168.50.215:/volume1/grafana /home/jclee/app/grafana nfs rw,noatime,hard 0 0
```

### Service Reload Details

**Prometheus** (hot reload, no downtime):
- Command: `wget --post-data='' -qO- http://localhost:9090/-/reload`
- Reloads: `prometheus.yml`, `alert-rules.yml`, `recording-rules.yml`
- Verification: Check https://prometheus.jclee.me/config

**Grafana** (requires restart):
- Dashboards: Auto-provisioned every 10s (no restart needed for dashboard changes)
- Config changes: Restart required
- Verification: Check https://grafana.jclee.me/api/health

**Loki** (requires restart):
- Config: `loki-config.yaml`
- Verification: Check https://loki.jclee.me/ready

## Architecture Deep Dive

### Service Network Topology

**Networks:**
- `traefik-public` (external): Reverse proxy with SSL via CloudFlare
- `grafana-monitoring-net` (bridge): Internal service communication

**Container Naming Convention:**
- Service name in docker-compose.yml: `grafana`
- Actual container name: `grafana-container`
- **IMPORTANT**: Always use **full container names** in configs (e.g., `prometheus-container:9090`)

### Data Flow Pipelines

```
┌─────────────────────────────────────────────────────────┐
│ Metrics Collection                                      │
├─────────────────────────────────────────────────────────┤
│ Services ──► Prometheus (scrape) ──► Grafana (query)  │
│ - node-exporter:9100   (system metrics)                 │
│ - cadvisor:8080        (container metrics)              │
│ - n8n:5678/metrics     (application metrics)            │
│ - local exporters (192.168.50.100:9101, 8081)          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Log Collection                                          │
├─────────────────────────────────────────────────────────┤
│ Docker Logs ──► Promtail ──► Loki ──► Grafana         │
│                                                          │
│ Important: Promtail uses Docker Service Discovery       │
│ Auto-discovers containers on grafana-monitoring-net     │
│ ⚠️  Synology `db` driver blocks some log collection    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Alerting Pipeline                                       │
├─────────────────────────────────────────────────────────┤
│ Prometheus Rules ──► AlertManager ──► Webhooks         │
│ Alert rules: configs/alert-rules.yml (20 rules active) │
└─────────────────────────────────────────────────────────┘
```

### Configuration Management

**Prometheus Scrape Targets** (`configs/prometheus.yml`):
- Core: prometheus, grafana, loki, alertmanager
- Exporters: node-exporter, cadvisor
- Applications: n8n (workflow automation)
- Local: node-exporter (192.168.50.100:9101), cadvisor (192.168.50.100:8081)

**Hot Reload Support**:
- Prometheus: ✅ Yes (`--web.enable-lifecycle`)
- Grafana: ❌ No (restart required, but dashboards auto-provision every 10s)
- Loki: ❌ No (restart required)

**Recording Rules** (`configs/recording-rules.yml`):
- 7 groups with 32 rules total across performance, container, and application metrics
- n8n-specific rules (updated 2025-10-16): `n8n:workflows:start_rate`, `n8n:workflows:active_count`, `n8n:cache:miss_rate_percent`, `n8n:queue:enqueue_rate`, `n8n:nodejs:eventloop_lag_p99`, `n8n:nodejs:memory_usage_mb`, `n8n:nodejs:gc_duration_avg`
- **Critical**: All recording rules use validated metrics only (learned from 2025-10-13 P95 incident, fixed 2025-10-16)

**Promtail Configuration** (`configs/promtail-config.yml`):
- **docker-containers** job: Auto-discovers via `docker_sd_configs`
- **system-logs** job: Scrapes `/var/log/*.log`
- **Loki Retention**: 3 days (older logs rejected)

**Grafana Auto-Provisioning**:
- **Datasources**: `configs/provisioning/datasources/datasource.yml`
  - Prometheus (UID: `prometheus`) - Default
  - Loki (UID: `loki`)
  - AlertManager (UID: `P4AAF3E0C04587B6C`)
- **Dashboards**: `configs/provisioning/dashboards/*.json`
  - Auto-loaded + refreshed every 10 seconds
  - **Do NOT create manually in UI** (will be overwritten)
- **Folder Structure**: 5 folders (Core-Monitoring, Infrastructure, Applications, Logging, Alerting)

### Dashboard Structure & Methodologies

**Current Dashboards**:
1. Monitoring Stack Health - Self-monitoring (USE methodology)
2. System Metrics - Infrastructure (USE methodology)
3. Container Performance - Docker metrics
4. **n8n Workflow Automation (REDS)** - Application monitoring with 15 panels
5. Log Analysis - Log aggregation

**REDS Methodology** (for application dashboards like n8n):
- **Rate**: Throughput (workflows/min, active count)
- **Errors**: Failure rate, error count
- **Duration**: Response time percentiles (P50, P90, P99)
- **Saturation**: Resource utilization (active handles, requests)

**USE Methodology** (for infrastructure dashboards):
- **Utilization**: CPU %, memory %, disk %
- **Saturation**: Load average, queue depth
- **Errors**: Error rates and counts

**Dashboard Design Principles**:
- **ALWAYS validate metrics exist** before adding panels
- Golden Signals in top row (4 overview panels)
- Set appropriate units (`bytes`, `percent`, `s`)
- Configure meaningful thresholds (green/yellow/orange/red)
- Include legend calculations: `mean`, `last`, `max`
- Use smooth interpolation and gradient opacity
- Use correct datasource UIDs: `"uid": "prometheus"` or `"uid": "loki"`

**Common Panel Queries** (updated 2025-10-16):
```promql
# n8n workflow metrics (validated)
n8n_active_workflow_count
rate(n8n_workflow_started_total[5m]) * 60  # Workflow start rate
rate(n8n_cache_misses_total[5m]) / (rate(n8n_cache_hits_total[5m]) + rate(n8n_cache_misses_total[5m])) * 100  # Cache miss rate
rate(n8n_queue_job_enqueued_total[5m]) * 60  # Queue enqueue rate
n8n_nodejs_eventloop_lag_p99_seconds  # NOT p95 (doesn't exist)

# Container metrics
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100
container_memory_usage_bytes{name!=""}

# System metrics
rate(node_cpu_seconds_total[5m]) * 100
node_memory_MemAvailable_bytes
```

### Alert Rules Configuration

**Alert Rules** (`configs/alert-rules.yml`): 20 rules across 4 groups

**Key Alerts**:
- N8nWorkflowFailureRateHigh: >5/min for 5m → WARNING
- N8nEventLoopLagHigh: >0.5s P99 for 5m → CRITICAL (uses P99, not P95)
- PrometheusTargetDown: Critical service down → CRITICAL
- PromtailDown: Log collector down → CRITICAL

**Adding Alert Rules**:
1. Edit `configs/alert-rules.yml`
2. Wait 1-2s for sync
3. Reload: `curl -X POST https://prometheus.jclee.me/-/reload`
4. Verify: https://prometheus.jclee.me/alerts

### Synology Platform Constraints

**Docker Logging Driver Limitation**:
- Synology enforces `db` logging driver system-wide (cannot override)
- Promtail **cannot** read logs from `db` driver containers
- **Solution**: Use Prometheus metrics instead (more reliable)
- See `docs/N8N-LOG-INVESTIGATION-2025-10-12.md` for details

**Volume Permissions** (critical for first deployment):
- Grafana: `472:472`
- Prometheus: `65534:65534`
- Loki: `10001:10001`
- Run `scripts/create-volume-structure.sh` on NAS to set ownership

## Common Development Patterns

### Adding New Prometheus Scrape Target

1. **Verify endpoint exists**:
```bash
curl -s http://service:port/metrics | head -20
```

2. **Add to `configs/prometheus.yml`**:
```yaml
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['service-container:port']
    metrics_path: '/metrics'
```

3. **Wait for sync (1-2s), reload**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

4. **Verify**: https://prometheus.jclee.me/targets

### Creating New Grafana Dashboard

**CRITICAL: Validate Metrics First** (prevents "No data" panels)

1. **Validate metrics exist**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep service_name

# Test query returns data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=your_metric_name'" | \
  jq '.data.result'
```

2. **Create dashboard JSON** following REDS or USE methodology:
```json
{
  "uid": "my-dashboard",
  "title": "Applications - My Service (REDS)",
  "tags": ["applications", "my-service", "reds-methodology"],
  "panels": [
    {
      "id": 1,
      "title": "🚀 RATE: Request Rate",
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "rate(verified_metric_name[5m])"}],
      "type": "stat",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "steps": [
              {"color": "green", "value": null},
              {"color": "yellow", "value": 50},
              {"color": "red", "value": 80}
            ]
          }
        }
      }
    }
  ],
  "schemaVersion": 38,
  "version": 1
}
```

3. **Save to `configs/provisioning/dashboards/my-dashboard.json`**
4. **Auto-provision**: Changes are instant via NFS. Grafana scans every 10 seconds, so max 10s latency
5. **Verify dashboard loads**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  'http://localhost:3000/api/dashboards/uid/my-dashboard'" | \
  jq '.dashboard.title'
```

### Adding Recording Rules

**CRITICAL: Validate Source Metrics First**

1. **Validate source metric exists** (see Prometheus Metrics Validation above)

2. **Add to `configs/recording-rules.yml`**:
```yaml
groups:
  - name: performance_recording_rules
    interval: 30s
    rules:
      # Document what metrics this uses
      - record: service:metric:aggregation
        expr: rate(validated_source_metric[5m])
```

3. **Reload Prometheus**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

4. **Verify recording rule works**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=service:metric:aggregation'" | \
  jq '.data.result'
```

### Metrics Validation (MANDATORY)

**Why Critical**:
- Metrics don't exist despite naming conventions
- Applications need explicit instrumentation
- Real incident (2025-10-13): n8n dashboard used `n8n_nodejs_eventloop_lag_p95_seconds` which doesn't exist. n8n only exposes P50, P90, P99.

**Validation Steps**:
1. Query Prometheus API for existence
2. Check labels and values
3. Test in Prometheus UI
4. Document source

**Example Validation**:
```bash
# List all n8n metrics
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep 'n8n_nodejs_eventloop_lag_p'

# Output shows:
# n8n_nodejs_eventloop_lag_p50_seconds  ✅
# n8n_nodejs_eventloop_lag_p90_seconds  ✅
# n8n_nodejs_eventloop_lag_p99_seconds  ✅
# (p95 does NOT exist!)

# Test query returns actual data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=n8n_nodejs_eventloop_lag_p99_seconds'" | \
  jq -r '.data.result[] | "P99: \(.value[1])s"'
```

**Documentation**: See `docs/METRICS-VALIDATION-2025-10-12.md`

## Troubleshooting

### Changes Not Appearing

```bash
# Verify NFS mount is active
mount | grep grafana

# Check if file exists on NAS
ssh -p 1111 jclee@192.168.50.215 "ls -lh /volume1/grafana/configs/prometheus.yml"

# Force Grafana dashboard re-scan (if needed)
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
```

### Prometheus Target DOWN

```bash
# Check targets
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up")'

# Common causes:
# 1. Wrong container name (use full name)
# 2. Network mismatch
# 3. Service not ready
```

### Logs Not in Loki

```bash
# Check Promtail
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs promtail-container --tail 50"

# Common causes:
# 1. Logs >3 days old (Loki retention)
# 2. Synology `db` driver (unsupported)
# 3. Missing volume mount
```

### Dashboard "No Data"

```bash
# Verify metric exists
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep metric_name

# Test query returns data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=metric_name'" | \
  jq '.data.result'

# Common causes:
# 1. Metric doesn't exist (NOT VALIDATED) ← Most common!
# 2. Wrong datasource UID
# 3. Query syntax error
# 4. Wrong percentile (e.g., p95 vs p99)
```

### Docker Context Issues (Local Containers)

**Problem**: Local containers (promtail-local) fail to start with "Bind mount failed: path does not exist"

**Root Cause**: `DOCKER_CONTEXT` environment variable set to `synology`, causing Docker commands to execute on remote NAS instead of locally

```bash
# Check current context
docker context ls
env | grep DOCKER

# Fix: Explicitly set context for local containers
DOCKER_CONTEXT=local docker compose -f docker-compose.local.yml up -d

# Or unset environment variable
unset DOCKER_CONTEXT
docker context use local
docker compose -f docker-compose.local.yml up -d
```

**Prevention**: Always check Docker context when running local vs remote containers
- Synology containers: Use `synology` context (default via DOCKER_CONTEXT env var)
- Local containers: Explicitly set `DOCKER_CONTEXT=local` or unset variable

### Verify System Health

```bash
# Check all services healthy
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps --filter health=healthy"

# Check Prometheus health
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/-/healthy"

# Check Grafana health
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container wget -qO- http://localhost:3000/api/health" | \
  jq '.database'

# Run log collection health check
./scripts/check-log-collection.sh
```

## Important Notes

1. **Remote Deployment**: Stack on Synology NAS, NOT local
2. **NFS Mount**: `/home/jclee/app/grafana` is NFS-mounted from Synology (instant sync)
3. **Container Names**: Use full names (e.g., `prometheus-container:9090`)
4. **Metrics Validation**: MANDATORY before dashboard/recording rule creation
5. **Grafana Auto-Provisioning**: Don't create manually in UI (overwritten every 10s)
6. **Synology `db` Driver**: Blocks log collection → use metrics instead
7. **Loki Retention**: 3 days
8. **Prometheus Retention**: 30 days
9. **Dashboard Refresh**: Auto-provision every 10 seconds
10. **Volume Permissions**: Run `create-volume-structure.sh` on first deployment
11. **Percentile Metrics**: Always verify which percentiles exist (P50/P90/P95/P99)
12. **REDS/USE Methodologies**: Apply to all dashboards for consistency

## Access Points

- **Grafana**: https://grafana.jclee.me (admin / bingogo1)
- **Prometheus**: https://prometheus.jclee.me
- **Loki**: https://loki.jclee.me
- **AlertManager**: https://alertmanager.jclee.me
- **SSH**: `ssh -p 1111 jclee@192.168.50.215`

## Automation Scripts

This project includes several automation scripts for operational tasks:

### Health Check Script
```bash
# Check all services health
./scripts/health-check.sh

# Features:
# - Validates 4 core services (Grafana, Prometheus, Loki, AlertManager)
# - Checks Prometheus targets status
# - Validates docker-compose syntax
# - Returns proper exit codes (0=healthy, 1=unhealthy, 2=partial)
```

### Metrics Validation Script
```bash
# Validate all dashboards
./scripts/validate-metrics.sh

# Validate specific dashboard
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/my-dashboard.json

# List all available metrics
./scripts/validate-metrics.sh --list

# Features:
# - Extracts metrics from dashboard JSON files
# - Queries Prometheus to verify metrics exist
# - Detects "No Data" panels before deployment
# - Prevents incidents like 2025-10-13 P95 (metric didn't exist)
```

### Common Library
```bash
# All scripts source this library
source "$(dirname "$0")/lib/common.sh"

# Provides:
# - Colored logging: log_info, log_success, log_error, log_warning
# - Error handling: die, check_command
# - Service health checks: check_service_health
# - Docker operations: docker_exec, docker_logs
# - Prometheus queries: query_prometheus
# - Grafana API calls: grafana_api
```

## CI/CD Pipeline

### GitHub Actions Workflow
`.github/workflows/validate.yml` runs on every push/PR:

**Jobs**:
1. `validate-yaml` - YAML syntax + duplicate keys check
2. `validate-json` - Dashboard JSON validation
3. `validate-docker-compose` - Docker Compose config verification
4. `validate-scripts` - Shellcheck + executable permissions
5. `security-scan` - Hardcoded secrets detection
6. `documentation-check` - Required files presence

**Triggers**: Push to main/master/develop, PRs to main/master, manual dispatch

## Environment Variables

All secrets and configuration use environment variables:

**Files**:
- `.env` - Actual values (gitignored, NEVER commit)
- `.env.example` - Template with placeholders (committed to git)

**Key Variables**:
```bash
# Service versions (pinned for reproducibility)
GRAFANA_VERSION=10.2.3
PROMETHEUS_VERSION=v2.48.1
LOKI_VERSION=2.9.3
PROMTAIL_VERSION=2.9.3
ALERTMANAGER_VERSION=v0.26.0
NODE_EXPORTER_VERSION=v1.7.0
CADVISOR_VERSION=v0.47.2

# Security
GRAFANA_ADMIN_PASSWORD=<secret>

# Domains
GRAFANA_DOMAIN=grafana.jclee.me
PROMETHEUS_DOMAIN=prometheus.jclee.me
LOKI_DOMAIN=loki.jclee.me
ALERTMANAGER_DOMAIN=alertmanager.jclee.me

# Paths (Synology NAS)
GRAFANA_DATA_PATH=/volume1/grafana/data/grafana
PROMETHEUS_DATA_PATH=/volume1/grafana/data/prometheus
LOKI_DATA_PATH=/volume1/grafana/data/loki
ALERTMANAGER_DATA_PATH=/volume1/grafana/data/alertmanager
CONFIGS_PATH=/volume1/grafana/configs

# Monitoring settings
PROMETHEUS_RETENTION_TIME=30d
MONITORING_NETWORK=grafana-monitoring-net
```

## Version History

### 2025-10-14: Security & Testing Improvements
- **Security**: Environment variable migration, no hardcoded passwords (3.0→4.2/5)
- **Testing**: Automated health checks, metrics validation (1.0→3.5/5)
- **Code Quality**: Common library for DRY principle (3.8→4.3/5)
- **Dependency Management**: Version pinning for reproducibility (3.2→4.0/5)
- **Overall Score**: B+ (3.6/5) → A- (4.0/5)

See `docs/IMPROVEMENTS-2025-10-14.md` for full details.

### 2025-10-13: Metrics Validation Incident
- **Incident**: Dashboard used `n8n_nodejs_eventloop_lag_p95_seconds` which doesn't exist
- **Root Cause**: n8n only exposes P50, P90, P99 percentiles
- **Fix**: Mandatory metrics validation before dashboard/recording rule creation
- **Prevention**: Created `validate-metrics.sh` script

## Key Documentation

- `docs/IMPROVEMENTS-2025-10-14.md` - Recent security & testing improvements
- `docs/STABILIZATION-REPORT-2025-10-14.md` - System stabilization after improvements
- `docs/GRAFANA-BEST-PRACTICES-2025.md` - Dashboard design, USE/REDS methodologies
- `docs/METRICS-VALIDATION-2025-10-12.md` - Metrics validation methodology
- `docs/N8N-LOG-INVESTIGATION-2025-10-12.md` - Synology logging constraints
- `docs/DASHBOARD-MODERNIZATION-2025-10-12.md` - Dashboard modernization standards
- `docs/DEPRECATED-REALTIME_SYNC.md` - Deprecated sync architecture (replaced by NFS)

## Summary

**Architecture**: NFS-mounted from Synology NAS (instant sync, no sync service)
**Critical Operations**: Validate metrics → Edit configs → Reload services
**Methodologies**: REDS (applications), USE (infrastructure)
**Validation**: `./scripts/validate-metrics.sh` (prevents "No Data" panels)
**Documentation**: See `resume/` for comprehensive guides (2400+ lines total)

For global infrastructure integration and Constitutional Framework, see `~/.claude/CLAUDE.md`.


