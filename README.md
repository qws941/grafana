# Grafana Monitoring Stack

Complete observability stack deployed **remotely on Synology NAS** (192.168.50.215:1111), providing full monitoring for infrastructure, applications, and services. The stack runs entirely on the NAS, while local development uses real-time synchronization.

**Critical Architecture**: This stack is **NOT local**. All services run on Synology NAS with automatic bi-directional sync between local development (192.168.50.100) and remote NAS.

## 🏗️ Architecture

```
Local Machine (Development)          Synology NAS (192.168.50.215:1111)
───────────────────────────          ──────────────────────────────────
/home/jclee/app/grafana/             /volume1/grafana/
(NFS Mount Point)         ◄═══════► (NFS Share)
├── configs/                          ├── configs/
├── scripts/                          ├── scripts/
├── docker-compose.yml                ├── docker-compose.yml
└── docs/                             └── data/
                                          ├── grafana/
NFS Mount:                                ├── prometheus/
- Source: 192.168.50.215:/volume1/grafana ├── loki/
- Type: NFS v3                            └── alertmanager/
- Sync: INSTANT (filesystem-level)
                                      Docker Services:
                                      - grafana-container      (3000)
                                      - prometheus-container   (9090)
                                      - loki-container         (3100)
                                      - alertmanager-container (9093)
                                      - promtail-container
                                      - node-exporter-container
                                      - cadvisor-container
```

## 🚀 Quick Start

### Prerequisites

- **Synology NAS**: DSM 7.0+ with SSH access (port 1111)
- **Local Machine**: Rocky Linux 9 (192.168.50.100)
- **Docker**: Installed on Synology NAS
- **SSH Key**: Passwordless SSH to NAS configured
- **NFS Mount**: `/home/jclee/app/grafana` mounted from `192.168.50.215:/volume1/grafana`
- **Docker Context**: `synology` context configured

> **Quick Reference**: See [CLAUDE.md](CLAUDE.md) for emergency fixes, PromQL patterns, and Docker context setup

### 1. Verify NFS Mount

```bash
# Check NFS mount (instant sync via filesystem)
mount | grep grafana

# Should show:
# 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs

# Setup Docker context (one-time)
docker context create synology --docker "host=ssh://jclee@192.168.50.215:1111"
docker context use synology
```

### 2. Environment Variables

Copy and configure environment variables:

```bash
# Create .env from example
cp .env.example .env

# Edit configuration
vim .env
```

**Required variables**:
```bash
# Service versions (pinned for reproducibility)
GRAFANA_VERSION=10.2.3
PROMETHEUS_VERSION=v2.48.1
LOKI_VERSION=2.9.3

# Security
GRAFANA_ADMIN_PASSWORD=<your-secure-password>

# Domains
GRAFANA_DOMAIN=grafana.jclee.me
PROMETHEUS_DOMAIN=prometheus.jclee.me
LOKI_DOMAIN=loki.jclee.me
ALERTMANAGER_DOMAIN=alertmanager.jclee.me

# Storage paths (Synology NAS)
GRAFANA_DATA_PATH=/volume1/grafana/data/grafana
PROMETHEUS_DATA_PATH=/volume1/grafana/data/prometheus
LOKI_DATA_PATH=/volume1/grafana/data/loki
```

### 3. Deploy Stack (on Synology NAS)

```bash
# SSH to Synology NAS
ssh -p 1111 jclee@192.168.50.215

# Navigate to project directory
cd /volume1/grafana

# Deploy stack
sudo docker-compose up -d

# Verify services
sudo docker ps | grep -E 'grafana|prometheus|loki'
```

## 📊 Services

| Service | Port | Domain | Description |
|---------|------|--------|-------------|
| **Grafana** | 3000 | https://grafana.jclee.me | Main dashboard and visualization |
| **Prometheus** | 9090 | https://prometheus.jclee.me | Metrics collection and storage |
| **Loki** | 3100 | https://loki.jclee.me | Log aggregation (3-day retention) |
| **AlertManager** | 9093 | https://alertmanager.jclee.me | Alert routing and management |
| **Promtail** | - | - | Log forwarder (Docker logs → Loki) |
| **Node Exporter** | 9100 | - | System metrics exporter |
| **cAdvisor** | 8080 | - | Container metrics exporter |

**Access**:
- All services accessible via HTTPS with CloudFlare SSL
- Credentials: admin / (GRAFANA_ADMIN_PASSWORD from .env)

## 📁 Directory Structure

```
grafana/
├── README.md                    # This file
├── CLAUDE.md                    # Project-specific guidance
├── .env.example                 # Environment variables template
├── .env.credentials.example     # API credentials template
├── docker-compose.yml           # Service definitions
├── configs/                     # Configuration files (auto-synced)
│   ├── prometheus.yml           # Prometheus scrape config (12+ targets)
│   ├── alert-rules.yml          # Alert rules (20+ rules)
│   ├── recording-rules.yml      # Recording rules (32 rules)
│   ├── loki-config.yml          # Loki configuration
│   ├── promtail-config.yml      # Promtail log collection
│   └── provisioning/            # Grafana auto-provisioning
│       ├── datasources/         # Datasource configs
│       └── dashboards/          # Dashboard JSON files (5 dashboards)
├── scripts/                     # Operational scripts
│   ├── health-check.sh          # Health verification
│   ├── validate-metrics.sh      # Metrics validation
│   ├── realtime-sync.sh         # Manual sync trigger
│   └── lib/                     # Common libraries
│       └── common.sh            # Shared functions
├── resume/                      # Architecture documentation
│   ├── README.md                # Documentation index
│   ├── architecture.md          # System architecture (700+ lines)
│   ├── api.md                   # API documentation (600+ lines)
│   ├── deployment.md            # Deployment guide (500+ lines)
│   └── troubleshooting.md       # Troubleshooting guide (600+ lines)
├── demo/                        # Examples and visual materials
│   ├── README.md                # Demo guide (577 lines)
│   ├── screenshots/             # Visual documentation
│   ├── videos/                  # Walkthrough videos
│   └── examples/                # Configuration examples
│       ├── sample-dashboard.json
│       ├── sample-alert-rule.yml
│       ├── sample-recording-rule.yml
│       └── sample-promtail-config.yml
├── docs/                        # Additional documentation
└── .github/                     # CI/CD workflows
    └── workflows/
        └── validate.yml         # Validation workflow (7 jobs)
```

## 📈 Dashboards

### Provisioned Dashboards (5 Core Dashboards)

| # | Dashboard | UID | Description | Methodology |
|---|-----------|-----|-------------|-------------|
| 1 | **Monitoring Stack Health** | `monitoring-stack-health` | Self-monitoring stack status | USE |
| 2 | **System Metrics** | `system-metrics` | Infrastructure monitoring | USE |
| 3 | **Container Performance** | `container-performance` | Docker metrics | USE |
| 4 | **n8n Workflow Automation** | `n8n-workflow-automation-reds` | Application monitoring (15 panels) | REDS |
| 5 | **Log Analysis** | `log-analysis` | Log aggregation and analysis | - |

**Access**: https://grafana.jclee.me

**Features**:
- ✅ Auto-provisioning (10-second refresh)
- ✅ Validated metrics (no "No Data" panels)
- ✅ REDS/USE methodologies
- ✅ 40+ panels total, 100% operational

### Methodologies

**REDS** (Application Monitoring):
- **Rate**: Throughput (requests/min, workflows/min)
- **Errors**: Error rate and count
- **Duration**: Response time percentiles (P50, P90, P99)
- **Saturation**: Resource utilization (connections, handles)

**USE** (Infrastructure Monitoring):
- **Utilization**: CPU %, memory %, disk %
- **Saturation**: Load average, queue depth
- **Errors**: Error rates and counts

## 🔧 Key Features

### Instant Configuration Sync via NFS

- **Instant**: Changes reflected immediately via NFS mount (no delay)
- **Bidirectional**: Local ↔ NAS (filesystem-level sync)
- **No daemon**: Standard Linux NFS mount handles synchronization
- **Reliable**: Kernel-level filesystem operation

**Standard workflow**:
```bash
# 1. Edit configs locally (instantly synced via NFS)
vim configs/prometheus.yml

# 2. Changes are IMMEDIATE on NAS (no waiting)

# 3. Reload remote service
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

### Metrics Validation (MANDATORY)

**Critical**: Always validate metrics exist before deploying dashboards or recording rules.

```bash
# Use validation script
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/my-dashboard.json

# Or query Prometheus directly
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep metric_name
```

**Historical Incident (2025-10-13)**: Dashboard used `n8n_nodejs_eventloop_lag_p95_seconds` which doesn't exist. n8n only exposes P50, P90, P99. This caused "No Data" panels. See `docs/METRICS-VALIDATION-2025-10-12.md`.

### Automated Validation

GitHub Actions workflow validates on every push:
- YAML syntax (yamllint)
- JSON structure (dashboards)
- Docker Compose config
- Shell scripts (shellcheck)
- Security scan (secrets detection)
- Documentation completeness
- Metrics configuration

## 🛠️ Configuration Management

### Prometheus Scrape Targets

**Core services**: prometheus, grafana, loki, alertmanager
**Exporters**: node-exporter, cadvisor
**Applications**: n8n (workflow automation)
**Local exporters**: node-exporter (192.168.50.100:9101), cadvisor (192.168.50.100:8081)

**Hot reload support**:
- Prometheus: ✅ Yes (`--web.enable-lifecycle`)
- Grafana: ❌ No (restart required, but dashboards auto-provision every 10s)
- Loki: ❌ No (restart required)

### Recording Rules

7 groups with 32 rules across:
- Performance metrics (request rate, error rate, response time)
- Container metrics (CPU, memory, network)
- Application metrics (n8n workflows, cache, queue)

**Updated 2025-10-16**: All n8n rules use validated metrics only (P50, P90, P99, NOT P95)

### Alert Rules

20+ rules across 4 groups:
- Service health (UP/DOWN)
- Performance (error rate, latency)
- Resources (memory, CPU)
- Business metrics (workflow failures)

**Integration**: AlertManager → n8n webhook → Slack/Email notifications

## 🔐 Security

- **No hardcoded secrets**: All credentials in .env (gitignored)
- **Version pinning**: Reproducible deployments
- **Network isolation**: Internal (grafana-monitoring-net) + External (traefik-public)
- **SSL termination**: CloudFlare + Traefik
- **Service permissions**: Proper UID/GID for each service
- **SSH key authentication**: Passwordless SSH to NAS

## 📝 Common Tasks

### Check System Health

```bash
# Run health check script
./scripts/health-check.sh

# Expected output:
# ✅ Grafana: OK
# ✅ Prometheus: OK
# ✅ Loki: OK
# ✅ AlertManager: OK
```

### Add Prometheus Scrape Target

```bash
# 1. Edit prometheus.yml
vim configs/prometheus.yml

# 2. Add job configuration
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['service-container:port']

# 3. Wait 1-2s for sync, reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# 4. Verify: https://prometheus.jclee.me/targets
```

### Create Grafana Dashboard

```bash
# 1. VALIDATE METRICS FIRST (CRITICAL)
./scripts/validate-metrics.sh --list | grep my_metric

# 2. Create dashboard JSON following REDS/USE methodology
# See demo/examples/sample-dashboard.json for template

# 3. Save to provisioning directory
cp my-dashboard.json configs/provisioning/dashboards/

# 4. Auto-synced + loaded within 11-12 seconds

# 5. Verify: https://grafana.jclee.me/dashboards
```

### View Logs

```bash
# Via Loki in Grafana Explore
https://grafana.jclee.me/explore
Query: {job="my-service"} |= "error"

# Via Docker logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f my-service-container"
```

## 🧪 Testing & Validation

### Pre-deployment Checks

```bash
# Validate YAML files
yamllint configs/

# Validate JSON dashboards
./scripts/validate-metrics.sh

# Validate Docker Compose
docker-compose config

# Run ShellCheck
shellcheck scripts/*.sh
```

### CI/CD Pipeline

GitHub Actions automatically validates:
- Configuration syntax
- Metrics existence
- Security (no hardcoded secrets)
- Documentation completeness

Runs on: Push to main/master/develop, Pull requests

## 📞 Troubleshooting

### NFS Mount Issues

```bash
# Check NFS mount status
mount | grep grafana

# Test write access
touch /home/jclee/app/grafana/test.txt && \
  rm /home/jclee/app/grafana/test.txt

# Remount if stale
sudo umount /home/jclee/app/grafana
sudo mount -a

# Verify mount
mount | grep grafana
# Should show: 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs
```

### Dashboard Shows "No Data"

```bash
# Validate metric exists (MOST COMMON ISSUE)
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/my-dashboard.json

# Test query in Prometheus
curl -s "https://prometheus.jclee.me/api/v1/query?query=my_metric" | jq '.data.result'
```

### Prometheus Target DOWN

```bash
# Check targets
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health != "up")'

# Common causes:
# 1. Wrong container name (use full name: service-container)
# 2. Network mismatch
# 3. Service not ready
```

For complete troubleshooting guide, see [resume/troubleshooting.md](resume/troubleshooting.md).

## 📚 Documentation

- [Architecture](resume/architecture.md) - System architecture, deployment diagram, data flows (700+ lines)
- [API Documentation](resume/api.md) - Complete API reference for all services (600+ lines)
- [Deployment Guide](resume/deployment.md) - Step-by-step deployment procedures (500+ lines)
- [Troubleshooting](resume/troubleshooting.md) - Comprehensive troubleshooting guide (600+ lines)
- [Demo Guide](demo/README.md) - Examples, scenarios, and visual materials (577 lines)
- [Project Guidance](CLAUDE.md) - Project-specific guidance for Claude Code (483 lines, v2.1)
  - 🔍 Common PromQL patterns (REDS/USE queries)
  - 🔧 Quick troubleshooting fixes (emergency scenarios)
  - ⚡️ Docker context setup & NFS architecture
  - 🚀 Script dependencies & validation

## 🔄 Updates

### Version History

- **2025-10-21**: CLAUDE.md v2.1 enhancements (PromQL patterns, quick fixes, Docker context, script deps)
- **2025-10-17**: Constitutional Framework compliance (95%+), comprehensive documentation
- **2025-10-16**: n8n recording rules updated (validated metrics only)
- **2025-10-14**: Security improvements, environment variable migration, automated validation
- **2025-10-13**: Metrics validation incident (P95 doesn't exist), validation script created
- **2025-10-12**: Dashboard modernization, REDS/USE methodologies

## 📄 License

This project is for internal use. Modify as needed for your environment.

## 🤝 Contributing

1. Validate metrics before creating dashboards (`./scripts/validate-metrics.sh`)
2. Follow REDS (application) or USE (infrastructure) methodology
3. Test in development before deploying to production
4. Document changes in comments
5. Run validation suite before committing

## 🔗 Links

- **Grafana**: https://grafana.jclee.me
- **Prometheus**: https://prometheus.jclee.me
- **Loki**: https://loki.jclee.me
- **AlertManager**: https://alertmanager.jclee.me
- **n8n**: https://n8n.jclee.me

---

**Deployment**: Synology NAS (192.168.50.215:1111)
**Development**: Rocky Linux 9 (192.168.50.100)
**Sync**: Instant (NFS v3 mount, filesystem-level)
**Compliance**: Constitutional Framework v12.0 (100%)
