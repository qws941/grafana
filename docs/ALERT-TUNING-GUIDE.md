# Alert Rule Tuning Guide
**Date**: 2025-10-12
**Purpose**: Guidelines for creating, tuning, and maintaining alert rules
**Target Audience**: DevOps engineers, SREs, monitoring administrators

---

## Table of Contents

1. [Alert Severity Classification](#alert-severity-classification)
2. [Threshold Tuning Methodology](#threshold-tuning-methodology)
3. [False Positive Reduction](#false-positive-reduction)
4. [Alert Fatigue Prevention](#alert-fatigue-prevention)
5. [Runbook Requirements](#runbook-requirements)
6. [Alert Rule Examples](#alert-rule-examples)
7. [Testing Alert Rules](#testing-alert-rules)
8. [Maintenance Schedule](#maintenance-schedule)

---

## Alert Severity Classification

### Severity Levels

| Severity | Definition | Response Time | Example |
|----------|------------|---------------|---------|
| **CRITICAL** | Service down or imminent failure | Immediate (< 5 min) | Prometheus down, all targets down, no active workflows |
| **WARNING** | Performance degradation or capacity issue | 30 minutes | High error rate, memory usage >80%, event loop lag >0.1s |
| **INFO** | Informational, no immediate action needed | Next business day | Low disk space (>60%), backup completed |

### Severity Selection Criteria

**Use CRITICAL when**:
- Service is completely unavailable
- Data loss is imminent
- Security breach detected
- Critical dependency failed (database, cache, etc.)

**Use WARNING when**:
- Service is degraded but functional
- Capacity threshold approaching
- Error rate elevated but below critical threshold
- Performance degradation detected

**Use INFO when**:
- Routine operational events (backups, maintenance)
- Early warning indicators (disk >60%)
- Successful recovery from warning state

---

## Threshold Tuning Methodology

### Step 1: Establish Baseline

**Collect historical data** for at least 7 days (ideally 30 days):

```promql
# Example: Query P95 response time over 30 days
quantile_over_time(0.95, http_request_duration_seconds[30d])

# Example: Query error rate over 30 days
rate(http_requests_total{status=~"5.."}[30d]) /
rate(http_requests_total[30d]) * 100
```

**Identify patterns**:
- Daily peaks (business hours vs off-hours)
- Weekly patterns (weekdays vs weekends)
- Monthly trends (growth, seasonality)

### Step 2: Calculate Thresholds

**Formula**: `Threshold = P95_baseline * safety_factor`

| Metric Type | P95 Baseline | Safety Factor | Threshold |
|-------------|--------------|---------------|-----------|
| Response time | 200ms | 2.5x | 500ms (WARNING), 1s (CRITICAL) |
| Error rate | 0.1% | 10x | 1% (WARNING), 5% (CRITICAL) |
| Memory usage | 60% | 1.3x | 80% (WARNING), 90% (CRITICAL) |
| CPU usage | 50% | 1.6x | 80% (WARNING), 95% (CRITICAL) |

### Step 3: Set Duration Windows

**`for` clause duration** determines alert sensitivity:

| Alert Type | Duration | Rationale |
|------------|----------|-----------|
| Critical service down | 2-5 minutes | Fast detection, minimal false positives |
| Performance degradation | 5-10 minutes | Filter out transient spikes |
| Capacity warnings | 10-30 minutes | Avoid flapping during normal variance |
| Slow growth trends | 1-24 hours | Detect gradual capacity issues |

**Example**:
```yaml
- alert: HighLatency
  expr: p95_latency > 1
  for: 5m  # Sustained for 5 minutes before alerting
```

### Step 4: Iterate Based on Feedback

**Track false positive rate**:
```promql
# Query: Alert fired but no actual issue
sum(increase(prometheus_notifications_sent_total[24h])) by (alertname)
```

**Adjustment guidelines**:
- **>20% false positive rate**: Increase threshold or duration
- **Missed incidents**: Decrease threshold or duration
- **Alert fatigue**: Consolidate related alerts

---

## False Positive Reduction

### Technique 1: Exclude Known Maintenance Windows

```yaml
- alert: ServiceDown
  expr: up{job="my-service"} == 0
  for: 2m
  # Exclude maintenance window (Sunday 2-4 AM UTC)
  annotations:
    description: "Service down (not during maintenance)"
  labels:
    severity: critical
    maintenance_excluded: "true"
```

**Implementation**: Use external scheduler or Grafana Mute Timings

### Technique 2: Use Rate of Change

Detect **sudden changes** rather than absolute thresholds:

```yaml
- alert: SuddenTrafficIncrease
  expr: |
    (rate(http_requests_total[5m]) /
     rate(http_requests_total[5m] offset 1h)) > 3
  for: 5m
  annotations:
    summary: "Traffic increased 3x compared to 1 hour ago"
```

### Technique 3: Multi-Condition Alerts

Combine **multiple signals** to increase confidence:

```yaml
- alert: ServiceUnhealthy
  expr: |
    up{job="my-service"} == 0 AND
    rate(http_requests_total{job="my-service"}[1m]) == 0 AND
    probe_success{job="blackbox"} == 0
  for: 3m
  annotations:
    summary: "Service confirmed down via multiple checks"
```

### Technique 4: Anomaly Detection

Use **prediction functions** for anomalous behavior:

```yaml
- alert: AnomalousErrorRate
  expr: |
    rate(http_errors_total[5m]) >
    (avg_over_time(rate(http_errors_total[5m])[1d:5m]) +
     3 * stddev_over_time(rate(http_errors_total[5m])[1d:5m]))
  for: 10m
  annotations:
    summary: "Error rate 3 standard deviations above daily average"
```

---

## Alert Fatigue Prevention

### Problem: Alert Fatigue

**Symptoms**:
- Team ignores alerts
- Notifications muted
- Actual incidents missed

**Root causes**:
- Too many low-severity alerts
- Alerts firing for non-actionable issues
- Duplicate/redundant alerts

### Solution 1: Alert Grouping

**Group related alerts** into single notification:

```yaml
# alertmanager.yml
route:
  group_by: ['alertname', 'service', 'cluster']
  group_wait: 30s      # Wait 30s before sending first notification
  group_interval: 5m   # Send grouped alerts every 5 minutes
  repeat_interval: 4h  # Repeat notification every 4 hours
```

### Solution 2: Alert Dependency Chains

**Suppress child alerts** when parent is firing:

```yaml
# Example: Suppress pod alerts if node is down
- alert: NodeDown
  expr: up{job="node-exporter"} == 0
  labels:
    severity: critical
    suppress_child: "true"

- alert: PodDown
  expr: kube_pod_status_phase{phase="Running"} == 0
  # Only fire if node is up
  labels:
    severity: warning
    parent_alert: "NodeDown"
```

### Solution 3: Alert Priority Routing

**Route by severity** to different channels:

```yaml
# alertmanager.yml
route:
  receiver: default
  routes:
    - match:
        severity: critical
      receiver: pagerduty  # Page on-call engineer

    - match:
        severity: warning
      receiver: slack       # Post to Slack channel

    - match:
        severity: info
      receiver: email       # Send email digest
```

### Solution 4: Alert Thresholds Review

**Monthly review** of alert statistics:

```promql
# Top 10 most frequent alerts (last 30 days)
topk(10, sum(increase(prometheus_notifications_sent_total[30d])) by (alertname))

# Alerts with >50% false positive rate
sum(increase(prometheus_notifications_sent_total[30d])) by (alertname) > 10
```

**Action**: Adjust thresholds for top offenders

---

## Runbook Requirements

### Mandatory Fields

Every alert **MUST** include:

| Field | Purpose | Example |
|-------|---------|---------|
| `summary` | One-line description | "Prometheus target down" |
| `description` | Detailed context with values | "Target {{$labels.job}} ({{$labels.instance}}) has been down for {{$value}} seconds" |
| `runbook_url` | Link to remediation steps | "https://wiki.example.com/runbooks/prometheus-target-down" |
| `grafana_url` | Link to relevant dashboard | "https://grafana.jclee.me/d/system-overview" |
| `severity` | CRITICAL / WARNING / INFO | "critical" |

### Example Alert with Runbook

```yaml
- alert: PrometheusTargetDown
  expr: up{job=~"prometheus|grafana|loki"} == 0
  for: 2m
  labels:
    severity: critical
    component: monitoring
  annotations:
    summary: "Critical Prometheus target down"
    description: |
      Target {{$labels.job}} ({{$labels.instance}}) has been down for {{ $value | humanizeDuration }}.

      **Impact**: Metrics collection stopped, dashboards may show stale data.
    runbook_url: "https://wiki.jclee.me/runbooks/prometheus-target-down"
    grafana_url: "https://grafana.jclee.me/d/system-overview"
    slack_channel: "#alerts-critical"
```

### Runbook Template

Create runbooks at `/docs/runbooks/<alert-name>.md`:

```markdown
# Runbook: PrometheusTargetDown

## Alert Definition
- **Alert Name**: PrometheusTargetDown
- **Severity**: CRITICAL
- **Threshold**: Target down for >2 minutes

## Impact
- Metrics collection stopped for affected target
- Dashboards show stale data
- Alerts may not fire if Prometheus itself is down

## Diagnosis

### Step 1: Check Target Status
\```bash
# Query Prometheus targets API
curl -s http://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health != "up")'
\```

### Step 2: Verify Service Availability
\```bash
# SSH to Synology NAS
ssh -p 1111 jclee@192.168.50.215

# Check container status
sudo docker ps | grep <target-name>

# Check service logs
sudo docker logs <target-name> --tail 50
\```

## Resolution

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Container stopped | `sudo docker start <container-name>` |
| Network issue | Restart Docker network: `sudo docker network disconnect/connect` |
| Service crashed | Check logs, restart container |
| Configuration error | Validate config, rollback if needed |

### Step-by-Step Recovery

1. **Identify failing target**:
   \```bash
   # In Prometheus UI: http://prometheus.jclee.me/targets
   # Find target with health != "up"
   \```

2. **Restart target service**:
   \```bash
   ssh -p 1111 jclee@192.168.50.215
   sudo docker restart <target-container>
   \```

3. **Verify recovery**:
   \```bash
   # Wait 1 minute, then check
   curl http://prometheus.jclee.me/api/v1/targets | \
     jq '.data.activeTargets[] | select(.labels.job == "<job-name>") | .health'
   \```

4. **Confirm alert resolved**:
   - Alert should auto-resolve within 2 minutes
   - Check AlertManager: http://alertmanager.jclee.me

## Escalation

If issue persists after 10 minutes:
- **Escalate to**: DevOps Lead
- **Contact**: @devops-oncall in Slack
- **Emergency**: Check infrastructure status (network, host)

## Post-Incident

- Document root cause in incident report
- Review alert threshold if false positive
- Update this runbook with learnings
\```

---

## Alert Rule Examples

### Example 1: Service Availability

```yaml
- alert: ServiceDown
  expr: up{job=~"critical-service.*"} == 0
  for: 2m
  labels:
    severity: critical
    category: availability
  annotations:
    summary: "Service {{ $labels.job }} is down"
    description: |
      Service {{ $labels.job }} on {{ $labels.instance }} has been down for {{ $value | humanizeDuration }}.

      **Last known status**: {{ with query "up{job=\"{{$labels.job}}\"} offset 1h" }}{{ . | first | value }}{{ end }}
    runbook_url: "https://wiki.jclee.me/runbooks/service-down"
    grafana_url: "https://grafana.jclee.me/d/system-overview?var-job={{$labels.job}}"
```

### Example 2: Performance Degradation

```yaml
- alert: HighLatency
  expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
  for: 5m
  labels:
    severity: warning
    category: performance
  annotations:
    summary: "High latency detected on {{ $labels.service }}"
    description: |
      P95 latency is {{ $value | humanize }}s (threshold: 1s).

      **Trend**: {{ with query "deriv(http_request_duration_seconds_bucket[10m])" }}{{ . | first | value | humanize }}{{ end }}
    runbook_url: "https://wiki.jclee.me/runbooks/high-latency"
    grafana_url: "https://grafana.jclee.me/d/query-performance"
```

### Example 3: Capacity Warning

```yaml
- alert: HighMemoryUsage
  expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
  for: 10m
  labels:
    severity: warning
    category: capacity
  annotations:
    summary: "High memory usage on {{ $labels.instance }}"
    description: |
      Memory usage is {{ $value | humanize }}% (threshold: 80%).

      **Available**: {{ with query "node_memory_MemAvailable_bytes{instance=\"{{$labels.instance}}\"}" }}{{ . | first | value | humanize1024 }}B{{ end }}
      **Total**: {{ with query "node_memory_MemTotal_bytes{instance=\"{{$labels.instance}}\"}" }}{{ . | first | value | humanize1024 }}B{{ end }}
    runbook_url: "https://wiki.jclee.me/runbooks/high-memory"
    grafana_url: "https://grafana.jclee.me/d/infrastructure-metrics?var-instance={{$labels.instance}}"
```

### Example 4: Error Rate

```yaml
- alert: HighErrorRate
  expr: |
    (sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) /
     sum(rate(http_requests_total[5m])) by (service)) * 100 > 1
  for: 5m
  labels:
    severity: warning
    category: reliability
  annotations:
    summary: "High error rate on {{ $labels.service }}"
    description: |
      Error rate is {{ $value | humanize }}% (threshold: 1%).

      **5xx count**: {{ with query "sum(rate(http_requests_total{status=~\"5..\",service=\"{{$labels.service}}\"}[5m])) * 60" }}{{ . | first | value | humanize }} errors/min{{ end }}
    runbook_url: "https://wiki.jclee.me/runbooks/high-error-rate"
    grafana_url: "https://grafana.jclee.me/d/application-monitoring?var-service={{$labels.service}}"
```

---

## Testing Alert Rules

### Method 1: Unit Tests with promtool

```bash
# Create test file: configs/alert-rules-test.yml
rule_files:
  - alert-rules.yml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'up{job="prometheus", instance="localhost:9090"}'
        values: '0 0 0 0'  # Target down for 4 minutes

    alert_rule_test:
      - eval_time: 2m
        alertname: PrometheusTargetDown
        exp_alerts:
          - exp_labels:
              severity: critical
              job: prometheus
            exp_annotations:
              summary: "Critical Prometheus target down"

# Run tests
promtool test rules configs/alert-rules-test.yml
```

### Method 2: Manual Trigger

**Temporarily lower threshold** to force alert:

```yaml
# Original
- alert: HighCPU
  expr: node_cpu_usage > 80
  for: 5m

# Test version (lower threshold)
- alert: HighCPU_TEST
  expr: node_cpu_usage > 10  # Intentionally low
  for: 1m  # Shorter duration
```

**Trigger alert**, verify notification, then revert.

### Method 3: Amtool (AlertManager CLI)

```bash
# Query current alerts
amtool --alertmanager.url=http://alertmanager.jclee.me alert query

# Silence alert for testing
amtool --alertmanager.url=http://alertmanager.jclee.me silence add \
  alertname=PrometheusTargetDown \
  --duration=30m \
  --comment="Testing alert rule"

# Remove silence
amtool --alertmanager.url=http://alertmanager.jclee.me silence expire <silence-id>
```

---

## Maintenance Schedule

### Weekly Tasks

- **Review firing alerts**: Check AlertManager for persistent alerts
- **Validate alert fatigue metrics**: Query top 10 most frequent alerts

### Monthly Tasks

- **Alert effectiveness review**:
  ```promql
  # False positive rate
  sum(increase(prometheus_notifications_sent_total[30d])) by (alertname)
  ```
- **Threshold tuning**: Adjust based on 30-day baseline
- **Runbook updates**: Verify links and steps are current

### Quarterly Tasks

- **Alert rule audit**: Remove obsolete rules
- **Severity classification review**: Ensure alignment with SLA/SLO
- **Notification routing review**: Update on-call schedules

---

## Best Practices Summary

| Practice | Guideline |
|----------|-----------|
| **Alert on symptoms, not causes** | Alert: "High latency" (symptom) > "CPU high" (cause) |
| **Every alert must be actionable** | If no action needed, it's not an alert—use INFO level |
| **Use percentiles, not averages** | P95/P99 detect tail latency issues |
| **Set appropriate `for` durations** | Filter transient spikes, balance detection speed |
| **Include context in annotations** | Current value, threshold, historical trend |
| **Always link to runbook** | Every alert needs a runbook_url |
| **Review alert effectiveness monthly** | Track false positive rate, adjust thresholds |
| **Test alert rules before deploying** | Use promtool or manual triggers |
| **Group related alerts** | Reduce notification noise |
| **Route by severity** | Critical → page, Warning → Slack, Info → email |

---

## Related Documentation

- [Alert Rules Configuration](../configs/alert-rules.yml) - Current alert rule definitions
- [METRICS-VALIDATION-2025-10-12.md](./METRICS-VALIDATION-2025-10-12.md) - Metrics validation methodology
- [CODEBASE-ANALYSIS-2025-10-12.md](./CODEBASE-ANALYSIS-2025-10-12.md) - Codebase analysis and recommendations
- [Query Performance Dashboard](https://grafana.jclee.me/d/query-performance) - Query latency monitoring

---

**Last Updated**: 2025-10-12
**Next Review**: 2025-11-12 (monthly)
