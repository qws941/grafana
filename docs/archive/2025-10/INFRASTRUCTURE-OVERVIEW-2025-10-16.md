# Infrastructure Overview

**Date**: 2025-10-16  
**Purpose**: Complete infrastructure architecture documentation

## 1. NFS Mount Architecture ✅

```
Local Machine (192.168.50.100)          Synology NAS (192.168.50.215)
─────────────────────────────────       ──────────────────────────────
/home/jclee/app/grafana/ ◄──NFS─────►  /volume1/grafana/
├── configs/                            ├── configs/ (SAME STORAGE!)
├── scripts/                            ├── scripts/
├── docs/                               ├── docs/
└── data/                               └── data/
```

**Key Point**: Local and NAS directories are **THE SAME physical storage** via NFS mount.

**NFS Mount Details**:
```bash
192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs
Options: rw, noatime, vers=3, proto=tcp, hard
```

**Implications**:
- ✅ Edit local file → Immediately reflected on NAS
- ✅ No rsync needed (already same storage)
- ✅ Real-time synchronization
- ⚠️ NFS must be mounted for files to be accessible

**Verification**:
```bash
mount | grep grafana
# Should show: 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana
```

## 2. Docker Context Architecture ✅

**Active Context**: `synology` (default)

```
docker context ls
NAME         DESCRIPTION                       DOCKER ENDPOINT
default      Current DOCKER_HOST              unix:///var/run/docker.sock
local        Local Docker (localhost)         unix:///var/run/docker.sock
synology *   Remote Docker (Synology NAS)     ssh://jclee@192.168.50.215:1111
```

**Implications**:
- All `docker` commands execute on **Synology NAS**
- `docker ps` shows NAS containers, not local
- `docker compose up` deploys to NAS
- Docker images are on NAS storage

**Context Switching**:
```bash
# Run containers locally (not recommended for monitoring stack)
DOCKER_CONTEXT=local docker compose up

# Run on Synology (default)
docker compose up  # Uses synology context
```

## 3. Service Execution Mapping

### Services on Synology NAS (Docker Context: synology)

All monitoring stack containers run on NAS:

```
Container Name              Port   Status      Uptime
────────────────────────────────────────────────────────
grafana-container           3000   Up          23 hours
prometheus-container        9090   Up          36 hours
loki-container              3100   Up          36 hours
alertmanager-container      9093   Up          36 hours
node-exporter-container     9100   Up          36 hours
cadvisor-container          8080   Up          36 hours
promtail-container          -      Up          36 hours
```

**Access URLs**:
- Grafana: https://grafana.jclee.me
- Prometheus: https://prometheus.jclee.me
- Loki: https://loki.jclee.me
- AlertManager: https://alertmanager.jclee.me

### Services on Local Machine (192.168.50.100)

```
Process                     Port   PID        Purpose
────────────────────────────────────────────────────────
ai-metrics-exporter         9091   385192     Mock AI metrics for testing
```

**Why Local?**:
- Testing/development metrics generator
- Prometheus (NAS) scrapes from 192.168.50.100:9091
- Easy to restart/modify during testing

## 4. Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Data Flow: AI Metrics Collection                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Local (192.168.50.100)          Synology NAS               │
│  ───────────────────────         ────────────               │
│                                                              │
│  ai-metrics-exporter:9091                                   │
│  └─> Generates mock metrics                                 │
│       ├─> mcp_ai_requests_total                             │
│       ├─> mcp_ai_tokens_total                               │
│       ├─> mcp_ai_cost_usd_total                             │
│       └─> mcp_ai_request_duration_seconds                   │
│            │                                                 │
│            │ HTTP GET /metrics                              │
│            │ (every 15 seconds)                             │
│            ▼                                                 │
│       prometheus-container:9090                             │
│       └─> Scrapes metrics                                   │
│            └─> Stores time series                           │
│                 └─> Evaluates recording rules               │
│                      └─> grafana-container:3000             │
│                           └─> Displays dashboard            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Scrape Configuration** (`configs/prometheus.yml`):
```yaml
- job_name: 'ai-agents'
  static_configs:
    - targets: ['192.168.50.100:9091']
  scrape_interval: 15s
```

## 5. Configuration File Management

### Edit Locally (NFS Mount)

```bash
# Edit on local machine
vim /home/jclee/app/grafana/configs/prometheus.yml

# Immediately reflected on NAS (NFS)
# No sync needed!

# Reload Prometheus to apply changes
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' \
  -qO- http://localhost:9090/-/reload"
```

### Path Equivalence

```
LOCAL                                          NAS
───────────────────────────────────────────────────────────────────
/home/jclee/app/grafana/configs/        =      /volume1/grafana/configs/
/home/jclee/app/grafana/scripts/        =      /volume1/grafana/scripts/
/home/jclee/app/grafana/docs/           =      /volume1/grafana/docs/

SAME PHYSICAL STORAGE via NFS!
```

### Why rsync Was Used (Mistakenly)

**Issue**: rsync was used during setup, but it's **redundant**

```bash
# This is UNNECESSARY because of NFS mount
rsync -avz configs/ jclee@192.168.50.215:/volume1/grafana/configs/

# Files are already the same! Just need to reload services
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' \
  -qO- http://localhost:9090/-/reload"
```

**Why it appeared to work**:
- Rsync completes successfully (no-op, files identical)
- Then Prometheus reload picks up changes
- But the reload was the key, not rsync!

## 6. Deployment Workflow

### Standard Deployment Process

```bash
# 1. Edit configuration locally
vim configs/prometheus.yml

# 2. Verify NFS mount is active
mount | grep grafana

# 3. Reload service (NAS)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' \
  -qO- http://localhost:9090/-/reload"

# 4. Verify changes
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | .labels.job'
```

### Dashboard Provisioning

```bash
# 1. Create/edit dashboard JSON
vim configs/provisioning/dashboards/applications/my-dashboard.json

# 2. Wait 10 seconds (Grafana auto-scan interval)
sleep 10

# 3. Verify dashboard loaded
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  'http://localhost:3000/api/dashboards/uid/my-dashboard'" | \
  jq '.dashboard.title'
```

## 7. Current Status (2025-10-16) ✅

### AI Cost Dashboard Status

```
Component                Status      Details
─────────────────────────────────────────────────────────────
AI Metrics Exporter      ✅ Running   PID 385192, Port 9091
Prometheus Target        ✅ UP        15s scrape interval
Metrics Collected        ✅ 60 series Grok, Gemini, Claude
Request Rate             ✅ 88.4/min  Mock traffic generation
Dashboard                ✅ Active    22 panels, 5 sections
Recording Rules          ✅ Loaded    9 rules in ai_cost_recording_rules
```

**Dashboard URL**: https://grafana.jclee.me/d/ai-agent-costs-reds

### Health Checks

```bash
# Exporter health
curl http://localhost:9091/health
# {"status":"healthy","uptime":xxx}

# Prometheus target
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/targets'" | \
  jq '.data.activeTargets[] | select(.labels.job=="ai-agents") | .health'
# "up"

# Dashboard loaded
curl -s -u admin:bingogo1 https://grafana.jclee.me/api/dashboards/uid/ai-agent-costs-reds | \
  jq '.dashboard.title'
# "AI Agent Costs (REDS)"
```

## 8. Key Takeaways

### Do's ✅

1. **Edit files locally** - NFS mount ensures instant NAS reflection
2. **Reload services after config changes** - Prometheus, Grafana need explicit reload
3. **Use Docker context** - `docker ps` shows NAS containers (synology context active)
4. **Check NFS mount** - `mount | grep grafana` should always show mounted
5. **Wait for provisioning** - Grafana scans dashboards every 10 seconds

### Don'ts ❌

1. **Don't use rsync** - Files are already synced via NFS
2. **Don't edit on NAS** - Edit locally instead (same result, easier)
3. **Don't forget reload** - Config changes need service reload to take effect
4. **Don't assume immediate** - Dashboard provisioning takes ~10 seconds
5. **Don't run monitoring stack locally** - Use centralized NAS stack

## 9. Troubleshooting

### NFS Mount Lost

**Symptom**: Files not accessible, or `/home/jclee/app/grafana` empty

**Fix**:
```bash
# Remount NFS
sudo mount 192.168.50.215:/volume1/grafana /home/jclee/app/grafana

# Or check /etc/fstab for auto-mount on boot
```

### Prometheus Not Scraping Local Exporter

**Symptom**: Target DOWN in Prometheus

**Checks**:
```bash
# 1. Exporter running?
curl http://localhost:9091/health

# 2. Firewall allowing 9091?
sudo firewall-cmd --list-ports | grep 9091

# 3. Prometheus config correct?
cat configs/prometheus.yml | grep -A5 ai-agents

# 4. Reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' \
  -qO- http://localhost:9090/-/reload"
```

### Dashboard Not Loading

**Symptom**: Dashboard UID not found in Grafana

**Checks**:
```bash
# 1. File exists on NAS?
ssh -p 1111 jclee@192.168.50.215 \
  "ls -lh /volume1/grafana/configs/provisioning/dashboards/applications/*.json"

# 2. Valid JSON?
jq . configs/provisioning/dashboards/applications/ai-agent-costs-reds.json

# 3. Correct folder?
# Must be in: configs/provisioning/dashboards/applications/
# NOT in: configs/provisioning/dashboards/ (root)

# 4. Wait 10 seconds for Grafana scan
sleep 10

# 5. Check Grafana logs
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs grafana-container --tail 50" | grep -i provision
```

## 10. Architecture Diagrams

### Network Topology

```
Internet
   │
   ├─> CloudFlare (DNS + SSL)
   │    ├─> grafana.jclee.me
   │    ├─> prometheus.jclee.me
   │    └─> loki.jclee.me
   │
   ▼
Synology NAS (192.168.50.215:1111)
   ├─> traefik-public (reverse proxy network)
   │    ├─> Grafana (3000)
   │    ├─> Prometheus (9090)
   │    └─> Loki (3100)
   │
   └─> grafana-monitoring-net (internal network)
        ├─> node-exporter (9100)
        ├─> cadvisor (8080)
        ├─> promtail (scrapes docker logs)
        └─> alertmanager (9093)

Local Dev Machine (192.168.50.100)
   ├─> NFS Mount: /home/jclee/app/grafana → NAS:/volume1/grafana
   ├─> ai-metrics-exporter (9091) ──scrape──► Prometheus (NAS)
   └─> Docker Context: synology (SSH to NAS)
```

### File System Layout

```
/home/jclee/app/grafana/  (NFS mounted from NAS)
├── configs/
│   ├── prometheus.yml                  # Prometheus config
│   ├── recording-rules.yml             # Recording rules
│   ├── alert-rules.yml                 # Alert rules
│   ├── promtail-config.yml             # Promtail config
│   └── provisioning/
│       ├── datasources/
│       │   └── datasource.yml          # Prometheus, Loki, AlertManager
│       └── dashboards/
│           ├── dashboard.yml           # Provisioning config
│           ├── applications/           # Application dashboards
│           │   ├── n8n-workflow-automation-reds.json
│           │   └── ai-agent-costs-reds.json
│           ├── core-monitoring/        # Stack self-monitoring
│           ├── infrastructure/         # System metrics
│           ├── logging/                # Log analysis
│           └── alerting/               # Alert dashboards
│
├── scripts/
│   ├── ai-metrics-exporter/            # AI metrics test generator
│   │   ├── package.json
│   │   ├── index.js
│   │   └── exporter.log
│   ├── health-check.sh                 # Health check script
│   ├── validate-metrics.sh             # Metrics validation
│   └── lib/
│       └── common.sh                   # Shared library
│
├── docs/
│   ├── AI-METRICS-SPECIFICATION.md
│   ├── AI-COST-DASHBOARD-IMPLEMENTATION-GUIDE.md
│   ├── INFRASTRUCTURE-OVERVIEW-2025-10-16.md
│   ├── IMPROVEMENTS-2025-10-14.md
│   └── GRAFANA-BEST-PRACTICES-2025.md
│
└── docker-compose.yml                  # Stack definition
```

## References

- NFS Protocol: RFC 1813 (NFSv3)
- Docker Context: https://docs.docker.com/engine/context/working-with-contexts/
- Prometheus Remote Storage: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write
- Grafana Provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
