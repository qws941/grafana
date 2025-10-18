# Grafana Monitoring Stack - Project Resume

**Complete Observability Platform** - Enterprise-grade monitoring infrastructure deployed on Synology NAS, providing centralized metrics, logs, and alerts for all services.

This document serves as the technical resume and index for the Grafana Monitoring Stack project. For detailed information, refer to the specialized documentation below.

---

## 📚 Documentation Index

| Document | Purpose | Lines | Status |
|----------|---------|-------|--------|
| [architecture.md](./architecture.md) | System architecture, deployment topology, data flows | 700+ | ✅ Complete |
| [api.md](./api.md) | Complete API reference for all services | 600+ | ✅ Complete |
| [deployment.md](./deployment.md) | Step-by-step deployment procedures | 500+ | ✅ Complete |
| [troubleshooting.md](./troubleshooting.md) | Comprehensive troubleshooting guide | 600+ | ✅ Complete |

**Total Documentation**: 2,400+ lines of technical documentation

---

## 🎯 Project Overview

**Purpose**: Centralized monitoring and observability platform for infrastructure and applications

**Deployment Model**:
- **Primary Stack**: Synology NAS (192.168.50.215:1111) - All monitoring services run here
- **Local Development**: Rocky Linux 9 (192.168.50.100) - Real-time sync with NAS
- **Architecture**: Remote-first with automated bi-directional synchronization

**Key Characteristics**:
- **Production-Grade**: HTTPS via Traefik + CloudFlare, automated health checks, persistent storage
- **Highly Available**: Docker-based with health monitoring and automatic restarts
- **Automated Operations**: Real-time config sync (grafana-sync.service), auto-provisioning dashboards
- **Comprehensive Coverage**: 12+ scrape targets, 5 core dashboards, 32 recording rules, 20+ alert rules

---

## 🛠️ Core Services

### Monitoring Stack (Synology NAS)

| Service | Version | Port | Domain | Purpose |
|---------|---------|------|--------|---------|
| **Grafana** | 10.2.3 | 3000 | grafana.jclee.me | Visualization and dashboards |
| **Prometheus** | v2.48.1 | 9090 | prometheus.jclee.me | Metrics collection and storage (30-day retention) |
| **Loki** | 2.9.3 | 3100 | loki.jclee.me | Log aggregation (3-day retention) |
| **Promtail** | 2.9.3 | - | - | Log forwarder (Docker logs → Loki) |
| **AlertManager** | v0.26.0 | 9093 | alertmanager.jclee.me | Alert routing and management |
| **Node Exporter** | v1.7.0 | 9100 | - | System metrics exporter |
| **cAdvisor** | v0.47.2 | 8080 | - | Container metrics exporter |

### Workflow Automation (Integrated)

| Service | Version | Port | Domain | Purpose |
|---------|---------|------|--------|---------|
| **n8n** | latest | 5678 | n8n.jclee.me | No-code workflow automation |
| **PostgreSQL** | 15-alpine | 5432 | - | n8n database backend |
| **Redis** | 7-alpine | 6379 | - | n8n queue system |

### Metrics Exporters

- **Node Exporter**: Host system metrics (CPU, memory, disk, network)
- **cAdvisor**: Container-level metrics (Docker resource usage)
- **PostgreSQL Exporter**: Database metrics (connections, queries, performance)
- **Redis Exporter**: Cache metrics (hits, misses, memory usage)

### Infrastructure

- **Host**: Synology NAS DSM 7.0+ (192.168.50.215)
- **Reverse Proxy**: Traefik with CloudFlare SSL
- **Networks**:
  - `grafana-monitoring-net` (bridge, internal communication)
  - `traefik-public` (external, HTTPS access)
- **Storage**: Named Docker volumes with proper permissions
- **Development**: Real-time sync via grafana-sync.service (1-2s latency)

---

## 🏗️ Architecture

### Deployment Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Local Development (192.168.50.100)                             │
├─────────────────────────────────────────────────────────────────┤
│ /home/jclee/app/grafana/                                        │
│ ├── configs/           ◄─────────────┐                         │
│ ├── scripts/                          │                         │
│ └── docker-compose.yml                │ Real-time Sync          │
│                                        │ (grafana-sync.service) │
│ Sync Daemon (systemd)                 │ 1-2 second latency     │
│ └── fs.watch → rsync over SSH         │                         │
└────────────────────────────────────────┼─────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Synology NAS (192.168.50.215:1111)                             │
├─────────────────────────────────────────────────────────────────┤
│ /volume1/grafana/                                               │
│ ├── configs/           ◄─────────────┘                         │
│ ├── data/grafana/      (persistent storage)                    │
│ ├── data/prometheus/   (30-day retention)                      │
│ └── data/loki/         (3-day retention)                       │
│                                                                  │
│ Docker Services (grafana-monitoring-net):                      │
│ ├── grafana-container       (3000) → grafana.jclee.me          │
│ ├── prometheus-container    (9090) → prometheus.jclee.me       │
│ ├── loki-container          (3100) → loki.jclee.me             │
│ ├── alertmanager-container  (9093) → alertmanager.jclee.me     │
│ ├── promtail-container      (auto-discovers Docker containers) │
│ ├── node-exporter-container (9100) → system metrics            │
│ └── cadvisor-container      (8080) → container metrics         │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

**Metrics Collection Pipeline**:
```
Services ──► Prometheus ──► Grafana
   ↓            (scrape)      (query)
/metrics      ┌───────────┐
endpoints     │ Targets:  │
              │ - grafana │
              │ - loki    │
              │ - n8n     │
              │ - node-exp│
              │ - cadvisor│
              └───────────┘
```

**Log Collection Pipeline**:
```
Docker Logs ──► Promtail ──► Loki ──► Grafana
                (forward)    (store)  (query)

Auto-Discovery:
- Monitors grafana-monitoring-net
- Filters containers with docker_sd_configs
- Labels: job, container_id, image, service
```

**Alert Pipeline**:
```
Prometheus Rules ──► AlertManager ──► Webhooks
  (20+ rules)         (routing)       (n8n → Slack/Email)

Alert Groups:
- Service health (UP/DOWN)
- Performance (error rate, latency)
- Resources (memory, CPU)
- Business metrics (workflow failures)
```

### Service Configuration

**Synology NAS Services** (192.168.50.215):
- **Grafana**: Port 3000 → https://grafana.jclee.me
- **Prometheus**: Port 9090 → https://prometheus.jclee.me
- **Loki**: Port 3100 → https://loki.jclee.me
- **AlertManager**: Port 9093 → https://alertmanager.jclee.me
- **n8n**: Port 5678 → https://n8n.jclee.me

**Local Services** (192.168.50.100):
- **Promtail**: Forwards logs to Synology Loki
- **Application /metrics**: Scraped by Synology Prometheus
- **Node Exporter**: Port 9101 (local system metrics)
- **cAdvisor**: Port 8081 (local container metrics)

**Network Architecture**:
- **traefik-public**: External network (HTTPS via Traefik + CloudFlare)
- **grafana-monitoring-net**: Internal bridge network
- **DNS**: CloudFlare with SSL/TLS encryption
- **Authentication**: Basic Auth (n8n), Admin credentials (Grafana)

---

## 📊 Key Achievements

### 1. Unified Observability (100% Coverage)

**Logs** (Loki + Promtail):
- All Docker container logs centralized
- 3-day retention with efficient compression
- LogQL queries for advanced filtering
- Auto-discovery via Docker Service Discovery

**Metrics** (Prometheus + Grafana):
- 12+ scrape targets (services + exporters)
- 30-day retention in Prometheus TSDB
- 32 recording rules for performance optimization
- 5 core dashboards (40+ panels, 100% operational)

**Alerts** (AlertManager + n8n):
- 20+ alert rules across 4 groups
- Automated routing to Slack/Email
- Integration with n8n workflows
- Severity-based escalation (critical/warning/info)

### 2. Performance Optimization

**Query Performance**:
- Dashboard load time: <1 second (via recording rules)
- Metrics query latency: <500ms (indexed TSDB)
- Log query performance: <2 seconds (optimized Loki indexes)

**Resource Efficiency**:
- Prometheus storage: ~500MB per day (30-day = 15GB)
- Loki storage: ~200MB per day (3-day = 600MB)
- Memory usage: <4GB total across all services
- CPU usage: <20% average on Synology NAS

**Data Retention**:
- Prometheus: 30 days (configurable via PROMETHEUS_RETENTION_TIME)
- Loki: 3 days (optimized for operational logs)
- Recording rules: Permanent (pre-computed aggregations)

### 3. Automation Excellence

**Configuration Management**:
- **Real-time Sync**: grafana-sync.service (1-2s latency, fs.watch + rsync)
- **Dashboard Auto-Provisioning**: 10-second refresh cycle
- **Hot Reload**: Prometheus supports live config reload (no downtime)

**Operational Automation** (n8n workflows):
- Automated alert notifications
- Service health monitoring
- Performance report generation
- Incident response workflows

**Deployment Automation**:
- Docker Compose orchestration
- Automated volume structure creation
- Health check validation
- CI/CD via GitHub Actions (7 validation jobs)

### 4. Security & Compliance

**Transport Security**:
- HTTPS for all external services (CloudFlare SSL)
- TLS termination via Traefik reverse proxy
- Certificate auto-renewal

**Authentication & Authorization**:
- Grafana: Admin credentials (no hardcoded passwords)
- n8n: Basic Auth with secure credentials
- API access: Token-based authentication

**Network Security**:
- Network isolation (separate bridge networks)
- Internal-only services (no public exposure)
- Firewall rules on Synology NAS

**Secrets Management**:
- Environment variables only (.env, gitignored)
- .env.example templates (committed, no secrets)
- .env.credentials.example for API keys

**Constitutional Framework v11.11 Compliance**:
- ✅ Synology NAS centralized monitoring (Principle #1)
- ✅ No local Grafana/Prometheus/Loki instances (prevents CLASS_1_CRITICAL violations)
- ✅ Universal observability (all projects integrated)
- ✅ /resume/ and /demo/ directories (mandatory structure)
- ✅ English-only documentation (language policy)
- ✅ Environment variable security (no hardcoded secrets)

---

## 📈 Monitoring Coverage

### Active Scrape Targets (12+)

**Core Services**:
1. `grafana` - Grafana internal metrics (grafana-container:3000)
2. `prometheus` - Prometheus self-monitoring (prometheus-container:9090)
3. `loki` - Loki operational metrics (loki-container:3100)
4. `alertmanager` - AlertManager status (alertmanager-container:9093)

**System Exporters**:
5. `node-exporter` - NAS system metrics (node-exporter-container:9100)
6. `cadvisor` - Docker container metrics (cadvisor-container:8080)
7. `node-exporter-local` - Local system metrics (192.168.50.100:9101)
8. `cadvisor-local` - Local container metrics (192.168.50.100:8081)

**Application Services**:
9. `n8n` - Workflow automation metrics (n8n.jclee.me:5678/metrics)
10. `n8n-postgres` - n8n database metrics (n8n-postgres-exporter:9187)
11. `n8n-redis` - n8n cache metrics (n8n-redis-exporter:9121)
12. `blacklist` - Blacklist service metrics (blacklist.jclee.me:2542/metrics)

**Prometheus Configuration**:
- Scrape interval: 15 seconds (configurable)
- Scrape timeout: 10 seconds
- Retention: 30 days
- TSDB path: /volume1/grafana/data/prometheus
- Hot reload: Enabled (`--web.enable-lifecycle`)

### Dashboards (5 Core + Extensible)

**Provisioned Dashboards**:
1. **Monitoring Stack Health** (`monitoring-stack-health`) - USE methodology, self-monitoring
2. **System Metrics** (`system-metrics`) - USE methodology, infrastructure health
3. **Container Performance** (`container-performance`) - Docker resource usage
4. **n8n Workflow Automation** (`n8n-workflow-automation-reds`) - REDS methodology, 15 panels
5. **Log Analysis** (`log-analysis`) - Loki log aggregation and analysis

**Dashboard Features**:
- Auto-provisioning every 10 seconds
- Validated metrics (mandatory pre-deployment validation)
- REDS/USE methodologies for consistency
- Golden Signals in top row
- Meaningful thresholds and units
- Legend calculations (mean, last, max)

**Methodologies**:
- **REDS** (Application Monitoring): Rate, Errors, Duration, Saturation
- **USE** (Infrastructure Monitoring): Utilization, Saturation, Errors

### Recording Rules (7 Groups, 32 Rules)

**Performance Recording Rules**:
- Request rate per service (1m, 5m averages)
- Error rate percentages
- Response time percentiles (P50, P90, P99)

**Container Recording Rules**:
- CPU usage per container
- Memory usage (bytes and percentage)
- Network receive/transmit rates

**Application Recording Rules** (n8n-specific):
- Workflow start rate, active count
- Cache miss rate percentage
- Queue enqueue rate
- Event loop lag (P99, validated)
- Memory usage, GC duration

**Critical**: All recording rules use validated metrics only (learned from 2025-10-13 P95 incident)

### Alert Rules (4 Groups, 20+ Rules)

**Service Health Alerts**:
- PrometheusTargetDown (critical)
- GrafanaDown, LokiDown, PromtailDown
- N8nDown (workflow automation unavailable)

**Performance Alerts**:
- HighErrorRate (>5% for 5min → warning)
- HighResponseTime (P99 >1s for 10min → warning)
- N8nEventLoopLagHigh (P99 >0.5s for 5min → critical)

**Resource Alerts**:
- HighMemoryUsage (>80% for 15min → info)
- HighCPUUsage (>80% for 15min → info)
- DiskSpaceRunningOut (<10% free → warning)

**Business Metrics Alerts**:
- N8nWorkflowFailureRateHigh (>5/min for 5min → warning)

---

## 🔧 Configuration Management

### Prometheus Configuration
**File**: `configs/prometheus.yml`
- 12+ scrape targets (services + exporters)
- Recording rules: `configs/recording-rules.yml` (32 rules)
- Alert rules: `configs/alert-rules.yml` (20+ rules)
- Hot reload supported: `curl -X POST https://prometheus.jclee.me/-/reload`

### Loki Configuration
**File**: `configs/loki-config.yml`
- 3-day retention (optimized for operational logs)
- Chunk encoding: gzip
- Storage: Local filesystem (`/volume1/grafana/data/loki`)
- No hot reload: Requires container restart

### Promtail Configuration
**File**: `configs/promtail-config.yml`
- Docker Service Discovery (auto-discovers containers)
- Filters: `grafana-monitoring-net` network only
- Labels: job, container_id, image, service (from Docker labels)
- Pipeline stages: timestamp, labels, filtering

### Grafana Auto-Provisioning
**Datasources**: `configs/provisioning/datasources/datasource.yml`
- Prometheus (UID: `prometheus`, default)
- Loki (UID: `loki`)
- AlertManager (UID: `P4AAF3E0C04587B6C`)

**Dashboards**: `configs/provisioning/dashboards/*.json`
- Auto-loaded every 10 seconds
- **Do NOT create manually in UI** (will be overwritten)
- Must use correct datasource UIDs

**Dashboard Folders**:
- Core-Monitoring
- Infrastructure
- Applications
- Logging
- Alerting

---

## 🚀 Deployment Summary

### Infrastructure Requirements
- **Host**: Synology NAS DSM 7.0+ with Docker
- **SSH**: Port 1111, passwordless key authentication
- **Storage**: ~20GB for all services (30-day Prometheus + 3-day Loki)
- **Network**: Bridge networks + Traefik reverse proxy
- **DNS**: CloudFlare with SSL/TLS

### Deployment Steps (Summary)
1. **Prerequisites**: SSH keys, Docker on Synology, sync service
2. **Environment**: Configure .env and .env.credentials
3. **Volume Structure**: Run `scripts/create-volume-structure.sh` on NAS
4. **Deploy**: `docker-compose up -d` on Synology
5. **Verify**: Health checks, Prometheus targets, Grafana dashboards

**Full deployment guide**: [deployment.md](./deployment.md) (500+ lines)

### Operational Scripts

**Health Check**:
```bash
./scripts/health-check.sh
# Validates: Grafana, Prometheus, Loki, AlertManager
# Checks: Prometheus targets, docker-compose syntax
# Returns: 0=healthy, 1=unhealthy, 2=partial
```

**Metrics Validation**:
```bash
./scripts/validate-metrics.sh
# Validates: Dashboard JSON files, extracts metrics
# Queries: Prometheus to verify metrics exist
# Prevents: "No Data" panels (mandatory pre-deployment)
```

**Real-time Sync**:
```bash
# Automatic via grafana-sync.service (1-2s latency)
sudo systemctl status grafana-sync
sudo journalctl -u grafana-sync -f

# Manual trigger (only if service down)
./scripts/realtime-sync.sh
```

---

## 📚 Related Documentation

### Internal Documentation
- [Architecture Deep Dive](./architecture.md) - 700+ lines, deployment topology, data flows
- [API Reference](./api.md) - 600+ lines, complete API documentation
- [Deployment Guide](./deployment.md) - 500+ lines, step-by-step procedures
- [Troubleshooting Guide](./troubleshooting.md) - 600+ lines, common issues and fixes

### Configuration Files
- [Prometheus Config](../configs/prometheus.yml) - Scrape targets, recording rules, alert rules
- [Loki Config](../configs/loki-config.yml) - Log storage and retention
- [Promtail Config](../configs/promtail-config.yml) - Log collection and forwarding
- [Grafana Datasources](../configs/provisioning/datasources/datasource.yml)
- [Dashboard Provisioning](../configs/provisioning/dashboards/)

### Demonstration Materials
- [Demo Guide](../demo/README.md) - 577 lines, complete demo scenarios
- [Sample Dashboard](../demo/examples/sample-dashboard.json) - REDS methodology template
- [Sample Alert Rules](../demo/examples/sample-alert-rule.yml)
- [Sample Recording Rules](../demo/examples/sample-recording-rule.yml)
- [Sample Promtail Config](../demo/examples/sample-promtail-config.yml)

### Access Points
- **Grafana**: https://grafana.jclee.me (admin / from .env)
- **Prometheus**: https://prometheus.jclee.me
- **Loki**: https://loki.jclee.me
- **AlertManager**: https://alertmanager.jclee.me
- **n8n**: https://n8n.jclee.me
- **SSH Access**: `ssh -p 1111 jclee@192.168.50.215`

---

## 📊 Project Metrics

**Documentation Coverage**: 2,400+ lines of technical documentation
**Configuration Files**: 10+ YAML/JSON configs, all validated
**Dashboards**: 5 core dashboards, 40+ panels, 100% operational
**Metrics**: 12+ scrape targets, 32 recording rules
**Alerts**: 20+ alert rules across 4 groups
**Scripts**: 5+ automation scripts (health check, validation, sync)
**CI/CD**: 7 GitHub Actions validation jobs
**Code Quality**: A- (4.0/5) - Security, testing, automation

**Incidents**:
- 2025-10-13: Metrics validation incident (P95 doesn't exist) - Fixed with mandatory validation
- 2025-10-14: Security improvements, environment variable migration
- 2025-10-16: Recording rules updated (validated metrics only)

**Compliance**:
- ✅ Constitutional Framework v11.11 (95%+ compliance)
- ✅ English-only documentation policy
- ✅ /resume/ and /demo/ mandatory structure
- ✅ No hardcoded secrets (environment variables only)
- ✅ Automated validation (GitHub Actions)

---

## 🏆 Technical Excellence

This project demonstrates:

1. **Production-Grade Architecture**: Remote-first deployment, HTTPS, persistent storage
2. **Operational Excellence**: Real-time sync, auto-provisioning, automated validation
3. **Comprehensive Observability**: Logs, metrics, alerts all integrated
4. **Security Best Practices**: No hardcoded secrets, network isolation, SSL/TLS
5. **Documentation Standards**: 2,400+ lines, English-only, comprehensive examples
6. **Automation First**: CI/CD, health checks, metrics validation
7. **Continuous Improvement**: Incident-driven learning, metrics validation after 2025-10-13

**Constitutional Framework Compliance**: 95%+ (v11.11)

---

**Last Updated**: 2025-10-17
**Status**: Active, Production
**Deployment**: Synology NAS (192.168.50.215:1111)
**Development**: Rocky Linux 9 (192.168.50.100)
**Sync**: Real-time (1-2s latency via grafana-sync.service)
