# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive Grafana Monitoring Stack deployment configuration for **remote Synology NAS** (192.168.50.215), providing a complete observability solution:

- **Core Monitoring**: Grafana, Prometheus, Loki, Alertmanager
- **Workflow Automation**: n8n with PostgreSQL and Redis backends
- **Metrics Collection**: Promtail, Node Exporter, cAdvisor, PostgreSQL Exporter, Redis Exporter
- **Special Integration**: Claude Code conversation log collection to Loki

**Critical Architecture Note**: This stack runs **remotely** on Synology NAS, not locally. All configuration changes must be uploaded via SSH and containers managed remotely.

## Deployment Architecture

```
Local Machine                    Synology NAS (192.168.50.215:1111)
────────────────                 ──────────────────────────────────
/home/jclee/app/grafana/    SSH  /volume1/docker/grafana/
├── configs/                ───► ├── configs/
├── compose/                     ├── grafana/      (uid:472)
└── scripts/                     ├── prometheus/   (uid:65534)
                                 ├── loki/         (uid:10001)
                                 └── alertmanager/ (uid:65534)

                                 Docker Containers:
                                 ├── grafana-container      (3000)
                                 ├── prometheus-container   (9090)
                                 ├── loki-container         (3100)
                                 ├── alertmanager-container (9093)
                                 ├── promtail-container
                                 ├── node-exporter-container
                                 └── cadvisor-container
```

## Key Commands

### Remote Deployment Workflow

**Standard workflow for configuration changes:**

```bash
# 1. Edit configs locally
vim configs/prometheus.yml

# 2. Upload to Synology NAS
cat configs/prometheus.yml | ssh -p 1111 jclee@192.168.50.215 \
  "sudo tee /volume1/docker/grafana/configs/prometheus.yml > /dev/null"

# 3a. Reload Prometheus (hot reload, no downtime)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# 3b. Or restart container (for Grafana, Loki, etc.)
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
```

### Remote Container Management

```bash
# SSH connection
ssh -p 1111 jclee@192.168.50.215

# Check all monitoring containers
sudo docker ps | grep -E 'grafana|prometheus|loki|promtail|n8n'

# View logs
sudo docker logs -f grafana-container
sudo docker logs prometheus-container --tail 50

# Restart specific service
sudo docker restart loki-container

# Check container health
sudo docker inspect grafana-container | jq '.[0].State.Health'

# Execute commands inside containers
sudo docker exec prometheus-container wget -qO- http://localhost:9090/-/healthy
sudo docker exec grafana-container curl -s http://localhost:3000/api/health
```

### Grafana API Operations

Use `scripts/grafana-api.sh` for authenticated API calls (requires `.env.credentials`):

```bash
# List datasources
./scripts/grafana-api.sh datasources

# List dashboards
./scripts/grafana-api.sh dashboards

# Get current user
./scripts/grafana-api.sh user

# Custom API endpoint
./scripts/grafana-api.sh api /api/health

# Show all available commands
./scripts/grafana-api.sh help
```

**Direct API calls to remote Grafana:**

```bash
# Using basic auth
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/datasources" | jq '.'

# List all dashboards
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/search?type=dash-db" | jq '.'

# Get specific dashboard
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/dashboards/uid/YOUR-UID" | jq '.'

# Delete datasource
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  -X DELETE http://localhost:3000/api/datasources/uid/YOUR-UID" | jq '.'
```

### Service Health Verification

```bash
# Check Prometheus targets status
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check Loki readiness
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec loki-container wget -qO- http://localhost:3100/ready"

# Verify AlertManager cluster status
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec alertmanager-container wget -qO- \
  http://localhost:9093/api/v2/status" | jq '.cluster.status'

# Check n8n metrics endpoint
ssh -p 1111 jclee@192.168.50.215 \
  "curl -s http://localhost:5678/metrics" | grep n8n_active_workflow_count
```

### Initial Deployment (First Time Only)

```bash
# 1. Create volume structure on Synology NAS
ssh -p 1111 jclee@192.168.50.215
cd /volume1/docker/grafana
sudo ./scripts/create-volume-structure.sh

# 2. Upload all configs
scp -P 1111 -r configs/* jclee@192.168.50.215:/volume1/docker/grafana/configs/

# 3. Upload docker-compose.yml
scp -P 1111 compose/docker-compose.yml jclee@192.168.50.215:/volume1/docker/grafana/

# 4. Start stack
ssh -p 1111 jclee@192.168.50.215
cd /volume1/docker/grafana
sudo docker compose up -d
```

## Architecture Details

### Service Network Topology

**Networks:**
- `traefik-public` (external): Traefik reverse proxy integration with SSL termination
- `grafana-monitoring-net` (bridge): Internal service communication

**Container Naming Convention:**
- Service name in docker-compose.yml: `grafana`
- Actual container name: `grafana-container`
- DNS resolution within network: Use container names (e.g., `prometheus-container:9090`)

**Critical**: Always use full container names in configs (e.g., `loki-container:3100`), not service names from docker-compose.

### Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ Metrics Collection                                      │
├─────────────────────────────────────────────────────────┤
│ Services ──► Prometheus (scrape) ──► Grafana (query)  │
│ n8n:5678/metrics                                        │
│ node-exporter:9100                                      │
│ cadvisor:8080                                           │
│ postgres-exporter:9187                                  │
│ redis-exporter:9121                                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Log Collection                                          │
├─────────────────────────────────────────────────────────┤
│ Docker Logs ──► Promtail ──► Loki ──► Grafana         │
│ System Logs ──► Promtail ──► Loki ──► Grafana         │
│ Claude Logs ──► Direct Push ──► Loki ──► Grafana      │
│ Gemini Logs ──► Promtail ──► Loki ──► Grafana         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Alerting Pipeline                                       │
├─────────────────────────────────────────────────────────┤
│ Prometheus Rules ──► AlertManager ──► Webhooks         │
│ Grafana Alerts ──► AlertManager ──► Notifications      │
└─────────────────────────────────────────────────────────┘
```

### Volume Ownership Requirements

**Critical**: Containers run as non-root users and require specific ownership:

| Service | UID | GID | Path |
|---------|-----|-----|------|
| Grafana | 472 | 472 | `/volume1/docker/grafana/grafana/` |
| Prometheus | 65534 | 65534 | `/volume1/docker/grafana/prometheus/` |
| Loki | 10001 | 10001 | `/volume1/docker/grafana/loki/` |
| Alertmanager | 65534 | 65534 | `/volume1/docker/grafana/alertmanager/` |

Run `scripts/create-volume-structure.sh` to set correct permissions automatically.

## Configuration Management

### Prometheus Scrape Targets

**File**: `configs/prometheus.yml`

When adding new monitoring targets:
1. Add scrape config to `configs/prometheus.yml`
2. Upload to Synology
3. Hot reload Prometheus (no downtime)

**Example scrape config:**
```yaml
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['my-service.jclee.me:8080']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

**Important**: Use full container names for internal services:
- ✅ `prometheus-container:9090`
- ✅ `n8n-postgres-exporter-container:9187`
- ❌ `n8n-postgres-exporter:9187` (won't resolve)

### Promtail Log Collection

**File**: `configs/promtail-config.yml`

**Current scrape jobs:**
1. `docker-containers` - Auto-discovers all Docker containers via docker_sd_configs
2. `system-logs` - System logs from `/var/log/*.log`
3. `gemini-logs` - AI conversation logs from `/var/log/gemini/*.log`

**Adding new static log sources:**
```yaml
- job_name: my-app-logs
  static_configs:
    - targets:
        - localhost
      labels:
        job: my-app
        service: my-service
        environment: production
        __path__: /var/log/my-app/*.log

  pipeline_stages:
    - json:
        expressions:
          level: level
          timestamp: timestamp
          message: message
    - labels:
        level:
    - timestamp:
        source: timestamp
        format: RFC3339
```

**Note**: Loki has 3-day retention by default. Logs older than 3 days are rejected.

### Grafana Datasource Auto-Provisioning

**File**: `configs/provisioning/datasources/datasource.yml`

Datasources are automatically provisioned on Grafana startup:
- **Prometheus** (UID: `prometheus`) - Default datasource
- **Loki** (UID: `loki`) - Log queries
- **AlertManager** (UID: `P4AAF3E0C04587B6C`) - Alert management

**Do not create datasources manually** in Grafana UI. They will be overwritten on restart. Instead, edit `datasource.yml` and restart Grafana.

### Grafana Dashboard Auto-Provisioning

**Directory**: `configs/provisioning/dashboards/`

Dashboard JSON files are auto-loaded on Grafana startup (refreshes every 10 seconds).

**Current dashboards:**
1. `n8n-workflow-monitoring.json` (UID: `n8n-workflow-monitoring`) - 6 panels
2. `redis-performance-monitoring.json` (UID: `redis-performance-monitoring`) - 9 panels
3. `system-overview.json` (UID: `system-overview`) - 7 panels
4. `integrated-monitoring-v2.json` (UID: `integrated-monitoring-v2`) - 8 panels
5. `gemini-conversation-analytics.json` (UID: `gemini-conversation`) - 9 panels

**Adding new dashboard:**
1. Export dashboard JSON from Grafana UI
2. Set unique `uid` field
3. Configure datasource UIDs (`"uid": "prometheus"` or `"uid": "loki"`)
4. Save to `configs/provisioning/dashboards/your-dashboard.json`
5. Upload to Synology NAS
6. Wait 10 seconds for auto-load OR restart Grafana for immediate load

**Important**: Dashboard filename should match UID for clarity (e.g., `my-dashboard.json` for `"uid": "my-dashboard"`).

## Claude Code Log Collection

**Architecture:**
```
Local Machine                      Synology NAS
─────────────────                  ─────────────
~/.claude/history.jsonl
        │
        ▼
/tmp/claude-log-collector-simple.sh  (cron: */5)
        │
        ▼ (HTTP POST)
loki-container:3100/loki/api/v1/push
        │
        ▼ (LogQL query)
grafana-container:3000
```

**Operational commands:**

```bash
# Manual sync
/tmp/claude-log-collector-simple.sh

# Check sync position
cat /tmp/claude-loki-position.txt  # Current line number

# View sync logs
tail -f /tmp/claude-log-sync.log

# Query in Grafana Explore
{job="claude-code"}
{job="claude-code", project="/home/jclee/app/grafana"}
{job="claude-code"} | json | line_format "{{.role}}: {{.content}}"
```

**Cron schedule**: `*/5 * * * * /tmp/claude-log-collector-simple.sh` (every 5 minutes)

**Important**: If logs aren't appearing in Loki:
1. Check position file is updating: `cat /tmp/claude-loki-position.txt`
2. Check sync log for errors: `tail -20 /tmp/claude-log-sync.log`
3. Verify Loki is accepting logs: `ssh -p 1111 jclee@192.168.50.215 "sudo docker logs loki-container --tail 50"`
4. Restart Promtail if needed: `ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"`

## Troubleshooting

### Prometheus Target DOWN

**Symptom**: `up{job="service"} == 0` or target shows as DOWN in Prometheus UI

**Common causes:**
1. **Wrong hostname**: Check if using container name (e.g., `n8n-postgres-exporter-container`) not service name
2. **Network mismatch**: Service not on `grafana-monitoring-net` network
3. **Port mismatch**: Verify service is actually listening on configured port
4. **Service not ready**: Check container is running and healthy

**Debug steps:**
```bash
# Verify DNS resolution
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container nslookup n8n-postgres-exporter-container"

# Test connectivity from Prometheus container
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://n8n-postgres-exporter-container:9187/metrics"

# Check Prometheus config syntax
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container promtool check config /etc/prometheus/prometheus.yml"

# View Prometheus scrape errors
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, error: .lastError}'
```

### Logs Not Appearing in Loki

**Symptom**: LogQL query returns 0 results for expected logs

**Common causes:**
1. **Logs too old**: Loki rejects logs older than 3 days (retention policy)
2. **Promtail not watching files**: Missing job config in `promtail-config.yml`
3. **Volume mount missing**: Promtail can't access log files
4. **Label mismatch**: Query using wrong job label

**Debug steps:**
```bash
# Check Promtail targets
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs promtail-container --tail 50 | grep -E 'Adding target|watching new directory'"

# View Promtail position tracking
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec promtail-container cat /tmp/positions.yaml"

# Check Loki ingestion logs
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs loki-container --tail 100 | grep -E 'POST /loki/api/v1/push|entry out of order'"

# Test Loki health
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec loki-container wget -qO- http://localhost:3100/ready"

# Reset Promtail positions (re-reads all files from start)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec promtail-container sh -c 'echo \"positions:\" > /tmp/positions.yaml' && \
  sudo docker restart promtail-container"
```

### Grafana Datasource "Plugin Unavailable"

**Symptom**: Datasource health check returns `{"statusCode": 500, "message": "Plugin unavailable"}`

**Note**: This is often a **cosmetic UI issue**. Test if datasource works via proxy endpoint:

```bash
# Test Prometheus datasource (replace UID)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=up"

# Test Loki datasource
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  'http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/labels'"

# Test AlertManager datasource
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  http://localhost:3000/api/datasources/proxy/uid/P4AAF3E0C04587B6C/api/v2/status"
```

If queries work, ignore the health check error. If not:
1. Restart Grafana: `sudo docker restart grafana-container`
2. Check datasource URL is correct (use container names)
3. Verify network connectivity between Grafana and target service

### n8n Service Issues

**PostgreSQL Exporter Configuration Error:**

If logs show: `field auto_discover_databases not found` or `field exclude_databases not found`

Solution: These are deprecated fields in newer postgres_exporter versions. Remove from `configs/postgres_exporter.yml`:

```yaml
# ❌ Remove these deprecated fields
auto_discover_databases: true
exclude_databases: []

# ✅ Keep only auth_modules section
auth_modules:
  n8n:
    type: userpass
    userpass:
      username: n8n
      password: ${N8N_DB_PASSWORD}
    options:
      sslmode: disable
```

### Volume Permission Issues

**Symptom**: Container fails to start with "Permission denied" errors

**Solution**: Recreate volume structure with correct ownership:

```bash
ssh -p 1111 jclee@192.168.50.215
cd /volume1/docker/grafana
sudo ./scripts/create-volume-structure.sh

# Verify ownership
ls -la /volume1/docker/grafana/
# Expected: grafana/ (472:472), prometheus/ (65534:65534), loki/ (10001:10001)
```

## Available Metrics

### n8n Metrics
- `n8n_active_workflow_count` - Number of active workflows
- `n8n_process_cpu_seconds_total` - Total CPU time consumed
- `n8n_nodejs_heap_size_used_bytes` - Node.js heap memory usage
- `n8n_nodejs_eventloop_lag_seconds` - Event loop lag (p50, p99)
- `n8n_nodejs_external_memory_bytes` - External memory usage

### Redis Metrics (n8n queue)
- `redis_up` - Redis availability (0 or 1)
- `redis_connected_clients` - Number of connected clients
- `redis_memory_used_bytes` - Total memory consumption
- `redis_commands_processed_total` - Total commands processed
- `redis_keyspace_hits_total` / `redis_keyspace_misses_total` - Cache hit/miss rate
- `redis_blocked_clients` - Clients blocked on blocking calls

### PostgreSQL Metrics (n8n database)
- `pg_up` - PostgreSQL availability (0 or 1)
- `pg_stat_database_numbackends` - Number of active connections
- `pg_database_size_bytes` - Database size in bytes
- `pg_stat_activity_count` - Active queries count
- `pg_stat_database_xact_commit` / `pg_stat_database_xact_rollback` - Transaction stats

### System Metrics (Node Exporter)
- `node_cpu_seconds_total` - CPU time per core per mode
- `node_memory_MemAvailable_bytes` - Available system memory
- `node_filesystem_avail_bytes` - Available disk space
- `node_network_receive_bytes_total` - Network RX bytes
- `node_load1`, `node_load5`, `node_load15` - System load averages

### Container Metrics (cAdvisor)
- `container_cpu_usage_seconds_total` - Container CPU usage
- `container_memory_usage_bytes` - Container memory usage
- `container_network_receive_bytes_total` - Container network RX
- `container_fs_usage_bytes` - Container filesystem usage

## Security Considerations

**Default Credentials (MUST CHANGE IN PRODUCTION):**
- Grafana admin: `admin / bingogo1`
- n8n admin: `admin / bingogo1`
- n8n database: Set via `N8N_DB_PASSWORD` environment variable

**Network Security:**
- Internal services isolated on `grafana-monitoring-net` network
- External access via `traefik-public` with SSL termination
- All `*.jclee.me` domains use CloudFlare SSL certificates

**Access URLs:**
- Grafana: https://grafana.jclee.me
- Prometheus: https://prometheus.jclee.me
- Loki: https://loki.jclee.me
- AlertManager: https://alertmanager.jclee.me
- n8n: https://n8n.jclee.me

## Important Notes

1. **Remote-Only Deployment**: This stack runs on Synology NAS (192.168.50.215), not local machine
2. **SSH Required**: All management operations require SSH access
3. **Container Names**: Always use full container names (e.g., `prometheus-container:9090`) in configs
4. **Volume Permissions**: Critical to run `create-volume-structure.sh` before first deployment
5. **Loki Retention**: Logs older than 3 days are automatically rejected
6. **Prometheus Retention**: Metrics retained for 30 days by default
7. **Grafana Provisioning**: Datasources and dashboards auto-load, don't create manually in UI
8. **n8n Dependencies**: Requires PostgreSQL and Redis, both monitored via exporters
