# Deployment Guide

## Prerequisites

### Local Development Machine

**Required**:
- Rocky Linux 9 (or compatible RHEL-based)
- SSH client with key-based authentication
- rsync installed
- Docker CLI (for remote operations)
- jq (for JSON parsing)

**Network Access**:
- SSH access to Synology NAS (192.168.50.215:1111)
- Internet connection for Docker image pulls
- Access to CloudFlare DNS (for domain verification)

### Synology NAS

**Required**:
- Synology DSM 7.x
- Docker package installed
- Minimum 4GB RAM (8GB recommended)
- 50GB free disk space (for data volumes)

**Network Configuration**:
- Traefik reverse proxy running
- traefik-public network created
- CloudFlare integration configured
- Ports: 3000, 9090, 3100, 9093 (internal only)

---

## Initial Setup

### Step 1: Clone Repository

```bash
cd /home/jclee/app
git clone https://github.com/your-org/grafana-monitoring.git grafana
cd grafana
```

### Step 2: Configure Environment Variables

```bash
# Copy environment template
cp .env.example .env

# Edit with actual values
vim .env
```

**Required Variables**:
```bash
# Security
GRAFANA_ADMIN_PASSWORD=<strong-password>

# Service Versions (use specific versions, not :latest)
GRAFANA_VERSION=10.2.3
PROMETHEUS_VERSION=v2.48.1
LOKI_VERSION=2.9.3
PROMTAIL_VERSION=2.9.3
ALERTMANAGER_VERSION=v0.26.0
NODE_EXPORTER_VERSION=v1.7.0
CADVISOR_VERSION=v0.47.2

# Domains
GRAFANA_DOMAIN=grafana.jclee.me
PROMETHEUS_DOMAIN=prometheus.jclee.me
LOKI_DOMAIN=loki.jclee.me
ALERTMANAGER_DOMAIN=alertmanager.jclee.me

# Storage Paths (Synology NAS)
GRAFANA_DATA_PATH=/volume1/grafana/data/grafana
PROMETHEUS_DATA_PATH=/volume1/grafana/data/prometheus
LOKI_DATA_PATH=/volume1/grafana/data/loki
ALERTMANAGER_DATA_PATH=/volume1/grafana/data/alertmanager
CONFIGS_PATH=/volume1/grafana/configs

# Prometheus Settings
PROMETHEUS_RETENTION_TIME=30d

# Network
MONITORING_NETWORK=grafana-monitoring-net
```

### Step 3: Create Volume Structure on NAS

**Connect to Synology NAS**:
```bash
ssh -p 1111 jclee@192.168.50.215
```

**Create directories with proper permissions**:
```bash
sudo mkdir -p /volume1/grafana/data/{grafana,prometheus,loki,alertmanager}
sudo mkdir -p /volume1/grafana/configs

# Set ownership (critical!)
sudo chown -R 472:472 /volume1/grafana/data/grafana     # Grafana
sudo chown -R 65534:65534 /volume1/grafana/data/prometheus  # Prometheus
sudo chown -R 10001:10001 /volume1/grafana/data/loki    # Loki
sudo chown -R 65534:65534 /volume1/grafana/data/alertmanager  # AlertManager
```

**Or use provided script**:
```bash
# From local machine
scp -P 1111 scripts/create-volume-structure.sh jclee@192.168.50.215:/tmp/
ssh -p 1111 jclee@192.168.50.215 "bash /tmp/create-volume-structure.sh"
```

### Step 4: Setup Real-time Sync Service

**Install systemd service**:
```bash
./scripts/start-sync-service.sh
```

**Verify sync service running**:
```bash
sudo systemctl status grafana-sync
sudo journalctl -u grafana-sync -f
```

**Expected output**:
```
● grafana-sync.service - Grafana Config Real-time Sync
     Loaded: loaded (/etc/systemd/system/grafana-sync.service; enabled)
     Active: active (running) since Thu 2025-10-17 08:00:00 KST
   Main PID: 12345 (node)
```

### Step 5: Initial Configuration Sync

```bash
# Sync configs to NAS
./scripts/sync-to-synology.sh

# Verify files on NAS
ssh -p 1111 jclee@192.168.50.215 "ls -la /volume1/grafana/configs/"
```

### Step 6: Validate Configurations

**Validate docker-compose.yml**:
```bash
docker compose config
```

**Validate YAML configs**:
```bash
yamllint configs/*.yml configs/*.yaml
```

**Validate shell scripts**:
```bash
shellcheck scripts/*.sh
```

### Step 7: Deploy Services

**SSH to Synology NAS**:
```bash
ssh -p 1111 jclee@192.168.50.215
cd /volume1/grafana
```

**Deploy services**:
```bash
docker compose up -d
```

**Expected output**:
```
[+] Running 8/8
 ✔ Network grafana-monitoring-net          Created
 ✔ Container grafana-container             Started
 ✔ Container prometheus-container          Started
 ✔ Container loki-container                 Started
 ✔ Container alertmanager-container         Started
 ✔ Container promtail-container             Started
 ✔ Container node-exporter-container        Started
 ✔ Container cadvisor-container             Started
```

### Step 8: Verify Deployment

**Check container status**:
```bash
docker ps | grep -E 'grafana|prometheus|loki'
```

**Expected output**:
```
CONTAINER ID   IMAGE                              STATUS         PORTS
abc123         grafana/grafana:10.2.3             Up 2 minutes   healthy
def456         prom/prometheus:v2.48.1            Up 2 minutes   healthy
ghi789         grafana/loki:2.9.3                 Up 2 minutes   healthy
```

**Run health check**:
```bash
# From local machine
./scripts/health-check.sh
```

**Expected output**:
```
╔═══════════════════════════════════════════╗
║   Grafana Monitoring Stack - Utilities   ║
╚═══════════════════════════════════════════╝

[INFO] Checking health of 4 services...

✅ Grafana: OK
✅ Prometheus: OK
✅ Loki: OK
✅ AlertManager: OK

[INFO] Results: 4/4 services healthy
[SUCCESS] All services are healthy!
```

### Step 9: Access Services

**Web UIs**:
- Grafana: https://grafana.jclee.me (admin / [password from .env])
- Prometheus: https://prometheus.jclee.me
- Loki: https://loki.jclee.me
- AlertManager: https://alertmanager.jclee.me

**Verify Grafana**:
1. Login to Grafana
2. Navigate to Configuration → Data Sources
3. Verify Prometheus and Loki datasources exist
4. Navigate to Dashboards → Browse
5. Verify 12 dashboards loaded (5 folders)

**Verify Prometheus**:
1. Navigate to https://prometheus.jclee.me/targets
2. Verify all targets are UP (green)
3. Navigate to https://prometheus.jclee.me/rules
4. Verify recording rules and alert rules loaded

---

## Configuration Changes

### Workflow for Configuration Updates

```
┌─────────────────────────────────────────────────────────┐
│ Configuration Change Workflow                           │
├─────────────────────────────────────────────────────────┤
│ 1. Edit config locally (e.g., configs/prometheus.yml)   │
│ 2. Wait 1-2 seconds (auto-sync via grafana-sync)       │
│ 3. Verify sync: sudo journalctl -u grafana-sync -n 5   │
│ 4. Reload service (if hot reload supported)             │
│ 5. Verify change applied                                │
└─────────────────────────────────────────────────────────┘
```

### Prometheus Configuration Changes

**Example: Add new scrape target**

1. **Edit configs/prometheus.yml**:
```yaml
scrape_configs:
  - job_name: 'my-new-service'
    static_configs:
      - targets: ['my-service-container:8080']
    metrics_path: '/metrics'
```

2. **Wait for auto-sync** (1-2 seconds)

3. **Reload Prometheus**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

4. **Verify target**:
```bash
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job == "my-new-service")'
```

### Grafana Dashboard Changes

**Example: Update dashboard**

1. **Edit dashboard JSON** (e.g., `configs/provisioning/dashboards/core-monitoring/01-monitoring-stack-health.json`)

2. **Wait for auto-sync** (1-2 seconds) + Grafana auto-provision (10 seconds)
   - Total latency: **11-12 seconds**

3. **Verify dashboard updated**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  'http://localhost:3000/api/dashboards/uid/monitoring-stack-health'" | \
  jq '.dashboard.title'
```

4. **Refresh Grafana browser** (Ctrl+Shift+R)

### Loki Configuration Changes

**Example: Change retention period**

1. **Edit configs/loki-config.yaml**:
```yaml
limits_config:
  retention_period: 7d  # Changed from 3d
```

2. **Wait for auto-sync** (1-2 seconds)

3. **Restart Loki** (no hot reload):
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker restart loki-container"
```

4. **Verify Loki healthy**:
```bash
curl -sf https://loki.jclee.me/ready
```

### AlertManager Configuration Changes

**Example: Add new webhook receiver**

1. **Edit configs/alertmanager.yml**:
```yaml
receivers:
  - name: 'default'
    webhook_configs:
      - url: 'https://n8n.jclee.me/webhook/alertmanager'
      - url: 'https://slack.example.com/webhook/alerts'  # New
```

2. **Wait for auto-sync** (1-2 seconds)

3. **Restart AlertManager** (no hot reload):
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker restart alertmanager-container"
```

4. **Test alert**:
```bash
# Trigger test alert
curl -H "Content-Type: application/json" -d '[{
  "labels": {"alertname": "TestAlert", "severity": "info"},
  "annotations": {"summary": "Test alert"}
}]' https://alertmanager.jclee.me/api/v2/alerts
```

---

## Updating Services

### Update Docker Images

**Check for updates**:
```bash
# Check current versions
ssh -p 1111 jclee@192.168.50.215 "docker images | grep -E 'grafana|prometheus|loki'"
```

**Update procedure**:

1. **Update .env versions**:
```bash
vim .env
# Update version numbers
GRAFANA_VERSION=10.3.0  # Example update
```

2. **Sync to NAS**:
```bash
# Auto-synced by grafana-sync service
# Or manual: ./scripts/sync-to-synology.sh
```

3. **Pull new images**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose pull"
```

4. **Recreate containers**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose up -d"
```

5. **Verify health**:
```bash
./scripts/health-check.sh
```

### Zero-downtime Updates (Future)

**Not currently implemented** - All services restart during updates

**Future implementation**:
- Grafana HA: Multiple instances behind load balancer
- Prometheus: Federation with rolling updates
- Loki: Distributed mode with ingester/querier separation

---

## Rollback Procedures

### Rollback Configuration Changes

**Scenario**: Configuration change caused service failure

**Rollback steps**:

1. **Identify last working commit**:
```bash
git log --oneline configs/
```

2. **Revert changes**:
```bash
git revert <commit-hash>
# Or manual: git checkout <commit-hash> -- configs/
```

3. **Wait for auto-sync** (1-2 seconds)

4. **Reload/restart service**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

5. **Verify health**:
```bash
./scripts/health-check.sh
```

### Rollback Docker Image Updates

**Scenario**: New Docker image version causing issues

**Rollback steps**:

1. **Update .env to previous version**:
```bash
vim .env
# Revert version numbers
GRAFANA_VERSION=10.2.3  # Previous version
```

2. **Sync to NAS** (auto-synced)

3. **Recreate containers**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose up -d --force-recreate"
```

4. **Verify health**:
```bash
./scripts/health-check.sh
```

### Complete System Rollback

**Scenario**: Multiple failures, need to restore from backup

**Rollback steps**:

1. **Stop all services**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose down"
```

2. **Restore configurations from git**:
```bash
git checkout <stable-commit-hash>
./scripts/sync-to-synology.sh
```

3. **Restore data volumes** (if needed):
```bash
# Restore Grafana data (dashboards, users)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo rsync -av /volume1/grafana/backups/grafana-data-20251017/ /volume1/grafana/data/grafana/"
```

4. **Restart services**:
```bash
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose up -d"
```

5. **Verify health**:
```bash
./scripts/health-check.sh
```

---

## Monitoring Deployment

### Health Checks

**Automated checks**:
```bash
# Run health check script
./scripts/health-check.sh

# Check specific service
curl -sf https://grafana.jclee.me/api/health
```

**Manual verification**:
```bash
# Check Prometheus targets
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check Loki ingestion
curl -s --get \
  --data-urlencode 'query=rate({job=~".+"}[5m])' \
  https://loki.jclee.me/loki/api/v1/query | \
  jq '.data.result | length'

# Check AlertManager alerts
curl -s https://alertmanager.jclee.me/api/v2/alerts | \
  jq 'length'
```

### Container Logs

**View logs**:
```bash
# Real-time logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs -f grafana-container"

# Last 50 lines
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs grafana-container --tail 50"

# All services
ssh -p 1111 jclee@192.168.50.215 "sudo docker compose logs --tail 20"
```

**Search logs**:
```bash
# Search for errors
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs prometheus-container 2>&1 | grep -i error"
```

### Metrics Validation

**Validate metrics exist before deployment**:
```bash
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/applications/my-dashboard.json
```

**List all available metrics**:
```bash
./scripts/validate-metrics.sh --list | grep n8n
```

---

## Troubleshooting Deployment

### Common Issues

#### Services won't start

**Symptom**: `docker compose up -d` fails or containers exit immediately

**Diagnosis**:
```bash
# Check container logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs grafana-container"

# Check docker-compose config
docker compose config
```

**Common causes**:
1. **Volume permission issues** → Run `scripts/create-volume-structure.sh`
2. **Port conflicts** → Check `docker ps` for conflicting containers
3. **Configuration errors** → Validate with `yamllint`
4. **Missing environment variables** → Check `.env` file

#### Real-time sync not working

**Symptom**: Config changes not syncing to NAS

**Diagnosis**:
```bash
# Check sync service
sudo systemctl status grafana-sync
sudo journalctl -u grafana-sync -n 50

# Test manual sync
./scripts/sync-to-synology.sh
```

**Fix**:
```bash
# Restart sync service
sudo systemctl restart grafana-sync

# Verify SSH connection
ssh -p 1111 jclee@192.168.50.215 "echo 'Connection OK'"
```

#### Traefik routing issues

**Symptom**: Services not accessible via domain names

**Diagnosis**:
```bash
# Check Traefik logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs traefik | grep grafana"

# Verify traefik-public network
ssh -p 1111 jclee@192.168.50.215 "docker network inspect traefik-public"
```

**Fix**:
1. Verify Traefik labels in docker-compose.yml
2. Check DNS resolution: `dig grafana.jclee.me`
3. Verify SSL certificates: `curl -vI https://grafana.jclee.me`

#### Dashboard "No Data" panels

**Symptom**: Dashboard panels show "No Data"

**Diagnosis**:
```bash
# Validate metrics exist
./scripts/validate-metrics.sh -d <dashboard-file>

# Test query manually
curl -s "https://prometheus.jclee.me/api/v1/query?query=<metric-name>" | jq '.'
```

**Fix**:
1. Verify metric exists: `/api/v1/label/__name__/values`
2. Check Prometheus targets: `/api/v1/targets`
3. Validate datasource UID in dashboard JSON
4. Use validated metrics only (learned from 2025-10-13 incident)

---

## Security Considerations

### Pre-deployment Security Checklist

- [ ] Strong Grafana admin password set in `.env`
- [ ] `.env` file gitignored (never committed)
- [ ] SSH key-based authentication configured
- [ ] Firewall rules configured (only ports 22/1111 open externally)
- [ ] SSL certificates valid (CloudFlare)
- [ ] No hardcoded secrets in configurations
- [ ] Read-only volume mounts for configs (`:ro` flag)
- [ ] Prometheus/Loki/AlertManager on internal network only

### Post-deployment Security Validation

```bash
# Verify no hardcoded secrets
grep -r "password\|secret\|token" configs/ scripts/ | grep -v "VARIABLE"

# Check SSL certificates
curl -vI https://grafana.jclee.me 2>&1 | grep "SSL certificate"

# Verify internal network isolation
ssh -p 1111 jclee@192.168.50.215 \
  "docker network inspect grafana-monitoring-net" | jq '.[] | .Containers'
```

---

## Backup and Restore

### Backup Procedure

**What to backup**:
1. Grafana data: `/volume1/grafana/data/grafana` (dashboards, users, settings)
2. Configurations: Already in git (configs/)
3. Prometheus data: Optional (30-day retention)

**Backup script**:
```bash
./scripts/backup.sh
```

**Manual backup**:
```bash
ssh -p 1111 jclee@192.168.50.215 "
  tar -czf /volume1/backups/grafana-backup-\$(date +%Y%m%d).tar.gz \
    /volume1/grafana/data/grafana \
    /volume1/grafana/configs
"
```

### Restore Procedure

**Restore from backup**:
```bash
# Stop services
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose down"

# Restore Grafana data
ssh -p 1111 jclee@192.168.50.215 "
  sudo rm -rf /volume1/grafana/data/grafana/*
  sudo tar -xzf /volume1/backups/grafana-backup-20251017.tar.gz -C /
  sudo chown -R 472:472 /volume1/grafana/data/grafana
"

# Restore configs (from git)
git checkout <stable-commit>
./scripts/sync-to-synology.sh

# Restart services
ssh -p 1111 jclee@192.168.50.215 "cd /volume1/grafana && docker compose up -d"

# Verify
./scripts/health-check.sh
```

---

## Scaling Considerations

### Current Limitations

- **Single NAS**: No redundancy or failover
- **No horizontal scaling**: All services on one machine
- **Limited resources**: Shared NAS CPU/memory with other services

### Future Scaling Options

**Horizontal Scaling**:
1. **Prometheus Federation**: Multiple Prometheus instances scraping different targets
2. **Loki Distributed Mode**: Separate ingester, querier, compactor
3. **Grafana HA**: Multiple Grafana instances behind load balancer

**Vertical Scaling**:
1. Increase NAS resources (CPU, memory, disk)
2. Optimize retention policies (reduce data volume)
3. Use recording rules (reduce query load)

---

## Additional Resources

- docs/OPERATIONAL-RUNBOOK.md - Day-to-day operations
- resume/architecture.md - System architecture
- resume/troubleshooting.md - Incident response
- scripts/health-check.sh - Automated health checks
- scripts/validate-metrics.sh - Metrics validation

---

**Last Updated**: 2025-10-17
**Deployment Version**: 1.0
**Maintainer**: DevOps Team
