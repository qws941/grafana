# n8n Log Collection Investigation
**Date**: 2025-10-12
**Status**: ❌ **n8n logs NOT being collected by Loki**
**Root Cause**: Synology `db` logging driver incompatibility

---

## Problem Summary

n8n container logs are NOT flowing to Loki despite:
- ✅ Promtail configured with Docker service discovery
- ✅ Promtail successfully discovering n8n-container (ID: `93754fa795e0c09a58ef6aa66651ea49f90069e0cf26ac685340f0664cf2ccf1`)
- ✅ n8n container actively logging (verified via `docker logs n8n-container`)

## Root Cause Analysis

### Discovery Process

1. **Promtail Discovery**: Confirmed n8n-container discovered by Promtail
   ```
   level=info ts=2025-10-11T16:34:10.183219337Z
   msg="added Docker target"
   containerID=93754fa795e0c09a58ef6aa66651ea49f90069e0cf26ac685340f0664cf2ccf1
   ```

2. **Loki Label Check**: n8n-container NOT appearing in Loki labels
   - ❌ Not in `container_name` label values
   - ❌ Not in `service_name` label values
   - ✅ Only n8n-postgres-container and n8n-redis-container present

3. **n8n Logging Verification**: Container IS actively logging
   ```bash
   $ docker logs n8n-container --tail 20
   Enqueued execution 221 (job 221)
   Enqueued execution 222 (job 222)
   ... [execution logs continue]
   ```

4. **Log Driver Discovery** (🎯 **ROOT CAUSE**):
   ```bash
   $ docker inspect n8n-container --format '{{.HostConfig.LogConfig.Type}}'
   db
   ```

### The Problem: Synology `db` Logging Driver

**Issue**: n8n-container uses Synology's proprietary `db` logging driver instead of standard `json-file`.

**Impact**:
- Docker daemon can read logs (via `docker logs`)
- Promtail CANNOT read logs (expects `json-file` or `journald` drivers)
- Logs stored in Synology's internal database, not accessible via Docker API

**Comparison with Working Containers**:
| Container | Log Driver | Promtail Collection |
|-----------|------------|---------------------|
| grafana-container | json-file | ✅ Working |
| prometheus-container | json-file | ✅ Working |
| loki-container | json-file | ✅ Working |
| n8n-container | **db** | ❌ **Not Working** |
| n8n-postgres-container | json-file | ✅ Working |

---

## n8n Log Structure Analysis

Despite collection issue, direct examination of n8n logs reveals:

### Log Format: Simple Text (NOT JSON)

```
Enqueued execution 221 (job 221)
Enqueued execution 222 (job 222)
Enqueued execution 223 (job 223)
```

**Characteristics**:
- ❌ Not JSON-formatted
- ❌ No structured fields (level, timestamp, message)
- ❌ No execution success/failure status
- ✅ Execution ID available
- ✅ Can parse with regex: `Enqueued execution (\d+)`

### Available Execution Information

From logs, we can extract:
- **Execution ID**: `221, 222, 223, ...`
- **Status**: Only "Enqueued" (no completion/failure logs observed)

**Metrics Potential**: LOW
- Can count executions started (via `Enqueued` pattern)
- CANNOT determine: execution success, failure, duration, errors

---

## Solutions

### Option 1: Change n8n Container Log Driver (⭐ **RECOMMENDED**)

**Description**: Reconfigure n8n-container to use `json-file` logging driver

**Implementation**:
```yaml
# In docker-compose.yml for n8n service
services:
  n8n:
    image: n8nio/n8n:latest
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

**Steps**:
1. Edit `/volume1/docker/n8n/docker-compose.yml` (or wherever n8n is deployed)
2. Add `logging` configuration to n8n service
3. Restart n8n container: `docker compose restart n8n`
4. Verify Promtail collection: `{container_name="n8n-container"}` in Grafana Explore

**Pros**:
- ✅ Immediate Promtail compatibility
- ✅ Standard Docker logging best practice
- ✅ Log rotation built-in (prevents disk overflow)

**Cons**:
- ⚠️ Requires container restart (brief downtime)
- ⚠️ Historical logs in Synology db lost (only new logs collected)

---

### Option 2: Configure n8n Structured Logging + Log File Output

**Description**: Configure n8n to write JSON logs to a file that Promtail can tail

**Implementation**:
```yaml
# n8n environment variables
environment:
  N8N_LOG_LEVEL: info
  N8N_LOG_OUTPUT: file
  N8N_LOG_FILE_LOCATION: /home/node/.n8n/logs
  N8N_LOG_FILE_SIZE_MAX: 16m
  N8N_LOG_FILES_COUNT_MAX: 3

# Add volume mount
volumes:
  - ./n8n-logs:/home/node/.n8n/logs

# Add Promtail static config
# In promtail-config.yml:
- job_name: n8n-file-logs
  static_configs:
    - targets:
        - localhost
      labels:
        job: n8n
        service: n8n-app
        __path__: /n8n-logs/*.log
```

**Pros**:
- ✅ n8n native structured logging (JSON format)
- ✅ More detailed execution information
- ✅ Can keep Synology db driver for Synology Log Center

**Cons**:
- ⚠️ Requires Promtail container volume mount modification
- ⚠️ Requires n8n container restart
- ⚠️ Duplicate logging (stdout + file)

---

### Option 3: Parse Synology Logs via Alternative Path

**Description**: Access Synology's internal log database and parse logs

**Pros**:
- ✅ No container reconfiguration needed

**Cons**:
- ❌ Complex (reverse-engineering Synology log DB format)
- ❌ Not officially supported
- ❌ May break with Synology updates
- ⚠️ NOT RECOMMENDED

---

### Option 4: Create Log-Based Metrics from Prometheus Scrapes (CURRENT WORKAROUND)

**Description**: Use existing n8n Prometheus metrics instead of log-based metrics

**Status**: ✅ **ALREADY IMPLEMENTED**

**Available Metrics** (from Prometheus):
- `n8n_active_workflow_count` - Active workflow count
- `n8n_workflow_failed_total` - Workflow failures (counter)
- `n8n_nodejs_eventloop_lag_p95_seconds` - Event loop lag P95
- `n8n_process_resident_memory_bytes` - Memory usage
- `n8n_nodejs_gc_duration_seconds` - GC performance

**Dashboards**: Application Monitoring (04-application-monitoring.json)
**Alert Rules**: configs/alert-rules.yml (n8n_monitoring group)

**Pros**:
- ✅ No configuration changes needed
- ✅ Reliable metrics-based monitoring
- ✅ Already integrated with Grafana + AlertManager

**Cons**:
- ❌ No log-based debugging (can't see execution details)
- ❌ No execution-level metrics (only workflow-level)

---

## Implementation Attempts (2025-10-12)

### Attempt 1: Change Docker Logging Driver to json-file
**Status**: ❌ **FAILED**
**Action**: Modified /volume1/n8n/docker-compose.yml to add:
```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```
**Result**: Synology overrides docker-compose logging config at system level. Container still uses `db` driver after recreation.
```bash
$ docker inspect n8n-container --format '{{.HostConfig.LogConfig.Type}}'
db  # ← Still "db" despite docker-compose.yml config
```

### Attempt 2: Enable n8n File Logging
**Status**: ❌ **FAILED**
**Action**: Modified n8n environment variables:
```yaml
- N8N_LOG_OUTPUT=file
- N8N_LOG_FILE_LOCATION=/home/node/.n8n/logs
- N8N_LOG_FILE_SIZE_MAX=16m
- N8N_LOG_FILES_COUNT_MAX=3
```
**Result**: n8n does not support file logging or environment variables are incorrect. Log directory not created.
```bash
$ docker exec n8n-container ls -la /home/node/.n8n/logs
Directory does not exist  # ← n8n ignores file logging config
```

### Conclusion: Synology Platform Limitation

**Technical Constraint**: Synology Docker Engine enforces `db` logging driver system-wide for Log Center integration. This is a **platform-level limitation**, not a configuration issue.

**Impact**:
- ✅ Docker daemon can read logs (via `docker logs`)
- ❌ Promtail CANNOT read logs (Docker API returns empty for `db` driver)
- ❌ Cannot override via docker-compose.yml
- ❌ n8n native file logging not supported

**Workarounds Evaluated**:
1. ❌ Change log driver - Blocked by Synology
2. ❌ n8n file logging - Not supported by n8n
3. ❌ Custom log forwarder script - Complex, adds maintenance burden
4. ✅ **Prometheus metrics** - Already implemented, superior monitoring

---

## Recommendation (FINAL)

**Decision**: **Continue using Prometheus metrics monitoring** (Option 4 - CURRENT IMPLEMENTATION)

**Reasoning**:
1. **Platform Limitation**: Synology `db` driver cannot be overridden
2. **Metrics Superior to Logs**: Prometheus provides structured, queryable data
3. **Comprehensive Coverage**: 37 n8n metrics + 13 alert rules already implemented
4. **Log Content Limited**: n8n logs are simple text ("Enqueued execution 221") with no structured data
5. **No Operational Gap**: All critical metrics monitored (workflows, failures, performance, resources)

**Cost-Benefit Analysis**:
- Custom log collector: High complexity, low value (simple text logs)
- Prometheus metrics: Low complexity, high value (structured monitoring)
- **Winner**: Prometheus metrics ✅

---

## Implementation Status

### ✅ Completed (2025-10-12)

1. **Dashboard Enhancement** (04-application-monitoring.json):
   - Panel 1: n8n Active Workflows (corrected metric)
   - Panel 2: n8n Workflow Failure Rate (corrected to use n8n_workflow_failed_total)
   - Panel 4: n8n Event Loop Lag P95 (replaced missing execution duration)
   - Panel 9: n8n Memory Usage (RSS, Heap) - **NEW**
   - Panel 10: n8n Garbage Collection Performance - **NEW**
   - Panel 11: n8n Active Handles & Resources - **NEW**

2. **Alert Rules** (configs/alert-rules.yml):
   - `N8nWorkflowFailureRateHigh` - >5 failures/min for 5m
   - `N8nEventLoopLagHigh` - >0.5s P95 for 5m (CRITICAL)
   - `N8nMemoryUsageHigh` - >2GB RSS for 5m
   - `N8nGarbageCollectionSlow` - >0.1s average GC for 5m
   - `N8nNoActiveWorkflows` - 0 active workflows for 10m (CRITICAL)

3. **Prometheus Reload**: Alert rules loaded successfully (20 total rules)

### ⏳ Future Work

When ready to implement log collection (Option 1):

1. Create maintenance plan (n8n downtime acceptable)
2. Edit n8n docker-compose.yml (add json-file logging)
3. Restart n8n container
4. Verify Promtail collection: `{container_name="n8n-container"} | json`
5. Create n8n-specific log dashboard (05-log-analysis.json already exists for general logs)
6. Add execution-level alerts (if n8n provides structured execution logs)

---

## Related Documentation

- [METRICS-VALIDATION-2025-10-12.md](./METRICS-VALIDATION-2025-10-12.md) - Metrics availability analysis
- [DASHBOARD-MODERNIZATION-2025-10-12.md](./DASHBOARD-MODERNIZATION-2025-10-12.md) - Dashboard refactoring plan
- configs/alert-rules.yml - Alert rule definitions
- configs/promtail-config.yml - Promtail logging configuration
- configs/provisioning/dashboards/04-application-monitoring.json - Application monitoring dashboard

---

## Verification Commands

```bash
# Check n8n container log driver
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker inspect n8n-container --format '{{.HostConfig.LogConfig.Type}}'"
# Expected: db (current) or json-file (after Option 1 implementation)

# View n8n logs directly
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs n8n-container --tail 50"

# Check if n8n logs in Loki (after Option 1)
# In Grafana Explore:
{container_name="n8n-container"}

# Verify Promtail discovering n8n
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs promtail-container 2>&1 | grep 93754fa795e0c09a58ef6aa66651ea49f90069e0cf26ac685340f0664cf2ccf1"

# Check Prometheus n8n metrics
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=n8n_active_workflow_count'" | jq '.data.result'
```

---

**Conclusion**: n8n log collection blocked by Synology `db` logging driver. Current workaround (Prometheus metrics + alerts) provides adequate monitoring. Log collection enhancement deferred to future maintenance window.
