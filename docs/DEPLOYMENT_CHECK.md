# 🚀 n8n Integrated Monitoring Stack - Deployment Verification Guide

Complete verification checklist for the n8n-integrated Grafana monitoring stack deployment on Synology NAS.

---

## 📦 Deployed Configuration

### Services Overview (12 Containers)

**Monitoring Stack (7 containers)**:
1. `grafana-container` - Visualization and dashboards (port 3000)
2. `prometheus-container` - Metrics collection (port 9090)
3. `loki-container` - Log aggregation (port 3100)
4. `promtail-container` - Log forwarder
5. `alertmanager-container` - Alert routing (port 9093)
6. `node-exporter-container` - System metrics (port 9100)
7. `cadvisor-container` - Container metrics (port 8080)

**n8n Workflow Automation Stack (5 containers)**:
8. `n8n-container` - Workflow automation engine (port 5678)
9. `n8n-postgres-container` - n8n database backend (port 5432)
10. `n8n-redis-container` - n8n queue system (port 6379)
11. `n8n-postgres-exporter-container` - PostgreSQL metrics (port 9187)
12. `n8n-redis-exporter-container` - Redis metrics (port 9121)

### Configuration File Mappings

**Volume Mounts (Synology NAS)**:
```
✅ grafana       → /volume1/grafana/configs/provisioning/
✅ prometheus    → /volume1/grafana/configs/prometheus.yml (includes n8n scrape targets)
✅ loki          → /volume1/grafana/configs/loki-config.yaml
✅ promtail      → /volume1/grafana/configs/promtail-config.yml
✅ alertmanager  → /volume1/grafana/configs/alertmanager.yml
```

**Scrape Targets (Prometheus)**:
- n8n main service: `n8n.jclee.me:5678/metrics`
- n8n PostgreSQL: `n8n-postgres-exporter:9187/metrics`
- n8n Redis: `n8n-redis-exporter:9121/metrics`

---

## 🔍 Deployment Status Verification

### 1. Container Execution Check

**Check all containers are running**:
```bash
# SSH to Synology NAS
ssh -p 1111 jclee@192.168.50.215

# Check all containers
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Expected Output**: All 12 containers in `Up` status with health checks passing

**Container Health Status**:
```bash
# Check specific container health
sudo docker inspect grafana-container | jq '.[0].State.Health.Status'
sudo docker inspect prometheus-container | jq '.[0].State.Health.Status'
sudo docker inspect n8n-container | jq '.[0].State.Health.Status'
```

**Expected**: All return `"healthy"`

### 2. n8n Web Access Verification

**HTTP Status Check**:
```bash
# From local machine
curl -I https://n8n.jclee.me
```

**Expected**: HTTP 200 or 302 (redirect to login)

**Browser Access**:
```
https://n8n.jclee.me
```

**Expected**: n8n login page or dashboard (if authenticated)

**Health Endpoint**:
```bash
curl https://n8n.jclee.me/healthz
```

**Expected**: `{"status":"ok"}` or HTTP 200

### 3. Prometheus n8n Target Verification

**Check n8n targets are UP**:
```bash
# Query Prometheus API for n8n targets
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | contains("n8n")) | {job: .labels.job, health: .health, lastScrape: .lastScrape}'
```

**Expected Output**:
```json
{"job": "n8n", "health": "up", "lastScrape": "2025-10-17T12:34:56.789Z"}
{"job": "n8n-postgres", "health": "up", "lastScrape": "2025-10-17T12:34:56.789Z"}
{"job": "n8n-redis", "health": "up", "lastScrape": "2025-10-17T12:34:56.789Z"}
```

**Web UI Verification**:
```
https://prometheus.jclee.me/targets
→ Search for "n8n" → All targets should be "UP"
```

---

## 📊 Log Collection Verification

### 1. Loki n8n Log Stream Check

**List all log streams**:
```bash
# Query Loki for available log streams
curl -s -G https://loki.jclee.me/loki/api/v1/label/__name__/values | jq '.'
```

**Query n8n logs specifically**:
```bash
# Get recent n8n logs
curl -s -G "https://loki.jclee.me/loki/api/v1/query" \
  --data-urlencode 'query={container_name="n8n-container"}' \
  --data-urlencode 'limit=10' | \
  jq '.data.result'
```

**Expected**: n8n container log streams with recent entries

**LogQL Query Examples**:
```bash
# n8n startup logs
curl -s -G "https://loki.jclee.me/loki/api/v1/query_range" \
  --data-urlencode 'query={container_name="n8n-container"} |= "started"' \
  --data-urlencode 'limit=5' | \
  jq '.data.result[0].values'

# n8n workflow execution logs
curl -s -G "https://loki.jclee.me/loki/api/v1/query_range" \
  --data-urlencode 'query={container_name="n8n-container"} |= "workflow"' \
  --data-urlencode 'limit=5' | \
  jq '.data.result[0].values'
```

### 2. Promtail Collection Status Check

**Check Promtail is discovering n8n containers**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs promtail-container --tail 50 | grep -i n8n"
```

**Expected**: Log parsing messages for n8n containers

**Promtail Metrics Check**:
```bash
# Check Promtail internal metrics
curl -s https://prometheus.jclee.me/api/v1/query?query=promtail_targets_active_total | \
  jq '.data.result[0].value'
```

**Expected**: Number of active targets (should include n8n containers)

### 3. Grafana Explore Log Verification

**Web UI Steps**:
1. Navigate to https://grafana.jclee.me
2. Login with admin credentials
3. Left menu → **Explore**
4. Data source: Select **Loki**
5. Query: `{container_name="n8n-container"}`
6. Click **Run query**

**Expected**: Real-time n8n container logs displayed with timestamps

**Alternative Queries**:
```logql
# All n8n-related logs
{job=~"n8n.*"}

# n8n error logs only
{container_name="n8n-container"} |= "error" or "ERROR"

# n8n workflow execution logs
{container_name="n8n-container"} |= "workflow"
```

---

## 📈 Metrics Collection Verification

### 1. Prometheus n8n Metrics Query

**Check n8n application metrics exist**:
```bash
# n8n workflow execution metrics
curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_workflow_executions_total" | \
  jq '.data.result'

# n8n active workflow count
curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_active_workflow_count" | \
  jq '.data.result'

# n8n execution duration (P99)
curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_nodejs_eventloop_lag_p99_seconds" | \
  jq '.data.result'
```

**Expected**: Each metric returns value array (may be empty if no workflows executed yet)

**PostgreSQL Metrics**:
```bash
# PostgreSQL connection status
curl -s "https://prometheus.jclee.me/api/v1/query?query=pg_up" | \
  jq '.data.result'

# PostgreSQL active connections
curl -s "https://prometheus.jclee.me/api/v1/query?query=pg_stat_activity_count" | \
  jq '.data.result'
```

**Redis Metrics**:
```bash
# Redis connection status
curl -s "https://prometheus.jclee.me/api/v1/query?query=redis_up" | \
  jq '.data.result'

# Redis memory usage
curl -s "https://prometheus.jclee.me/api/v1/query?query=redis_memory_used_bytes" | \
  jq '.data.result'
```

### 2. n8n Metrics Endpoint Direct Check

**Verify metrics endpoint is accessible**:
```bash
# From inside n8n container
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec n8n-container curl -s http://localhost:5678/metrics" | \
  grep "n8n_"
```

**Expected Output** (sample):
```
# HELP n8n_workflow_executions_total Total number of workflow executions
# TYPE n8n_workflow_executions_total counter
n8n_workflow_executions_total{status="success"} 42
n8n_workflow_executions_total{status="failed"} 3

# HELP n8n_active_workflow_count Number of active workflows
# TYPE n8n_active_workflow_count gauge
n8n_active_workflow_count 5
```

**List all n8n metrics available**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec n8n-container curl -s http://localhost:5678/metrics" | \
  grep "^n8n_" | awk '{print $1}' | sort -u
```

### 3. Grafana Dashboard Verification

**Check n8n dashboard is loaded**:
```bash
# Query Grafana API for n8n dashboard
curl -s -u admin:bingogo1 \
  "https://grafana.jclee.me/api/dashboards/uid/n8n-workflow-automation-reds" | \
  jq '.dashboard.title'
```

**Expected**: `"n8n Workflow Automation (REDS)"`

**Web UI Verification**:
```
https://grafana.jclee.me/d/n8n-workflow-automation-reds
→ Dashboard should load with 15 panels
→ All panels should show data (no "No Data" messages)
```

---

## 🎯 Comprehensive Health Check Script

**Script**: `scripts/check-n8n-stack.sh`

```bash
#!/bin/bash
# Comprehensive n8n stack health check script
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🔍 n8n Stack Comprehensive Health Check"
echo "========================================"
echo ""

# 1. Container Status Check
echo "1️⃣  Container Status"
echo "-------------------"
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker ps --filter 'name=n8n' --format '✅ {{.Names}}: {{.Status}}'"
echo ""

# 2. n8n Web Access Check
echo "2️⃣  n8n Web Access"
echo "-----------------"
if curl -f -s https://n8n.jclee.me/healthz > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n web UI accessible${NC}"
else
    echo -e "${RED}❌ n8n web UI not accessible${NC}"
    exit 1
fi
echo ""

# 3. Prometheus Target Check
echo "3️⃣  Prometheus Targets"
echo "---------------------"
curl -s https://prometheus.jclee.me/api/v1/targets 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.job | contains("n8n")) |
    if .health == "up" then "✅ \(.labels.job): \(.health)"
    else "❌ \(.labels.job): \(.health)" end'
echo ""

# 4. Loki Log Collection Check
echo "4️⃣  Loki Log Collection"
echo "----------------------"
LOG_COUNT=$(curl -s -G "https://loki.jclee.me/loki/api/v1/query" \
  --data-urlencode 'query={container_name="n8n-container"}' \
  --data-urlencode 'limit=1' 2>/dev/null | jq '.data.result | length')

if [ "$LOG_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ n8n logs collected (${LOG_COUNT} streams)${NC}"
else
    echo -e "${YELLOW}⚠️  n8n log streams not found${NC}"
fi
echo ""

# 5. Metrics Data Check
echo "5️⃣  Metrics Data"
echo "---------------"
METRIC_COUNT=$(curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_active_workflow_count" 2>/dev/null | \
  jq '.data.result | length')

if [ "$METRIC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ n8n metrics collected (${METRIC_COUNT} time series)${NC}"
    # Show current workflow count
    WORKFLOW_COUNT=$(curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_active_workflow_count" 2>/dev/null | \
      jq -r '.data.result[0].value[1]')
    echo "   Active workflows: ${WORKFLOW_COUNT}"
else
    echo -e "${YELLOW}⚠️  n8n metrics data not found (appears after first workflow execution)${NC}"
fi
echo ""

# 6. Dashboard Check
echo "6️⃣  Grafana Dashboard"
echo "--------------------"
DASHBOARD=$(curl -s -u admin:bingogo1 \
  "https://grafana.jclee.me/api/dashboards/uid/n8n-workflow-automation-reds" 2>/dev/null | \
  jq -r '.dashboard.title')

if [ "$DASHBOARD" = "n8n Workflow Automation (REDS)" ]; then
    echo -e "${GREEN}✅ n8n dashboard loaded: $DASHBOARD${NC}"
else
    echo -e "${RED}❌ n8n dashboard not found${NC}"
fi
echo ""

echo "========================================"
echo "🎉 Health check complete!"
echo ""
echo "Access URLs:"
echo "- n8n:        https://n8n.jclee.me"
echo "- Dashboard:  https://grafana.jclee.me/d/n8n-workflow-automation-reds"
echo "- Prometheus: https://prometheus.jclee.me/targets"
```

**Usage**:
```bash
# Make executable
chmod +x scripts/check-n8n-stack.sh

# Run health check
./scripts/check-n8n-stack.sh
```

**Expected Output**:
```
🔍 n8n Stack Comprehensive Health Check
========================================

1️⃣  Container Status
-------------------
✅ n8n-container: Up 2 hours (healthy)
✅ n8n-postgres-container: Up 2 hours (healthy)
✅ n8n-redis-container: Up 2 hours (healthy)

2️⃣  n8n Web Access
-----------------
✅ n8n web UI accessible

3️⃣  Prometheus Targets
---------------------
✅ n8n: up
✅ n8n-postgres: up
✅ n8n-redis: up

4️⃣  Loki Log Collection
----------------------
✅ n8n logs collected (3 streams)

5️⃣  Metrics Data
---------------
✅ n8n metrics collected (12 time series)
   Active workflows: 5

6️⃣  Grafana Dashboard
--------------------
✅ n8n dashboard loaded: n8n Workflow Automation (REDS)

========================================
🎉 Health check complete!
```

---

## 🚨 Troubleshooting

### n8n Container Won't Start

**Check logs**:
```bash
docker context use synology
docker logs n8n-container --tail 100
```

**Common causes**:

1. **PostgreSQL connection failure**:
   ```bash
   # Check PostgreSQL container is running
   docker context use synology
   docker ps | grep postgres

   # Check PostgreSQL logs
   docker logs n8n-postgres-container

   # Test PostgreSQL connection
   docker exec n8n-postgres-container pg_isready -U n8n
   ```

2. **Redis connection failure**:
   ```bash
   # Check Redis container is running
   docker context use synology
   docker ps | grep redis

   # Test Redis connection
   docker exec n8n-redis-container redis-cli ping
   ```

3. **Environment variable errors**:
   ```bash
   # Check environment variables in container
   docker context use synology
   docker exec n8n-container env | grep N8N

   # Verify .env file using NFS mount
   cat /home/jclee/app/grafana/.env | grep N8N
   ```

4. **Port conflict**:
   ```bash
   # Check if port 5678 is already in use
   ssh -p 1111 jclee@192.168.50.215 "sudo netstat -tlnp | grep 5678"
   ```

**Fix**: Stop conflicting service or change n8n port in docker-compose.yml

### Metrics Not Being Collected

**Verify metrics endpoint is working**:
```bash
# 1. Check n8n metrics endpoint inside container
docker context use synology
docker exec n8n-container curl http://localhost:5678/metrics
```

**Expected**: Prometheus-format metrics output

**Reload Prometheus configuration**:
```bash
# 2. Force Prometheus to reload configuration
curl -X POST https://prometheus.jclee.me/-/reload
```

**Check Prometheus target status**:
```bash
# 3. Verify n8n target is configured and UP
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job=="n8n")'
```

**Common issues**:
- Scrape URL incorrect in prometheus.yml
- n8n metrics not enabled (check N8N_METRICS=true in .env)
- Network connectivity issues between Prometheus and n8n containers

### Logs Not Being Collected

**Check Promtail status**:
```bash
# 1. Check Promtail container logs
docker context use synology
docker logs promtail-container --tail 100
```

**Verify Docker socket access**:
```bash
# 2. Check Promtail can access Docker socket
docker context use synology
docker exec promtail-container ls -la /var/run/docker.sock
```

**Expected**: Socket file exists with proper permissions

**Test Loki connection**:
```bash
# 3. Verify Promtail can reach Loki
docker context use synology
docker exec promtail-container wget -O- http://loki-container:3100/ready
```

**Expected**: `{"status":"ready"}`

**Common issues**:
- Docker socket not mounted in Promtail container
- Network connectivity between Promtail and Loki
- Promtail configuration error (check promtail-config.yml)
- Synology `db` logging driver limitation (see CLAUDE.md)

### Dashboard Shows "No Data"

**Validate metrics exist**:
```bash
# 1. List all n8n metrics in Prometheus
curl -s "https://prometheus.jclee.me/api/v1/label/__name__/values" | \
  jq -r '.data[]' | grep "^n8n_"
```

**Test dashboard queries manually**:
```bash
# 2. Test a specific dashboard query
curl -s "https://prometheus.jclee.me/api/v1/query?query=n8n_active_workflow_count" | \
  jq '.data.result'
```

**Check datasource configuration**:
```bash
# 3. Verify Grafana datasource is configured correctly
curl -s -u admin:bingogo1 "https://grafana.jclee.me/api/datasources" | \
  jq '.[] | select(.type=="prometheus")'
```

**Common causes**:
- Metrics don't exist (need to validate first)
- Wrong datasource UID in dashboard JSON
- Query syntax error
- No workflows executed yet (some metrics only appear after activity)

---

## 📋 Deployment Completion Checklist

### Infrastructure Verification
- [ ] All 12 containers running with `Up` status
- [ ] All containers passing health checks
- [ ] No container restart loops (check uptime)
- [ ] All volumes mounted correctly
- [ ] Network connectivity between containers

### Service Access Verification
- [ ] https://n8n.jclee.me accessible (HTTP 200)
- [ ] https://grafana.jclee.me accessible (HTTP 200)
- [ ] https://prometheus.jclee.me accessible (HTTP 200)
- [ ] https://loki.jclee.me accessible (HTTP 200)
- [ ] n8n login page loads properly

### Prometheus Verification
- [ ] 3 n8n targets in UP state (n8n, postgres, redis)
- [ ] All monitoring targets UP (grafana, loki, alertmanager)
- [ ] n8n metrics appearing in Prometheus (query: `n8n_active_workflow_count`)
- [ ] PostgreSQL metrics appearing (query: `pg_up`)
- [ ] Redis metrics appearing (query: `redis_up`)

### Loki Verification
- [ ] n8n logs visible in Grafana Explore
- [ ] Log streams include container metadata (container_name, image)
- [ ] Logs updating in real-time
- [ ] LogQL queries working properly

### Grafana Dashboard Verification
- [ ] n8n dashboard auto-provisioned (UID: `n8n-workflow-automation-reds`)
- [ ] All 15 panels displaying data (no "No Data" messages)
- [ ] Golden Signals in top row showing metrics
- [ ] Time series panels showing trends
- [ ] Dashboard updates in real-time

### Configuration Files Verification
- [ ] Grafana provisioning folder mounted
- [ ] Prometheus config mounted with n8n scrape targets
- [ ] Loki config mounted with 3-day retention
- [ ] Promtail config mounted with Docker discovery
- [ ] AlertManager config mounted

---

## 🎯 Success Criteria

### Essential (Must Pass)

1. **Service Accessibility**:
   - https://n8n.jclee.me → HTTP 200
   - n8n web UI functional with login page

2. **Log Collection**:
   - Grafana Explore → Loki datasource → `{container_name="n8n-container"}` → Real-time logs visible

3. **Metrics Collection**:
   - Prometheus → Query: `n8n_active_workflow_count` → Returns data
   - All n8n targets UP in https://prometheus.jclee.me/targets

4. **Dashboard Functional**:
   - https://grafana.jclee.me/d/n8n-workflow-automation-reds → All panels show data

### Recommended (Should Pass)

5. **Workflow Execution Test**:
   - Create test workflow in n8n
   - Execute workflow manually
   - Verify metrics increment (query: `n8n_workflow_executions_total`)
   - Verify execution appears in logs (Grafana Explore)

6. **Alert Rules Active**:
   - Check https://prometheus.jclee.me/rules
   - n8n alert rules loaded (N8nDown, N8nWorkflowFailureRateHigh)
   - No alerts firing initially

7. **Performance Validation**:
   - Dashboard loads in <2 seconds
   - Log queries return in <3 seconds
   - Metrics queries return in <1 second

### Advanced (Optional)

8. **Recording Rules Working**:
   - Query: `n8n:workflows:start_rate` returns data
   - All n8n recording rules evaluating successfully

9. **Long-term Stability**:
   - No container restarts for 24 hours
   - Memory usage stable (<4GB total)
   - Disk usage within limits (<20GB total)

---

**Deployment Verification Complete!** 🎉

**Next Steps**:
1. Create your first n8n workflow
2. Monitor performance in Grafana dashboard
3. Set up AlertManager notifications (Slack/Email)
4. Review logs regularly in Loki

**Support**:
- Troubleshooting: [troubleshooting.md](../resume/troubleshooting.md)
- Architecture: [architecture.md](../resume/architecture.md)
- API Reference: [api.md](../resume/api.md)
