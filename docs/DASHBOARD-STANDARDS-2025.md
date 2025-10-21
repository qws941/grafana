# Grafana Dashboard Standards (2025)

**Version**: 1.0
**Last Updated**: 2025-10-20
**Status**: Active

## Overview

This document defines the standards for all Grafana dashboards in our monitoring stack. Following these standards ensures consistency, maintainability, and optimal performance across all dashboards.

## Table of Contents

1. [Dashboard Metadata](#dashboard-metadata)
2. [Design Standards](#design-standards)
3. [Performance Guidelines](#performance-guidelines)
4. [Query Optimization](#query-optimization)
5. [Naming Conventions](#naming-conventions)
6. [Folder Structure](#folder-structure)
7. [Methodology Application](#methodology-application)

---

## Dashboard Metadata

### Required Fields

Every dashboard **MUST** include:

```json
{
  "uid": "unique-dashboard-id",
  "title": "Category - Dashboard Name (Methodology)",
  "description": "Detailed description of dashboard purpose and scope",
  "tags": ["category", "methodology", "service-name"],
  "timezone": "browser",
  "schemaVersion": 38,
  "version": 1,
  "refresh": "30s",
  "time": {
    "from": "now-1h",
    "to": "now"
  }
}
```

### Field Specifications

#### UID
- Format: `kebab-case-name`
- Must be unique across all dashboards
- Cannot be changed after creation (breaks links)
- Example: `n8n-workflow-automation-reds`

#### Title
- Format: `[Category] - [Name] ([Methodology])`
- Categories: `Applications`, `Infrastructure`, `Core`, `Logging`, `Alerting`
- Examples:
  - `Applications - n8n Workflow Automation (REDS)`
  - `Infrastructure - Complete Overview (USE)`
  - `Core - Monitoring Stack Complete`

#### Description
- Minimum 50 characters
- Include dashboard purpose, key metrics, and use cases
- Mention data sources and refresh intervals
- Example:
  ```
  Comprehensive n8n workflow monitoring dashboard using REDS methodology.
  Tracks workflow execution rates, error rates, response times, and resource
  utilization. Updates every 30 seconds. Created 2025-10-20.
  ```

#### Tags
- Minimum 2 tags required
- Always include:
  - Category tag (applications, infrastructure, logging, etc.)
  - Methodology tag (reds, use, golden-signals)
  - Service name tags (n8n, grafana, prometheus, etc.)
- Example: `["applications", "n8n", "reds-methodology"]`

#### Refresh
- **Standard**: `30s` for real-time dashboards
- **High frequency**: `10s` for critical alerts
- **Low frequency**: `1m` or `5m` for historical analysis
- **Never**: omit or use `""` (causes browser default behavior)

#### Schema Version
- Always use latest: `38` (as of Grafana 11.3)
- Update when upgrading Grafana versions

---

## Design Standards

### Color Palette

Use consistent colors across all dashboards:

#### Status Colors
```yaml
Success/Up:     #73BF69  (green)
Warning:        #FF9830  (orange)
Error/Down:     #E02F44  (red)
Info:           #5794F2  (blue)
Neutral:        #B7B7B7  (gray)
```

#### Thresholds
```yaml
# For percentage metrics (0-100)
Good:     [85, 100]   → Green
Warning:  [70, 85)    → Yellow
Critical: [0, 70)     → Red

# For error rates
Good:     [0, 1)      → Green
Warning:  [1, 5)      → Yellow
Critical: [5, ∞)      → Red

# For latency (seconds)
Good:     [0, 0.5)    → Green
Warning:  [0.5, 1.0)  → Yellow
Critical: [1.0, ∞)    → Red
```

### Panel Layout

#### Golden Signals (First Row)
- **Height**: 4 units
- **Width**: 6 units each (4 panels total)
- **Type**: `stat` with background color
- **Position**: Top row (y=0)
- **Order**: Rate → Errors → Duration → Saturation

Example:
```
┌─────────┬─────────┬─────────┬─────────┐
│  RATE   │ ERRORS  │DURATION │SATURATION│
│  (6x4)  │ (6x4)   │ (6x4)   │ (6x4)    │
└─────────┴─────────┴─────────┴─────────┘
```

#### Detail Panels (Subsequent Rows)
- **Height**: 6-8 units
- **Width**: 12 or 24 units
- **Type**: `timeseries` or `gauge` or `table`
- Use rows to organize related panels

### Panel Configuration

#### Time Series Defaults
```json
{
  "type": "timeseries",
  "options": {
    "tooltip": {"mode": "multi"},
    "legend": {
      "displayMode": "list",
      "placement": "bottom",
      "showLegend": true,
      "calcs": ["mean", "last", "max"]
    }
  },
  "fieldConfig": {
    "defaults": {
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 10,
        "lineWidth": 2,
        "showPoints": "never"
      },
      "unit": "short",
      "decimals": 2
    }
  }
}
```

#### Stat Panel Defaults
```json
{
  "type": "stat",
  "options": {
    "graphMode": "area",
    "colorMode": "background",
    "textMode": "value_and_name",
    "orientation": "auto"
  },
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "decimals": 2,
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"color": "red", "value": null},
          {"color": "yellow", "value": 70},
          {"color": "green", "value": 85}
        ]
      }
    }
  }
}
```

### Units

Use appropriate units for metrics:

| Metric Type | Unit | Display |
|-------------|------|---------|
| Bytes | `bytes` | Auto-scaled (KB, MB, GB) |
| Bits/sec | `bps` | Auto-scaled (Kbps, Mbps) |
| Percentage | `percent` | 0-100 |
| Duration | `s` or `ms` | Seconds or milliseconds |
| Count | `short` | Plain number |
| Currency | `currencyUSD` | $0.00 |
| Requests/sec | `ops` | Operations per second |

---

## Performance Guidelines

### Query Optimization

#### Use Recording Rules
Always prefer recording rules for complex or frequently used queries:

```promql
# ❌ BAD: Complex query in dashboard
rate(node_cpu_seconds_total{mode!="idle"}[5m]) * 100

# ✅ GOOD: Use recording rule
instance:node_cpu_utilization:rate5m
```

#### Minimize Label Cardinality
```promql
# ❌ BAD: Includes all labels
container_memory_usage_bytes

# ✅ GOOD: Filter labels
container_memory_usage_bytes{name!=""}
```

#### Use Appropriate Time Ranges
```promql
# ❌ BAD: 1m rate for 30s refresh
rate(metric[1m])

# ✅ GOOD: 5m rate for stable results
rate(metric[5m])
```

### Dashboard Performance

#### Panel Count Guidelines
- **Simple Dashboard**: 5-10 panels
- **Standard Dashboard**: 10-20 panels
- **Complex Dashboard**: 20-30 panels
- **Maximum**: 35 panels (beyond this, split into multiple dashboards)

#### Query Interval
Match query interval to visualization needs:
- **Real-time**: `$__interval` (auto-adjust)
- **Aggregated**: `1m` or `5m` fixed interval

---

## Query Optimization

### Recording Rules Strategy

**When to create a recording rule**:
1. Query used in 3+ dashboards
2. Query takes >1s to execute
3. Query has 2+ aggregation functions
4. Query runs more than once per minute

**Example recording rule**:
```yaml
- record: service:request_rate:5m
  expr: rate(http_requests_total[5m]) * 60
```

### Template Variables

Use template variables for dynamic filtering:

```json
{
  "templating": {
    "list": [
      {
        "name": "instance",
        "label": "Instance",
        "type": "query",
        "query": "label_values(up, instance)",
        "refresh": 2,
        "multi": true,
        "includeAll": true
      }
    ]
  }
}
```

Then use in queries:
```promql
up{instance=~"$instance"}
```

---

## Naming Conventions

### Metric Names
Follow Prometheus naming conventions:

```
<namespace>_<subsystem>_<metric>_<unit>_<suffix>
```

Examples:
- `n8n_workflow_started_total` (counter)
- `prometheus_tsdb_storage_blocks_bytes` (gauge)
- `http_request_duration_seconds_bucket` (histogram)

### Label Names
- Use `snake_case`
- Avoid spaces and special characters
- Keep names short but descriptive
- Examples: `job`, `instance`, `status`, `error_type`, `context`

### Recording Rule Names
```
<level>:<metric>:<aggregation>
```

Examples:
- `instance:node_cpu_utilization:rate5m`
- `job:http_requests:rate1m`
- `cluster:memory:usage_ratio`

---

## Folder Structure

```
configs/provisioning/dashboards/
├── core-monitoring/          # Self-monitoring of observability stack
│   ├── monitoring-stack-complete.json
│   ├── context-based-target-monitoring.json
│   └── codebase-health-analysis.json
├── infrastructure/           # System and container metrics (USE)
│   ├── infrastructure-complete.json
│   └── traefik-reverse-proxy-reds.json
├── applications/             # Application-specific monitoring (REDS)
│   ├── n8n-workflow-automation-reds.json
│   ├── ai-agents-monitoring-reds.json
│   ├── hycu-automation-reds.json
│   └── ai-agent-costs-reds.json
├── logging/                  # Log aggregation and analysis
│   └── log-analysis.json
└── alerting/                 # Alert management and overview
    └── alert-overview.json
```

### Folder Assignment Rules

1. **Core-Monitoring**: Dashboards monitoring the observability stack itself
2. **Infrastructure**: System-level metrics (CPU, memory, disk, network, containers)
3. **Applications**: Business/application metrics using REDS methodology
4. **Logging**: Log-based dashboards
5. **Alerting**: Alert status and management dashboards

---

## Methodology Application

### REDS (for Applications)

**Rate-Errors-Duration-Saturation**

#### Panel 1: Rate
```promql
# Request throughput
rate(http_requests_total[5m]) * 60
```
- **Unit**: `ops` (requests per minute)
- **Threshold**: Baseline-dependent
- **Visualization**: Stat + Time series

#### Panel 2: Errors
```promql
# Error rate percentage
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100
```
- **Unit**: `percent`
- **Threshold**: <1% green, 1-5% yellow, >5% red
- **Visualization**: Stat + Time series

#### Panel 3: Duration
```promql
# Response time P99
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```
- **Unit**: `s`
- **Threshold**: <0.5s green, 0.5-1s yellow, >1s red
- **Visualization**: Stat + Time series

#### Panel 4: Saturation
```promql
# Active connections
http_active_connections
```
- **Unit**: `short`
- **Threshold**: Service-specific
- **Visualization**: Stat + Time series

### USE (for Infrastructure)

**Utilization-Saturation-Errors**

#### Panel 1: Utilization
```promql
# CPU utilization
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```
- **Unit**: `percent`
- **Threshold**: <70% green, 70-85% yellow, >85% red

#### Panel 2: Saturation
```promql
# Load average normalized
node_load1 / count without (cpu, mode) (node_cpu_seconds_total{mode="idle"})
```
- **Unit**: `short`
- **Threshold**: <1.0 green, 1-2 yellow, >2 red

#### Panel 3: Errors
```promql
# Network errors
rate(node_network_receive_errs_total[5m])
```
- **Unit**: `ops`
- **Threshold**: 0 green, >0 red

---

## Validation Checklist

Before deploying a new dashboard, verify:

- [ ] UID is unique and descriptive
- [ ] Title follows naming convention
- [ ] Description is present and detailed
- [ ] Appropriate tags are applied
- [ ] Refresh interval is set (default: 30s)
- [ ] Schema version is 38
- [ ] Golden Signals in first row (if applicable)
- [ ] Consistent color scheme applied
- [ ] Appropriate units for all panels
- [ ] All metrics validated in Prometheus
- [ ] Recording rules created for complex queries
- [ ] Template variables used where appropriate
- [ ] Dashboard tested at various time ranges
- [ ] Performance: <35 panels total
- [ ] Documentation: Panel titles are descriptive

---

## Maintenance

### Regular Reviews
- **Monthly**: Review dashboard usage and performance
- **Quarterly**: Update thresholds based on baseline changes
- **Annually**: Audit all dashboards for deprecations and improvements

### Version Control
- All dashboards must be in git
- Use JSON formatting (2-space indent)
- No manual edits in Grafana UI (auto-provisioning overwrites)
- Changes via Pull Request with review

### Deprecation Process
1. Mark dashboard as `[DEPRECATED]` in title
2. Add deprecation notice to description
3. Wait 30 days for user feedback
4. Remove dashboard if no objections

---

## Resources

- [Grafana Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)
- [REDS Methodology](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- [USE Method](http://www.brendangregg.com/usemethod.html)
- [Prometheus Naming](https://prometheus.io/docs/practices/naming/)

---

## Changelog

### 2025-10-20
- Initial version
- Defined dashboard metadata standards
- Established design guidelines
- Added REDS/USE methodology application
- Created validation checklist

---

**Document Owner**: DevOps Team
**Review Cycle**: Quarterly
**Next Review**: 2026-01-20
