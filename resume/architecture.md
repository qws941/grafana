# Architecture Overview

## System Design

### Deployment Architecture

```
Local Machine (Development)          Synology NAS (192.168.50.215:1111)
───────────────────────────          ──────────────────────────────────
/home/jclee/app/grafana/             /volume1/grafana/
├── configs/              ◄────────► ├── configs/         (real-time sync)
├── scripts/              systemd    ├── scripts/
├── docker-compose.yml    service    ├── docker-compose.yml
└── docs/                            └── Docker Services:
                                         - grafana-container      (3000)
Real-time Sync Daemon                    - prometheus-container   (9090)
└── grafana-sync.service                 - loki-container         (3100)
    ├── fs.watch → detect changes        - alertmanager-container (9093)
    ├── debounce (1s delay)              - promtail-container
    └── rsync over SSH                   - node-exporter-container
                                         - cadvisor-container
```

### Architecture Principles

1. **Remote-First Deployment**: All production services run on Synology NAS, not locally
2. **Real-time Synchronization**: Local changes automatically sync to NAS within 1-2 seconds
3. **Network Isolation**: Services communicate on internal network, external access via Traefik
4. **Configuration as Code**: All configs in git, environment variables for secrets

---

## Service Components

### Core Monitoring Stack

#### Grafana (Port 3000)
**Purpose**: Visualization and dashboard platform
**Container**: grafana-container
**Data Sources**:
- Prometheus (metrics)
- Loki (logs)
- AlertManager (alerts)

**Key Features**:
- Auto-provisioning dashboards every 10 seconds
- Public dashboards enabled
- Plugin support (8 plugins installed)

**Volumes**:
- `/var/lib/grafana` - Data storage (dashboards, users, settings)
- `/etc/grafana/provisioning` - Datasources and dashboard definitions (read-only)

#### Prometheus (Port 9090)
**Purpose**: Metrics collection and time-series database
**Container**: prometheus-container
**Configuration**: /etc/prometheus-configs/prometheus.yml

**Key Features**:
- Hot reload support (--web.enable-lifecycle)
- Admin API enabled
- 30-day retention (configurable)
- Recording rules (32 rules across 7 groups)
- Alert rules (20+ rules across 4 groups)

**Scrape Targets**:
- Core: grafana, prometheus, loki, alertmanager
- Exporters: node-exporter, cadvisor
- Applications: n8n (workflow automation)
- Remote: local-node-exporter, local-cadvisor, ai-agents, hycu-automation

**Volumes**:
- `/prometheus` - Time-series database
- `/etc/prometheus-configs` - Configuration files (read-only)

#### Loki (Port 3100)
**Purpose**: Log aggregation system
**Container**: loki-container
**Configuration**: /etc/loki/local-config.yaml

**Key Features**:
- 3-day retention
- Multi-tenant support
- Label-based indexing

**Volumes**:
- `/loki` - Log storage
- `/etc/loki/local-config.yaml` - Configuration (read-only)

#### Promtail
**Purpose**: Log collector and shipper
**Container**: promtail-container
**Configuration**: /etc/promtail/config.yml

**Key Features**:
- Docker service discovery (auto-discovers containers on monitoring-net)
- System log collection (/var/log/*.log)
- Label transformation

**Limitations**:
- Synology `db` logging driver blocks some log collection
- Documented in docs/N8N-LOG-INVESTIGATION-2025-10-12.md

**Volumes**:
- `/var/run/docker.sock` - Docker API access (read-only)
- `/etc/promtail/config.yml` - Configuration (read-only)

#### AlertManager (Port 9093)
**Purpose**: Alert routing and notification
**Container**: alertmanager-container
**Configuration**: /etc/alertmanager/alertmanager.yml

**Key Features**:
- Webhook integration with n8n
- Alert grouping and throttling
- Silence management

**Volumes**:
- `/alertmanager` - Alert state storage
- `/etc/alertmanager/alertmanager.yml` - Configuration (read-only)

### Data Collection Layer

#### Node Exporter (Port 9100)
**Purpose**: System-level metrics collection
**Container**: node-exporter-container

**Metrics Collected**:
- CPU usage and load average
- Memory utilization
- Disk I/O and space
- Network statistics
- System uptime

**Volumes** (read-only):
- `/host/proc` - Process information
- `/host/sys` - System information
- `/rootfs` - Filesystem information

#### cAdvisor (Port 8080)
**Purpose**: Container-level metrics collection
**Container**: cadvisor-container

**Metrics Collected**:
- Container CPU usage
- Container memory usage
- Container network I/O
- Container disk I/O

**Security Note**: Runs with `privileged: true` (required for full container metrics)

**Volumes** (read-only):
- `/` - Root filesystem
- `/var/run` - Docker runtime
- `/sys` - System information
- `/var/lib/docker` - Docker data

---

## Network Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                      traefik-public                         │
│                   (External Network)                         │
│                                                               │
│  Internet ──► CloudFlare ──► Traefik ──► Services          │
│                SSL            Reverse                         │
│                              Proxy                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ (Ports 3000, 9090, 3100, 9093)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   grafana-monitoring-net                     │
│                   (Internal Network)                         │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Grafana  │  │Prometheus│  │   Loki   │  │AlertMgr  │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
│       │              │              │              │        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │ Promtail │  │Node Exp. │  │ cAdvisor │                │
│  └──────────┘  └──────────┘  └──────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Network Configuration

**traefik-public** (External):
- Type: Pre-existing external network
- Purpose: Reverse proxy and SSL termination
- Access: HTTPS via CloudFlare certificates
- Services exposed: grafana, prometheus, loki, alertmanager

**grafana-monitoring-net** (Internal):
- Type: Bridge network
- Purpose: Internal service communication
- Services: All monitoring stack components
- Isolation: No direct external access

### Service Discovery

**Container Naming Convention**:
- Format: `{service}-container`
- Examples: `grafana-container:3000`, `prometheus-container:9090`
- **CRITICAL**: Always use full container names in configs (not short names)

**DNS Resolution**:
- Internal: Services resolve via Docker DNS (e.g., `prometheus-container:9090`)
- External: Services accessible via domain names (e.g., `grafana.jclee.me`)

---

## Data Flow Pipelines

### Metrics Collection Pipeline

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
```

**Flow Details**:
1. **Collection**: Prometheus scrapes `/metrics` endpoints every 15s (configurable per job)
2. **Storage**: Time-series data stored in Prometheus TSDB (30-day retention)
3. **Processing**: Recording rules pre-aggregate metrics every 30s
4. **Visualization**: Grafana queries Prometheus via PromQL
5. **Alerting**: Prometheus evaluates alert rules, sends to AlertManager

### Log Collection Pipeline

```
┌─────────────────────────────────────────────────────────┐
│ Log Collection                                          │
├─────────────────────────────────────────────────────────┤
│ Docker Logs ──► Promtail ──► Loki ──► Grafana         │
│                                                          │
│ Important: Promtail uses Docker Service Discovery       │
│ Auto-discovers containers on grafana-monitoring-net     │
│ ⚠️  Synology `db` driver blocks some log collection    │
└─────────────────────────────────────────────────────────┘
```

**Flow Details**:
1. **Collection**: Promtail reads Docker logs via Docker API (`/var/run/docker.sock`)
2. **Discovery**: Auto-discovers containers on `grafana-monitoring-net` network
3. **Labeling**: Adds labels (job, container_name, host, environment)
4. **Shipping**: Sends logs to Loki over HTTP
5. **Storage**: Loki stores logs with 3-day retention
6. **Query**: Grafana queries Loki via LogQL

**Known Limitations**:
- Synology `db` logging driver blocks some containers
- Solution: Use Prometheus metrics instead (more reliable)
- Documentation: docs/N8N-LOG-INVESTIGATION-2025-10-12.md

### Alerting Pipeline

```
┌─────────────────────────────────────────────────────────┐
│ Alerting Pipeline                                       │
├─────────────────────────────────────────────────────────┤
│ Prometheus Rules ──► AlertManager ──► Webhooks         │
│ Alert rules: configs/alert-rules.yml (20 rules active) │
└─────────────────────────────────────────────────────────┘
```

**Flow Details**:
1. **Evaluation**: Prometheus evaluates alert rules every 15s
2. **Firing**: Alerts sent to AlertManager when conditions met
3. **Grouping**: AlertManager groups similar alerts
4. **Routing**: Routes to appropriate receivers (webhooks, email, Slack)
5. **Notification**: n8n workflows process webhooks (automation)

---

## Configuration Management

### Real-time Synchronization

**Sync Service**: grafana-sync.service (systemd)
**Mechanism**: File watcher (fs.watch) + rsync over SSH
**Latency**: 1-2 seconds
**Direction**: Bi-directional (local ↔ NAS)

**Workflow**:
1. Developer edits config locally (e.g., `configs/prometheus.yml`)
2. File watcher detects change (inotify)
3. Debounce timer waits 1 second (prevent multiple triggers)
4. rsync transfers changed files to NAS via SSH
5. Remote service reloads configuration (if hot reload supported)

**Hot Reload Support**:
- Prometheus: ✅ Yes (`curl -X POST https://prometheus.jclee.me/-/reload`)
- Grafana: ❌ No (dashboards auto-provision every 10s, restart for other changes)
- Loki: ❌ No (restart required)
- AlertManager: ❌ No (restart required)

**Monitoring**:
- Service status: `sudo systemctl status grafana-sync`
- Real-time logs: `sudo journalctl -u grafana-sync -f`

### Configuration Files Structure

```
configs/
├── prometheus.yml              # Prometheus scrape configuration
├── recording-rules.yml         # Pre-aggregated metrics (32 rules)
├── loki-config.yaml            # Loki storage and retention
├── promtail-config.yml         # Promtail log collection
├── promtail-local-config.yml   # Local Promtail (dev machine)
├── alertmanager.yml            # AlertManager routing
├── alert-rules/
│   └── log-collection-alerts.yml
├── provisioning/
│   ├── datasources/
│   │   └── datasource.yml      # Grafana datasource definitions
│   └── dashboards/
│       ├── dashboard.yml       # Dashboard provisioning config
│       ├── core-monitoring/    # 3 dashboards
│       ├── infrastructure/     # 3 dashboards
│       ├── applications/       # 4 dashboards
│       ├── logging/            # 1 dashboard
│       └── alerting/           # 1 dashboard
└── n8n-workflows/
    └── alertmanager-webhook.json
```

---

## Security Architecture

### Access Control

**Authentication**:
- Grafana: Admin user with password (via `GRAFANA_ADMIN_PASSWORD` env var)
- Prometheus: No authentication (internal network only)
- Loki: No authentication (internal network only)
- AlertManager: No authentication (internal network only)

**Network Security**:
- Internal services: Only accessible within `grafana-monitoring-net`
- External access: Only via Traefik reverse proxy
- SSL/TLS: CloudFlare certificates (automatic renewal)

**Container Security**:
- Read-only config volumes (`:ro` flag)
- Pinned image versions (no `:latest` in production)
- Privileged containers: Only cAdvisor (required for container metrics)

### Secrets Management

**Environment Variables**:
- All secrets via environment variables (never hardcoded)
- `.env` file (gitignored, local only)
- `.env.example` (committed, template with placeholders)

**SSH Access**:
- Synology NAS: Port 1111 (non-standard)
- Key-based authentication recommended
- Used for: Real-time sync, remote operations

---

## Observability Design

### Monitoring Methodologies

#### REDS (for Applications)
**Components**:
- **Rate**: Throughput (requests/min, workflows/min)
- **Errors**: Failure rates, error counts
- **Duration**: Response time percentiles (P50, P90, P99)
- **Saturation**: Resource utilization (active handles, queue depth)

**Applied To**: n8n, AI Agents, HYCU Automation, Traefik

#### USE (for Infrastructure)
**Components**:
- **Utilization**: CPU %, memory %, disk %
- **Saturation**: Load average, queue depth
- **Errors**: Error rates and counts

**Applied To**: System metrics, container metrics, monitoring stack health

### Dashboard Organization

**Folder Structure** (5 folders):
1. **core-monitoring** (3 dashboards) - Monitoring stack health, query performance, service health
2. **infrastructure** (3 dashboards) - System metrics, container performance, Traefik
3. **applications** (4 dashboards) - n8n, AI agents, HYCU, application monitoring
4. **logging** (1 dashboard) - Log analysis
5. **alerting** (1 dashboard) - Alert overview

**Total**: 12 dashboards

### Metrics Validation

**Critical Process** (learned from 2025-10-13 incident):
1. Query Prometheus API for metric existence
2. Test metrics return data
3. Deploy dashboard only if validation passes

**Tool**: `scripts/validate-metrics.sh`

**Example Incident**:
- Dashboard used `n8n_nodejs_eventloop_lag_p95_seconds`
- Metric doesn't exist (n8n only exposes P50, P90, P99)
- Result: "No Data" panel
- Fix: Mandatory validation before deployment

---

## Integration Architecture

### External Systems

**Synology NAS** (192.168.50.215):
- Docker runtime for all services
- NFS storage for Grafana data
- SSH access for remote operations (port 1111)

**Traefik Reverse Proxy**:
- Network: traefik-public (external)
- SSL termination via CloudFlare
- Service routing by domain name

**n8n Workflow Automation** (n8n.jclee.me):
- AlertManager webhook receiver
- Automation workflows (Slack notifications, ticket creation)
- Stored workflows: configs/n8n-workflows/

**AI Agents** (192.168.50.100:9091):
- MCP server metrics
- AI model usage tracking
- Cost monitoring
- Exporter: scripts/ai-metrics-exporter/

**HYCU Automation** (192.168.50.100:9092):
- Backup automation metrics
- Job status tracking
- Exporter: External service

### API Endpoints

**Prometheus**:
- Query API: `https://prometheus.jclee.me/api/v1/query`
- Targets API: `https://prometheus.jclee.me/api/v1/targets`
- Reload: `https://prometheus.jclee.me/-/reload` (POST)

**Grafana**:
- Health: `https://grafana.jclee.me/api/health`
- Dashboards: `https://grafana.jclee.me/api/search`
- Datasources: `https://grafana.jclee.me/api/datasources`

**Loki**:
- Query: `https://loki.jclee.me/loki/api/v1/query`
- Labels: `https://loki.jclee.me/loki/api/v1/labels`
- Ready: `https://loki.jclee.me/ready`

**AlertManager**:
- Alerts: `https://alertmanager.jclee.me/api/v2/alerts`
- Webhook: Configured in alertmanager.yml

---

## Performance Optimization

### Recording Rules

**Purpose**: Pre-aggregate frequently queried metrics
**Interval**: 30 seconds
**Count**: 32 rules across 7 groups

**Example Rules**:
```promql
# n8n workflow metrics
- record: n8n:workflows:start_rate
  expr: rate(n8n_workflow_started_total[5m]) * 60

- record: n8n:cache:miss_rate_percent
  expr: rate(n8n_cache_misses_total[5m]) / (rate(n8n_cache_hits_total[5m]) + rate(n8n_cache_misses_total[5m])) * 100
```

**Benefits**:
- Faster dashboard loading
- Reduced query complexity
- Lower CPU usage on Prometheus

### Metric Relabeling

**Purpose**: Drop unnecessary metrics at scrape time
**Location**: prometheus.yml scrape configs

**Example**:
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'mcp_ai_.*'
    action: keep  # Only keep AI-related metrics
```

**Benefits**:
- Reduced storage requirements
- Faster query performance
- Lower network bandwidth

### Retention Policies

**Prometheus**: 30 days (configurable via `PROMETHEUS_RETENTION_TIME`)
**Loki**: 3 days (configurable in loki-config.yaml)
**Grafana**: Permanent (dashboards, users, settings)
**AlertManager**: 120 hours (default)

---

## Disaster Recovery

### Backup Strategy

**What to Backup**:
- Grafana data: `/volume1/grafana/data/grafana`
- Prometheus data: `/volume1/grafana/data/prometheus` (optional, historical data)
- Configurations: All files in `/volume1/grafana/configs` (already in git)

**Backup Script**: `scripts/backup.sh`

**Recovery Process**:
1. Restore configurations from git
2. Restore Grafana data from backup (dashboards, users, settings)
3. Recreate volumes on NAS (scripts/create-volume-structure.sh)
4. Deploy services (docker-compose up -d)
5. Verify health (scripts/health-check.sh)

### Monitoring Stack Failure

**Scenario**: Grafana/Prometheus unavailable

**Impact**:
- Loss of real-time visibility
- No alerting (AlertManager down)
- Historical data unavailable

**Mitigation**:
- External monitoring (e.g., UptimeRobot)
- Backup monitoring stack (future)
- NAS replication (future)

---

## Scalability Considerations

### Current Limitations

**Single Point of Failure**:
- Single Synology NAS
- No HA/redundancy
- No automatic failover

**Resource Constraints**:
- NAS CPU: Shared with other services
- NAS Memory: Limited (monitor container memory usage)
- NAS Disk: 3.4GB project, growing with logs/metrics

### Future Scalability

**Horizontal Scaling** (not implemented):
- Prometheus federation (multiple Prometheus instances)
- Loki distributed mode (ingester, querier, compactor)
- Grafana HA (multiple instances behind load balancer)

**Vertical Scaling**:
- Increase NAS resources (CPU, memory, disk)
- Optimize retention policies (reduce data volume)
- Use recording rules (reduce query complexity)

---

## Operational Procedures

See:
- docs/OPERATIONAL-RUNBOOK.md - Day-to-day operations
- resume/deployment.md - Deployment procedures
- resume/troubleshooting.md - Incident response

---

## References

- docs/REALTIME_SYNC.md - Real-time synchronization details
- docs/GRAFANA-BEST-PRACTICES-2025.md - Dashboard design guidelines
- docs/METRICS-VALIDATION-2025-10-12.md - Metrics validation methodology
- docs/N8N-LOG-INVESTIGATION-2025-10-12.md - Logging constraints
- docs/CODEBASE-ANALYSIS-REPORT-2025-10-17.md - Comprehensive analysis

---

**Last Updated**: 2025-10-17
**Architecture Version**: 1.0
**Maintainer**: DevOps Team
