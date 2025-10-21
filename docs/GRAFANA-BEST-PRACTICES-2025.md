# Grafana Best Practices - 2025 Edition

## Dashboard Maturity Assessment

**Current Maturity Level: Medium → High**

### What We Had (Medium Maturity)
- ✅ Consistent numbering system (01-, 02-, etc.)
- ✅ Recording rules for performance
- ✅ Basic tagging
- ❌ No folder organization
- ❌ No USE/REDS methodology
- ❌ Inconsistent naming conventions
- ❌ Non-existent metrics in recording rules

### What We're Implementing (High Maturity)
- ✅ Folder-based organization
- ✅ Purpose-driven naming
- ✅ USE/REDS methodology applied
- ✅ Validated metrics only
- ✅ Comprehensive tagging strategy
- ✅ Version control via git
- ✅ Auto-provisioning (no manual edits)

---

## Folder Structure

```
📁 Core-Monitoring           # Monitoring stack self-monitoring
   ├── Monitoring Stack Health (USE)
   ├── Query Performance
   └── Service Health

📁 Infrastructure            # System-level metrics
   ├── System Metrics (USE)
   └── Container Performance (REDS)

📁 Applications              # Application-specific monitoring
   └── n8n Workflow Automation

📁 Logging                   # Log aggregation and analysis
   └── Log Analysis

📁 Alerting                  # Alert management
   └── Alert Overview
```

---

## Naming Conventions

### Format
```
[Category] - [Purpose] [(Methodology)]
```

### Examples
- `Core-Monitoring - Stack Health (USE)` ✅
- `Infrastructure - System Metrics (USE)` ✅
- `Applications - n8n Monitoring` ✅
- `01-monitoring-stack-health.json` ❌ (old style)

### Methodology Tags
- `(USE)`: Utilization, Saturation, Errors
- `(REDS)`: Rate, Errors, Duration, Saturation
- `(Custom)`: Custom business logic

---

## Tagging Strategy

### Required Tags
Every dashboard MUST have:
- `purpose`: [monitoring|infrastructure|application|logging|alerting]
- `audience`: [sre|developer|manager|all]
- `methodology`: [use|reds|custom]
- `services`: List of monitored services

### Optional Tags
- `priority`: [p0|p1|p2|p3]
- `team`: Owning team name
- `lifecycle`: [production|staging|development]

### Example
```json
{
  "tags": [
    "applications",
    "n8n",
    "workflows",
    "nodejs",
    "audience:sre",
    "methodology:reds",
    "priority:p1",
    "lifecycle:production"
  ]
}
```

---

## USE Methodology (Infrastructure Dashboards)

**For every resource, monitor:**
- **Utilization**: How busy is the resource? (e.g., CPU %, memory %, disk %)
- **Saturation**: How much queued work? (e.g., load average, wait time)
- **Errors**: Error counts and rates

### Example Layout
```
Row 1: Overview Stats (4 panels)
  - Total CPU Utilization (%)
  - Memory Saturation (swap usage)
  - Disk I/O Utilization (%)
  - Network Error Rate

Row 2: Time Series (3 panels)
  - CPU Utilization Over Time
  - Memory Saturation Over Time
  - Disk I/O Over Time

Row 3: Detailed Breakdown
  - Per-CPU Core Utilization
  - Memory Breakdown (RSS, Cache, Buffers)
  - Disk Latency Histogram
```

---

## REDS Methodology (Application/Service Dashboards)

**For every service, monitor:**
- **Rate**: Request throughput (req/s, ops/s)
- **Errors**: Error rate and count (HTTP 5xx, exceptions)
- **Duration**: Response time percentiles (P50, P95, P99)
- **Saturation**: Queue depth, concurrency, backlog

### Example Layout (n8n)
```
Row 1: Overview (REDS Golden Signals)
  - Request Rate (workflows/min)
  - Error Rate (failures/min)
  - Duration P95 (workflow execution time)
  - Saturation (active workflows, queue depth)

Row 2: Rate Trends
  - Workflow Success Rate Over Time
  - Workflow Failure Rate Over Time

Row 3: Error Analysis
  - Error Types Breakdown
  - Failed Workflow Details

Row 4: Duration Analysis
  - Response Time Percentiles (P50, P90, P99)
  - Slowest Workflows

Row 5: Saturation
  - Active Workflow Count
  - Queue Depth
  - Worker Utilization
```

---

## Dashboard Design Principles

### 1. **Purpose-Driven Design**
Every dashboard must answer specific questions:
- **SRE**: "Is the service healthy? What's breaking?"
- **Developer**: "How's my feature performing?"
- **Manager**: "What's the business impact?"

### 2. **Visual Hierarchy (Z-Pattern)**
Users scan in a Z-pattern (top-left → top-right → bottom-left → bottom-right).

```
┌─────────────────────────────────────┐
│ 🔥 Critical Stats (Top-Left)        │ Most important metrics here
│ - Service Up/Down                   │
│ - Error Rate                        │
│ - P95 Latency                       │
├─────────────────────────────────────┤
│ 📊 Time Series (Middle)             │ Trends over time
│ - Request Rate                      │
│ - Error Rate                        │
│ - Response Time                     │
├─────────────────────────────────────┤
│ 🔍 Detailed Breakdown (Bottom)      │ Deep-dive details
│ - Top Errors                        │
│ - Slowest Endpoints                 │
│ - Resource Consumption              │
└─────────────────────────────────────┘
```

### 3. **Consistent Panel Configuration**
Every time series panel should have:
- **Legend**: Show `mean`, `last`, `max` calculations
- **Tooltip**: Multi-series mode, sorted descending
- **Thresholds**: Green/Yellow/Red based on SLOs
- **Units**: Always set appropriate units (bytes, percent, seconds)

### 4. **Color Strategy**
- **Green**: Healthy, < 50% utilization
- **Yellow**: Warning, 50-80% utilization or 1-5% error rate
- **Red**: Critical, > 80% utilization or > 5% error rate

---

## Recording Rules Strategy

### When to Use Recording Rules
1. **Complex queries used in multiple dashboards**
2. **High-cardinality metrics** (many labels)
3. **Slow queries** (> 1 second execution time)
4. **Critical alerts** requiring fast evaluation

### Naming Convention
```
<scope>:<metric>:<aggregation>:<timewindow>
```

Examples:
- `job:http_requests:rate5m` - Rate of HTTP requests per job (5m window)
- `n8n:workflows:failure_rate` - n8n workflow failure rate
- `container:memory_usage:bytes` - Container memory usage

### Best Practices
- **Validate metrics exist before creating rules** (mandatory!)
- **Keep rules simple** - complex logic → multiple rules
- **Monitor rule performance**: `prometheus_rule_evaluation_duration_seconds`
- **Document rule purpose** with comments
- **Review quarterly** for obsolete rules

---

## Metrics Validation Protocol

**MANDATORY before dashboard creation or recording rule:**

```bash
# 1. List all available metrics
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep {service_name}

# 2. Query specific metric
curl -s "https://prometheus.jclee.me/api/v1/query?query={metric_name}" | \
  jq '.data.result'

# 3. Test query in Prometheus UI
open https://prometheus.jclee.me/graph?g0.expr={metric_name}&g0.tab=0
```

**Rule**: Never assume a metric exists. Always validate first.

---

## Alert Rule Guidelines

### Alert Naming
```
<Component><Condition><Severity>
```

Examples:
- `N8nWorkflowFailureRateHigh` ✅
- `PrometheusTSDBCorruption` ✅
- `alert_1` ❌

### Severity Levels
- **critical**: Service down, data loss, immediate action required
- **warning**: Degraded performance, investigate within hours
- **info**: FYI, no action required

### Alert Quality
**Good Alert** (actionable):
```yaml
- alert: N8nWorkflowFailureRateHigh
  expr: rate(n8n_workflow_failed_total[5m]) * 60 > 5
  for: 5m  # Avoid alert fatigue
  annotations:
    summary: "n8n workflow failure rate high"
    description: "Failure rate: {{ $value }} failures/min (threshold: 5/min)"
    runbook_url: "https://wiki.company.com/n8n-troubleshooting"
    grafana_url: "https://grafana.jclee.me/d/application-monitoring"
```

**Bad Alert** (not actionable):
```yaml
- alert: ThingIsBad
  expr: thing > 100
  annotations:
    summary: "thing is bad"
```

### Avoid Alert Fatigue
- Use `for: 5m` to avoid transient spikes
- Combine metrics for high-confidence signals
- Use **rate** instead of raw counters
- Group related alerts with `severity` labels

---

## Dashboard Lifecycle

### Development Flow
```
1. Local edit:  configs/provisioning/dashboards/*.json
2. Auto-sync:   grafana-sync.service (1-2s)
3. Auto-reload: Grafana scans every 10s
4. Verify:      https://grafana.jclee.me
5. Commit:      git add + commit + push
```

### Testing Checklist
- [ ] All panels show data (no "No data")
- [ ] Thresholds configured correctly
- [ ] Legend shows calculations (mean, last, max)
- [ ] Units set appropriately
- [ ] Time range appropriate (default: 6h)
- [ ] Refresh interval set (default: 30s)
- [ ] Mobile-responsive (test on smaller screen)

### Versioning
- All dashboards in git (single source of truth)
- No manual edits in Grafana UI (overwritten by auto-provisioning)
- Use branches for experiments: `git checkout -b dashboard-experiment`

---

## Common Anti-Patterns

### ❌ Don't Do This
1. **Too many panels**: > 15 panels → split into multiple dashboards
2. **No thresholds**: Can't distinguish healthy from unhealthy
3. **Raw counters**: Use `rate()` or `increase()` instead
4. **No time window**: Specify `[5m]` for rate calculations
5. **Assumed metrics**: Always validate metrics exist
6. **Manual editing**: Don't create dashboards in UI (use provisioning)
7. **No USE/REDS**: Infrastructure/service dashboards need methodology

### ✅ Do This Instead
1. **Focused dashboards**: 8-12 panels, single purpose
2. **Meaningful thresholds**: Based on SLOs (green < 50%, yellow 50-80%, red > 80%)
3. **Rate calculations**: `rate(metric[5m])` for rates
4. **Consistent time windows**: [5m] for alerts, [1h] for trends
5. **Metrics validation**: Run validation script before creating dashboard
6. **Git-based workflow**: Edit JSON, commit, auto-deploy
7. **Apply methodology**: USE for infrastructure, REDS for services

---

## Migration Plan (Old → New)

### Phase 1: Folder Structure (Week 1)
- [x] Create folder definitions in `dashboard.yml`
- [ ] Move dashboards to appropriate folders
- [ ] Update dashboard UIDs for consistency

### Phase 2: Naming & Tagging (Week 1)
- [ ] Rename dashboards (remove numbers, add methodology)
- [ ] Add comprehensive tags to all dashboards
- [ ] Update dashboard titles and descriptions

### Phase 3: USE/REDS Implementation (Week 2)
- [ ] Refactor Infrastructure dashboards with USE
- [ ] Refactor Application dashboards with REDS
- [ ] Create recording rules for complex USE/REDS queries

### Phase 4: Documentation (Week 2)
- [ ] Create runbooks for each dashboard
- [ ] Document alert response procedures
- [ ] Create onboarding guide for new team members

---

## Performance Optimization

### Dashboard Load Time
**Target**: < 2 seconds

**Optimizations**:
1. **Use recording rules** for expensive queries
2. **Limit time range** (default: 6h, not 30d)
3. **Reduce cardinality** with label aggregation
4. **Use $__interval** variable for adaptive resolution

### Query Optimization
```promql
# ❌ Slow (high cardinality)
rate(http_requests_total[5m])

# ✅ Fast (pre-aggregated via recording rule)
job:http_requests:rate5m
```

### Monitoring Query Performance
```promql
# Slowest queries
topk(10, prometheus_engine_query_duration_seconds{quantile="0.99"})

# Recording rule evaluation time
prometheus_rule_evaluation_duration_seconds > 1
```

---

## Resources

### Official Documentation
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [Prometheus Recording Rules](https://prometheus.io/docs/practices/rules/)
- [USE Methodology](http://www.brendangregg.com/usemethod.html)
- [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)

### Community Resources
- [Grafana Dashboard ID 11159](https://grafana.com/grafana/dashboards/11159) - Node.js Application Dashboard
- [n8n Monitoring Setup](https://community.n8n.io/t/n8n-grafana-full-node-js-metrics-dashboard-json-example-included/115366)

### Internal Documentation
- `docs/METRICS-VALIDATION-2025-10-12.md` - Metrics validation methodology
- `docs/DASHBOARD-MODERNIZATION-2025-10-12.md` - Dashboard modernization guide
- `docs/DEPRECATED-REALTIME_SYNC.md` - Deprecated sync architecture (replaced by NFS mount)

---

**Status**: ACTIVE - 2025-10-13
**Maturity Level**: Medium → High (in progress)
**Last Updated**: 2025-10-13 by Claude Code (AI Cognitive Agent)
**Compliance**: Constitutional Principle #1 - "If it's not in Grafana, it didn't happen"
