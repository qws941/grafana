# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🚨 CRITICAL RULES

### ⚠️ P0 - Mandatory Validation

1. **ALWAYS validate metrics exist** before creating dashboards/recording rules
   - **2025-10-13 Incident**: Used `n8n_nodejs_eventloop_lag_p95_seconds` which doesn't exist
   - **Reality**: n8n only exposes P50, P90, P99 (NOT P95)
   - **Command**: `./scripts/validate-metrics.sh --list | grep <pattern>`
   - **Documentation**: `/docs/METRICS-VALIDATION-2025-10-12.md`

2. **Use Docker context**, not manual SSH
   - **Correct**: `docker context use synology && docker exec ...`
   - **Wrong**: `ssh -p 1111 jclee@192.168.50.215 "sudo docker ..."`
   - **Why**: Cleaner, automatic SSH handling, consistent commands
   - **Guide**: `/docs/DOCKER-CONTEXT-QUICK-REFERENCE.md`

3. **Never create dashboards in Grafana UI**
   - **Auto-provisioned**: Every 10 seconds from `configs/provisioning/dashboards/*.json`
   - **Manual changes**: Will be overwritten
   - **Workflow**: Edit JSON → Save → Wait max 10s

4. **Use full container names** in configurations
   - **Correct**: `prometheus-container:9090`
   - **Wrong**: `prometheus:9090`

5. **Follow dashboard methodologies**
   - **REDS** for applications (Rate, Errors, Duration, Saturation)
   - **USE** for infrastructure (Utilization, Saturation, Errors)
   - **Guide**: `/docs/GRAFANA-BEST-PRACTICES-2025.md`

---

## 🎯 PROJECT CONTEXT

**Deployment Model**: Remote on Synology NAS (192.168.50.215:1111)
**Local Directory**: NFS-mounted from `192.168.50.215:/volume1/grafana`
**Sync**: Instant via NFS v3 (no sync service needed)
**Docker**: All services run on NAS, use `synology` context

### ⚠️ CRITICAL: NFS Mount Architecture

**This directory is NFS-mounted, NOT sync service**:
- **Mount Source**: `192.168.50.215:/volume1/grafana`
- **Mount Point**: `/home/jclee/app/grafana`
- **Mount Type**: NFS v3 (rw, noatime, hard)
- **Sync**: **INSTANT** (filesystem-level, zero delay)
- **grafana-sync.service**: DISABLED (replaced by NFS on 2025-10-18)
- **Verification**: `mount | grep grafana` should show NFS mount

**Why NFS**:
- Eliminates sync latency (file changes are instant on NAS)
- No sync daemon needed (filesystem handles it)
- Bidirectional by default (local ↔ NAS)
- More reliable than rsync-based sync

**Note**: README.md may show old grafana-sync.service architecture in diagrams. This is outdated. The current architecture uses NFS mount as documented here. See `/docs/archive/deprecated-scripts/README.md` for migration history.

### Key Architecture Points

- **NFS Mount**: `/home/jclee/app/grafana` ↔ `/volume1/grafana` (instant sync)
- **Networks**: `traefik-public` (external) + `grafana-monitoring-net` (internal)
- **Services**: Grafana, Prometheus, Loki, AlertManager, Promtail, node-exporter, cadvisor
- **Access**: https://grafana.jclee.me (all services via CloudFlare SSL)

### Configuration Files

```
configs/
├── prometheus.yml          # Scrape targets (12+), organized by context
├── alert-rules.yml         # 20+ alert rules (4 groups)
├── recording-rules.yml     # 32 rules (7 groups) - validated metrics only
├── loki-config.yml         # 3-day retention
├── promtail-config.yml     # Docker service discovery
└── provisioning/
    ├── datasources/        # Prometheus, Loki, AlertManager
    └── dashboards/         # Auto-provisioned every 10s
        ├── applications/   # n8n, ai-agents (REDS methodology)
        ├── core-monitoring/# Stack health, targets (USE methodology)
        └── infrastructure/ # System, containers, Traefik (USE methodology)
```

---

## ⚡️ QUICK COMMANDS

### First-Time Setup

```bash
# Create Docker context (one-time only)
docker context create synology \
  --docker "host=ssh://jclee@192.168.50.215:1111"

# Use synology context (per session)
docker context use synology

# Verify active context
docker context show  # Should output: synology

# List all contexts
docker context ls
```

### Daily Operations

```bash
# Real-time monitoring dashboard
./scripts/monitoring-status.sh

# Historical trends & analysis
./scripts/monitoring-trends.sh

# Validate metrics (MANDATORY before dashboard creation)
./scripts/validate-metrics.sh --list | grep <pattern>

# Health check
./scripts/health-check.sh

# NFS mount status
mount | grep grafana
```

### Service Management

```bash
# Switch to remote context (one-time per session)
docker context use synology

# Reload Prometheus (hot reload, no downtime)
docker exec prometheus-container \
  wget --post-data='' -qO- http://localhost:9090/-/reload

# Restart Grafana
docker restart grafana-container

# View logs
docker logs -f grafana-container

# Container health
docker inspect grafana-container | jq '.[0].State.Health'
```

### Metrics Validation Workflow

```bash
# List all available metrics
docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values' | \
  jq -r '.data[]' | grep <pattern>

# Test query returns data (not just metric exists)
docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=<metric_name>' | \
  jq '.data.result'
```

---

## 📚 DOCUMENTATION MAP

All detailed documentation is in `/resume/` and `/docs/` directories. CLAUDE.md is a **quick reference**, not a manual.

### Primary Documentation

| Document | Lines | Content |
|----------|-------|---------|
| `/resume/architecture.md` | 610 | System architecture, data flows, network topology |
| `/resume/api.md` | 849 | Complete API reference for all services |
| `/resume/deployment.md` | 774 | Step-by-step deployment procedures |
| `/resume/troubleshooting.md` | 958 | Comprehensive troubleshooting guide |
| `/resume/README.md` | 532 | Documentation index and overview |

### Key Guides

- **NFS Architecture**: `/docs/DEPRECATED-REALTIME_SYNC.md` (explains migration)
- **Deprecated Scripts**: `/docs/archive/deprecated-scripts/README.md` (sync service history)
- **Dashboard Standards**: `/docs/GRAFANA-BEST-PRACTICES-2025.md`
- **Metrics Validation**: `/docs/METRICS-VALIDATION-2025-10-12.md`
- **Docker Context**: `/docs/DOCKER-CONTEXT-QUICK-REFERENCE.md`
- **Alert System**: `/docs/ALERT-SYSTEM-SETUP-GUIDE.md`
- **Operational Runbook**: `/docs/OPERATIONAL-RUNBOOK.md`
- **Legacy Cleanup**: `/docs/LEGACY-CLEANUP-2025-10-21.md` (latest cleanup summary)

### Recent Updates

- **2025-10-21**: Legacy cleanup (archived sync scripts), documentation updates
- **2025-10-20**: Context-based target organization, monitoring scripts
- **2025-10-18**: NFS mount migration (grafana-sync.service deprecated)
- **2025-10-16**: n8n recording rules updated (P99, not P95)
- **2025-10-14**: Security improvements, environment variables
- **2025-10-13**: Metrics validation incident & script creation

---

## 🔍 COMMON PROMQL PATTERNS

### Application Metrics (REDS Methodology)

```promql
# RATE: Workflow start rate (workflows/minute)
rate(n8n_workflow_started_total[5m]) * 60

# RATE: Active workflow count
n8n_active_workflow_count

# ERRORS: Workflow failure rate
rate(n8n_workflow_failed_total[5m])

# DURATION: Event loop lag ⚠️ Use P99, NOT P95 (P95 doesn't exist!)
n8n_nodejs_eventloop_lag_p99_seconds
n8n_nodejs_eventloop_lag_p90_seconds
n8n_nodejs_eventloop_lag_p50_seconds

# SATURATION: Queue enqueue rate
rate(n8n_queue_job_enqueued_total[5m]) * 60

# SATURATION: Cache miss rate percentage
rate(n8n_cache_misses_total[5m]) /
  (rate(n8n_cache_hits_total[5m]) + rate(n8n_cache_misses_total[5m])) * 100
```

### Infrastructure Metrics (USE Methodology)

```promql
# UTILIZATION: CPU per container (%)
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# UTILIZATION: Memory per container (bytes)
container_memory_usage_bytes{name!=""}

# UTILIZATION: Network receive rate (bytes/sec)
rate(container_network_receive_bytes_total{name!=""}[5m])

# SATURATION: Memory limit percentage
(container_memory_usage_bytes{name!=""} /
  container_spec_memory_limit_bytes{name!=""}) * 100

# UTILIZATION: System CPU by mode
rate(node_cpu_seconds_total[5m]) * 100

# UTILIZATION: Available memory
node_memory_MemAvailable_bytes

# SATURATION: System load average
node_load1
node_load5
node_load15
```

### Context-Based Target Filtering

Prometheus targets are organized by context (added 2025-10-20):

```promql
# All production targets
up{context=~"monitoring-stack|infrastructure|application"}

# All development targets
up{context=~"dev-.*"}

# Specific context
up{context="monitoring-stack"}  # Self-monitoring infrastructure
up{context="infrastructure"}    # Production system metrics
up{context="application"}       # Production applications
```

### ⚠️ Validation Best Practices

Always verify metrics exist before using:
```bash
# Check metric exists
./scripts/validate-metrics.sh --list | grep metric_name

# Test query returns data
docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=metric_name{labels}'
```

---

## 🚀 DEVELOPMENT WORKFLOWS

### Adding Dashboard

1. **Validate metrics** → `./scripts/validate-metrics.sh --list`
2. **Create JSON** → Follow REDS/USE methodology (see `/docs/GRAFANA-BEST-PRACTICES-2025.md`)
3. **Save** → `configs/provisioning/dashboards/<category>/<name>.json`
4. **Wait** → Max 10s for auto-provision
5. **Verify** → Check Grafana UI at https://grafana.jclee.me

**Dashboard Categories**:
- `applications/` - REDS methodology (n8n, ai-agents, hycu-automation)
- `core-monitoring/` - USE methodology (stack health, targets)
- `infrastructure/` - USE methodology (system, containers, Traefik)

### Adding Prometheus Target

1. **Verify endpoint** → `curl http://service:port/metrics`
2. **Edit config** → `configs/prometheus.yml` (add to appropriate context group)
3. **Reload** → `docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload`
4. **Check** → https://prometheus.jclee.me/targets

**Target Contexts** (organize by purpose):
- `monitoring-stack` - Self-monitoring (Prometheus, Grafana, Loki, AlertManager)
- `infrastructure` - System metrics (node-exporter, cadvisor)
- `application` - Production apps (n8n, pushgateway)
- `dev-infrastructure` - Development system metrics
- `dev-application` - Development apps

### Adding Alert Rule

1. **Edit** → `configs/alert-rules.yml`
2. **Reload** → Same as Prometheus target
3. **Verify** → https://prometheus.jclee.me/alerts

### Adding Recording Rule

1. **Validate source metrics** → `./scripts/validate-metrics.sh --list`
2. **Edit** → `configs/recording-rules.yml`
3. **Reload** → Same as Prometheus target
4. **Verify** → Query the recorded metric in Prometheus

### Script Requirements

All scripts require these dependencies:

**Required**:
- `bash` (v4.0+)
- `jq` (JSON processing)
- `docker` (with synology context configured)
- `curl` or `wget`

**Optional (for specific scripts)**:
- `monitoring-status.sh`: `bc` (calculations)
- `monitoring-trends.sh`: `bc`, `date`, `awk`
- `validate-metrics.sh`: `jq`, Python 3 (JSON parsing)

**Verify dependencies**:
```bash
# Check required tools
command -v jq docker curl bc

# Install missing tools (Rocky Linux)
sudo dnf install -y jq bc

# Verify Docker context
docker context show  # Should output: synology
```

**Common script errors**:
- `jq: command not found` → Install jq: `sudo dnf install jq`
- `docker: context not found` → Create context: See **First-Time Setup** section
- `bc: command not found` → Install bc: `sudo dnf install bc`

---

## 🔒 PLATFORM CONSTRAINTS

### Synology Limitations

- **Logging Driver**: `db` driver system-wide (Promtail can't read)
  - **Solution**: Use Prometheus metrics instead
  - **See**: `/docs/N8N-LOG-INVESTIGATION-2025-10-12.md`

- **Volume Permissions**: Critical for first deployment
  - Grafana: `472:472`
  - Prometheus: `65534:65534`
  - Loki: `10001:10001`
  - **Script**: `scripts/create-volume-structure.sh`

### Data Retention

- **Prometheus**: 30 days (configurable via `PROMETHEUS_RETENTION_TIME`)
- **Loki**: 3 days (hardcoded in `configs/loki-config.yml`)
- **AlertManager**: No limit (stateless)

### Hot Reload Support

- **Prometheus**: ✅ Yes (`--web.enable-lifecycle`)
  - Reloads: `prometheus.yml`, `alert-rules.yml`, `recording-rules.yml`
- **Grafana**: ❌ No (restart required for config changes)
  - **Exception**: Dashboards auto-provision every 10s (no restart needed)
- **Loki**: ❌ No (restart required)

---

## 🔧 QUICK FIXES

### Emergency Troubleshooting

**Dashboard shows "No Data"**:
```bash
# 1. Verify metric exists
./scripts/validate-metrics.sh --list | grep <metric>

# 2. Check Prometheus target is UP
docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job == "service-name")'

# 3. Test query in Prometheus UI
# https://prometheus.jclee.me/graph
```

**NFS mount is stale**:
```bash
# Remount NFS
sudo umount /home/jclee/app/grafana
sudo mount -a

# Verify mount
mount | grep grafana
# Should show: 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs
```

**Prometheus target DOWN**:
```bash
# Check container is running
docker ps | grep container-name

# Check container logs
docker logs container-name --tail 50

# Test connectivity from Prometheus
docker exec prometheus-container wget -O- http://target:port/metrics
```

**Configuration not reloading**:
```bash
# Verify Docker context is set
docker context show  # Should be: synology

# Force reload Prometheus
docker exec prometheus-container wget --post-data='' -qO- \
  http://localhost:9090/-/reload

# Restart Grafana (config changes)
docker restart grafana-container

# Check logs for errors
docker logs grafana-container --tail 50
```

**Logs not in Loki**:
```bash
# Check Promtail
docker logs promtail-container --tail 50

# Common causes:
# - Logs > 3 days old (Loki retention)
# - Synology 'db' driver (use metrics instead)
# - Container not on grafana-monitoring-net
```

---

## 🔗 QUICK LINKS

- **Grafana**: https://grafana.jclee.me
- **Prometheus**: https://prometheus.jclee.me
- **Loki**: https://loki.jclee.me
- **AlertManager**: https://alertmanager.jclee.me
- **SSH**: `ssh -p 1111 jclee@192.168.50.215`

---

**Last Updated**: 2025-10-21
**Template Version**: v2.1 (improved from v2.0)
**Maintained By**: Human + Claude Code
