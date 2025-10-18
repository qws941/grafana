# Grafana Monitoring Stack - Demo Guide

This directory contains demonstrations, examples, and visual materials for the Grafana Monitoring Stack.

## Quick Start

### Access Information

```
Grafana:       https://grafana.jclee.me
Prometheus:    https://prometheus.jclee.me
Loki:          https://loki.jclee.me
AlertManager:  https://alertmanager.jclee.me
```

### Grafana Login

```
URL: https://grafana.jclee.me
Username: admin
Password: (from .env GRAFANA_ADMIN_PASSWORD)
```

### Main Dashboards

**Core Monitoring**:
- Monitoring Stack Health - Self-monitoring (USE methodology)
- System Metrics - Infrastructure monitoring

**Applications**:
- n8n Workflow Automation (REDS) - Application monitoring
- Container Performance - Docker metrics

**Logs & Alerts**:
- Log Analysis - Log aggregation
- Alert Overview - Active alerts

## Directory Structure

```
demo/
├── README.md                       # This file
├── screenshots/                    # Visual documentation
│   └── README.md                   # Screenshot guidelines
├── videos/                         # Walkthrough videos
│   └── README.md                   # Video creation guidelines
└── examples/                       # Configuration examples
    ├── sample-dashboard.json       # REDS methodology dashboard
    ├── sample-alert-rule.yml       # Alert rule examples
    ├── sample-recording-rule.yml   # Recording rule examples
    └── sample-promtail-config.yml  # Log collection config
```

## Example Files

### 1. Sample Dashboard (REDS Methodology)

**File**: `examples/sample-dashboard.json`

Complete Grafana dashboard example implementing the REDS methodology:
- **Rate**: Request rate per minute
- **Errors**: 5xx error rate
- **Duration**: Response time P99
- **Saturation**: Active connections

**Features**:
- 6 panels (4 stat panels + 2 time series)
- Proper threshold configuration (green/yellow/red)
- Correct datasource UIDs
- Panel descriptions with thresholds
- Validated metrics (no "No Data" panels)

**Usage**:
```bash
# Copy to provisioning directory
cp demo/examples/sample-dashboard.json \
   configs/provisioning/dashboards/my-app-dashboard.json

# Auto-synced and loaded within 11-12 seconds
# Verify: https://grafana.jclee.me/dashboards
```

### 2. Sample Alert Rules

**File**: `examples/sample-alert-rule.yml`

Alert rule examples with best practices:
- **ServiceDown**: Critical - Service unavailable (2m threshold)
- **HighErrorRate**: Warning - Error rate >5% (5m threshold)
- **HighResponseTime**: Warning - P99 >1s (10m threshold)
- **HighMemoryUsage**: Info - Memory >80% (15m threshold)

**Features**:
- Severity levels (critical, warning, info)
- Proper `for` durations to reduce noise
- Rich annotations (summary, description, runbook links)
- Labels for routing (severity, team, service)
- Common alert patterns documented

**Usage**:
```bash
# Add to alert rules
cat demo/examples/sample-alert-rule.yml >> configs/alert-rules.yml

# Reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# Verify: https://prometheus.jclee.me/alerts
```

### 3. Sample Recording Rules

**File**: `examples/sample-recording-rule.yml`

Recording rule examples for performance optimization:
- **Performance metrics**: Request rate, error rate, response time percentiles
- **Resource metrics**: CPU/memory usage, network throughput
- **Business metrics**: Active users, transaction success rate

**Features**:
- Proper naming convention (level:metric:operations)
- Multiple time windows (1m, 5m)
- Label preservation
- Extensive documentation on use cases and best practices

**Usage**:
```bash
# Add to recording rules
cat demo/examples/sample-recording-rule.yml >> configs/recording-rules.yml

# Reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# Query recorded metric
curl -s "https://prometheus.jclee.me/api/v1/query?query=service:http_requests:rate5m"
```

### 4. Sample Promtail Configuration

**File**: `examples/sample-promtail-config.yml`

Promtail configuration examples for log collection:
- **Docker containers**: Auto-discovery via docker_sd_configs
- **System logs**: Static file paths
- **Application logs**: Custom parsing with pipeline stages
- **Nginx logs**: Access and error log parsing

**Features**:
- Pipeline stages (regex, json, timestamp, labels, match, metrics)
- Label best practices (low cardinality)
- Common use cases (multi-line, filtering, rate limiting)
- Performance tuning for high-volume logging

**Usage**:
```bash
# Test configuration locally
promtail -config.file=demo/examples/sample-promtail-config.yml -dry-run

# Copy specific job to production config
# (manually merge, don't replace entire file)
vim configs/promtail-config.yml

# Restart Promtail
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"
```

## Demo Scenarios

### Scenario 1: Service Metrics

#### 1.1 Prometheus Metrics Query

```bash
# Query request rate
curl -s "https://prometheus.jclee.me/api/v1/query?query=rate(http_requests_total\{job=\"my-service\"\}[5m])" | jq '.'

# Query error rate
curl -s "https://prometheus.jclee.me/api/v1/query?query=rate(http_requests_total\{job=\"my-service\",status=~\"5..\"\}[5m])" | jq '.'
```

#### 1.2 Grafana Dashboard Exploration

```
1. Access https://grafana.jclee.me
2. Navigate to Explore → Select Prometheus
3. Query: rate(http_requests_total{job="my-service"}[5m])
4. Run Query → View graph
5. Add multiple queries for comparison
```

### Scenario 2: Log Analysis

#### 2.1 Loki Log Query

```
1. Grafana → Explore
2. Data source: Loki
3. LogQL query: {job="my-service"} |~ "error|ERROR"
4. Run Query → View error logs
5. Filter by time range
```

#### 2.2 Real-time Log Streaming

```
1. Explore → Loki
2. Query: {job="my-service"}
3. Click "Live" button
4. Watch real-time log stream
```

#### 2.3 Log Pattern Detection

```logql
# Detect errors with rate
rate({job="my-service"} |~ "error|ERROR" [5m])

# Parse JSON logs
{job="my-service"} | json | level="error"

# Extract fields
{job="my-service"} | logfmt | duration > 1s
```

### Scenario 3: Alert Configuration

#### 3.1 Create Alert Rule

```yaml
# Add to configs/alert-rules.yml
groups:
  - name: my_service_alerts
    rules:
      - alert: HighErrorRate
        expr: |
          rate(http_requests_total{job="my-service",status=~"5.."}[5m])
          / rate(http_requests_total{job="my-service"}[5m])
          > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate for my-service"
          description: "Error rate is {{ $value | humanizePercentage }}"
```

#### 3.2 Verify Alert

```bash
# Reload Prometheus
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"

# Check alert rules
curl -s https://prometheus.jclee.me/api/v1/rules | jq '.data.groups[].rules[] | select(.name=="HighErrorRate")'

# View in AlertManager
open https://alertmanager.jclee.me
```

### Scenario 4: Dashboard Creation

#### 4.1 Using REDS Methodology

Follow the `examples/sample-dashboard.json` template:

1. **Rate panel**: `rate(http_requests_total[5m]) * 60`
2. **Errors panel**: `rate(http_requests_total{status=~"5.."}[5m]) * 60`
3. **Duration panel**: `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))`
4. **Saturation panel**: `active_connections`

#### 4.2 Validate Metrics First (CRITICAL)

```bash
# List all available metrics
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep my_service

# Test query returns data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=http_requests_total{job=\"my-service\"}'" | \
  jq '.data.result'
```

#### 4.3 Deploy Dashboard

```bash
# Save dashboard JSON to provisioning directory
vim configs/provisioning/dashboards/my-service-dashboard.json

# Auto-synced within 1-2s, Grafana loads within 10s
# Total latency: 11-12 seconds

# Verify dashboard loaded
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container curl -s -u admin:bingogo1 \
  'http://localhost:3000/api/dashboards/uid/my-service'" | \
  jq '.dashboard.title'
```

## Advanced Usage

### PromQL Query Examples

#### Service Availability

```promql
# Service UP status
up{job="my-service"}

# Average response time (5m)
rate(http_request_duration_seconds_sum{job="my-service"}[5m])
/ rate(http_request_duration_seconds_count{job="my-service"}[5m])

# P99 latency
histogram_quantile(0.99,
  rate(http_request_duration_seconds_bucket{job="my-service"}[5m])
)

# Success rate (percentage)
(
  rate(http_requests_total{job="my-service",status!~"5.."}[5m])
  / rate(http_requests_total{job="my-service"}[5m])
) * 100
```

#### Resource Utilization

```promql
# CPU usage (percentage)
rate(container_cpu_usage_seconds_total{name="my-service-container"}[5m]) * 100

# Memory usage (percentage)
(
  container_memory_usage_bytes{name="my-service-container"}
  / container_spec_memory_limit_bytes{name="my-service-container"}
) * 100

# Network receive rate (bytes/sec)
rate(container_network_receive_bytes_total{name="my-service-container"}[5m])

# Disk I/O rate
rate(container_fs_reads_bytes_total{name="my-service-container"}[5m])
+ rate(container_fs_writes_bytes_total{name="my-service-container"}[5m])
```

### LogQL Query Examples

#### Log Filtering

```logql
# Error logs only
{job="my-service"} |~ "error|ERROR|exception"

# Specific time range with JSON parsing
{job="my-service"} | json | level="error"

# Rate calculation from logs
rate({job="my-service"} |~ "error" [5m])

# Count by field
sum by (status) (count_over_time({job="my-service"} | json [5m]))
```

#### Pattern Extraction

```logql
# Extract duration from logs
{job="my-service"} | logfmt | duration > 1s

# Parse custom format
{job="my-service"} | regexp "duration=(?P<duration>\\d+\\.\\d+)"

# Aggregate by extracted field
avg_over_time({job="my-service"} | logfmt | unwrap duration [5m])
```

### Dashboard Variables

Create dynamic dashboards with variables:

```
1. Dashboard Settings → Variables → Add Variable
2. Name: service
3. Type: Query
4. Data source: Prometheus
5. Query: label_values(up, job)
6. Usage in panels: up{job="$service"}
```

### Metrics from Logs

Export Prometheus metrics from log patterns:

```yaml
# In promtail-config.yml
pipeline_stages:
  - metrics:
      error_count:
        type: Counter
        description: "Total error logs"
        source: level
        config:
          value: error
          action: inc
```

## Troubleshooting

### Issue 1: Grafana Unreachable

```bash
# Check Synology NAS connectivity
ping 192.168.50.215

# Check Grafana container (on Synology)
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep grafana"

# View logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs grafana-container --tail 50"

# Restart if needed
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
```

### Issue 2: Prometheus Metrics Missing

```bash
# Check Prometheus targets
curl -s https://prometheus.jclee.me/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Verify service metrics endpoint
curl http://my-service:port/metrics

# Check Prometheus logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs prometheus-container --tail 50"

# Verify scrape config
ssh -p 1111 jclee@192.168.50.215 "cat /volume1/grafana/configs/prometheus.yml | grep my-service"
```

### Issue 3: Loki Logs Not Appearing

```bash
# Check Promtail status
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep promtail"

# View Promtail logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs promtail-container --tail 50"

# Test Loki connectivity
curl https://loki.jclee.me/ready

# Query Loki directly
curl -s "https://loki.jclee.me/loki/api/v1/query?query={job=\"my-service\"}&limit=10" | jq '.'

# Common causes:
# 1. Logs older than 3 days (Loki retention)
# 2. Synology 'db' driver (unsupported by Promtail)
# 3. Missing volume mounts in promtail container
```

### Issue 4: Dashboard Shows "No Data"

```bash
# Validate metric exists (CRITICAL STEP)
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep your_metric

# Test query in Prometheus
curl -s "https://prometheus.jclee.me/api/v1/query?query=your_metric" | jq '.data.result'

# Run validation script
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/my-dashboard.json

# Common causes:
# 1. Metric doesn't exist (NOT VALIDATED) ← Most common!
# 2. Wrong datasource UID (should be "prometheus" or "loki")
# 3. Query syntax error
# 4. Wrong percentile (e.g., p95 vs p99)
```

### Issue 5: Real-time Sync Not Working

```bash
# Check sync service status
sudo systemctl status grafana-sync

# View sync logs
sudo journalctl -u grafana-sync -n 50

# Manual sync test
/home/jclee/app/grafana/scripts/realtime-sync.sh

# Restart sync service
sudo systemctl restart grafana-sync

# Verify file synced to NAS
ssh -p 1111 jclee@192.168.50.215 "ls -lh /volume1/grafana/configs/prometheus.yml"
```

## Visual Documentation

### Screenshots

See `screenshots/README.md` for complete list of required screenshots:
- Core monitoring dashboards
- Configuration pages
- Operations workflows
- Health check outputs

**Guidelines**: PNG format, 1920x1080+ resolution

### Videos

See `videos/README.md` for complete list of required videos:
- Initial setup walkthrough (5-10 min)
- Configuration changes (2-3 min each)
- Troubleshooting workflow (5-7 min)

**Guidelines**: MP4 (H.264), 1920x1080, 30fps, with narration

## Related Documentation

- [Architecture Documentation](../resume/architecture.md)
- [API Documentation](../resume/api.md)
- [Deployment Guide](../resume/deployment.md)
- [Troubleshooting Guide](../resume/troubleshooting.md)
- [Project README](../README.md)
- [Prometheus Configuration](../configs/prometheus.yml)
- [Grafana Official Docs](https://grafana.com/docs/)
- [Prometheus Official Docs](https://prometheus.io/docs/)
- [Loki Official Docs](https://grafana.com/docs/loki/)

## Contributing Examples

To add new examples to this directory:

1. **Validate configuration** syntax (shellcheck, yamllint, JSON validator)
2. **Test in production** environment (verify it works)
3. **Document thoroughly** (add comments explaining each section)
4. **Follow naming convention**: `sample-<description>.<ext>`
5. **Update this README** with usage instructions
6. **Submit for review** (ensure Constitutional Framework compliance)

## Metrics Validation (MANDATORY)

Before creating dashboards or recording rules, ALWAYS validate metrics exist:

```bash
# Use validation script
./scripts/validate-metrics.sh --list | grep your_metric

# Or query Prometheus directly
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=your_metric'" | \
  jq '.data.result | length'
```

**Historical Incident (2025-10-13)**: Dashboard used `n8n_nodejs_eventloop_lag_p95_seconds` which doesn't exist. n8n only exposes P50, P90, P99. This caused "No Data" panels. See `docs/METRICS-VALIDATION-2025-10-12.md`.

## Support

For questions or issues:
- Check [Troubleshooting Guide](../resume/troubleshooting.md)
- Review [Architecture Documentation](../resume/architecture.md)
- Consult [CLAUDE.md](../CLAUDE.md) for project-specific guidance
- Review Constitutional Framework at `~/.claude/CLAUDE.md`
