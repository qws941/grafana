# API Documentation

## Overview

This document describes the API endpoints and integration points for the Grafana Monitoring Stack.

---

## Grafana API

### Base URL
```
https://grafana.jclee.me
```

### Authentication
All Grafana API requests require Basic Auth:
```bash
curl -u admin:${GRAFANA_ADMIN_PASSWORD} https://grafana.jclee.me/api/...
```

### Health Check

**Endpoint**: `/api/health`
**Method**: GET
**Auth**: None required

**Example**:
```bash
curl -sf https://grafana.jclee.me/api/health
```

**Response** (200 OK):
```json
{
  "commit": "...",
  "database": "ok",
  "version": "10.2.3"
}
```

### List Dashboards

**Endpoint**: `/api/search?type=dash-db`
**Method**: GET
**Auth**: Basic Auth required

**Example**:
```bash
curl -u admin:bingogo1 \
  https://grafana.jclee.me/api/search?type=dash-db | jq '.'
```

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "uid": "monitoring-stack-health",
    "title": "Monitoring Stack Health",
    "uri": "db/monitoring-stack-health",
    "url": "/d/monitoring-stack-health/monitoring-stack-health",
    "type": "dash-db",
    "tags": ["core-monitoring"],
    "isStarred": false
  }
]
```

### Get Dashboard by UID

**Endpoint**: `/api/dashboards/uid/:uid`
**Method**: GET
**Auth**: Basic Auth required

**Example**:
```bash
curl -u admin:bingogo1 \
  https://grafana.jclee.me/api/dashboards/uid/monitoring-stack-health | \
  jq '.dashboard.title'
```

**Response** (200 OK):
```json
{
  "meta": {
    "type": "db",
    "canSave": true,
    "canEdit": true,
    "canAdmin": true
  },
  "dashboard": {
    "id": 1,
    "uid": "monitoring-stack-health",
    "title": "Monitoring Stack Health",
    "panels": [...]
  }
}
```

### List Datasources

**Endpoint**: `/api/datasources`
**Method**: GET
**Auth**: Basic Auth required

**Example**:
```bash
curl -u admin:bingogo1 \
  https://grafana.jclee.me/api/datasources | jq '.'
```

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "uid": "prometheus",
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus-container:9090",
    "isDefault": true
  },
  {
    "id": 2,
    "uid": "loki",
    "name": "Loki",
    "type": "loki",
    "url": "http://loki-container:3100",
    "isDefault": false
  }
]
```

### Helper Script

**Location**: `scripts/grafana-api.sh`

**Usage**:
```bash
# List datasources
./scripts/grafana-api.sh datasources

# List dashboards
./scripts/grafana-api.sh dashboards

# Get dashboard by UID
./scripts/grafana-api.sh dashboard <uid>
```

---

## Prometheus API

### Base URL
```
https://prometheus.jclee.me
```

### Authentication
No authentication required (internal network only, external access via Traefik)

### Health Check

**Endpoint**: `/-/healthy`
**Method**: GET

**Example**:
```bash
curl -sf https://prometheus.jclee.me/-/healthy
```

**Response** (200 OK):
```
Prometheus is Healthy.
```

### Readiness Check

**Endpoint**: `/-/ready`
**Method**: GET

**Example**:
```bash
curl -sf https://prometheus.jclee.me/-/ready
```

**Response** (200 OK):
```
Prometheus is Ready.
```

### Query Metrics

**Endpoint**: `/api/v1/query`
**Method**: GET
**Parameters**:
- `query` (required) - PromQL query string
- `time` (optional) - Evaluation timestamp (default: current time)

**Example**:
```bash
curl -s "https://prometheus.jclee.me/api/v1/query?query=up" | jq '.'
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "up",
          "job": "prometheus",
          "instance": "prometheus-container:9090"
        },
        "value": [1697548800, "1"]
      }
    ]
  }
}
```

### Query Range (Time Series)

**Endpoint**: `/api/v1/query_range`
**Method**: GET
**Parameters**:
- `query` (required) - PromQL query string
- `start` (required) - Start timestamp
- `end` (required) - End timestamp
- `step` (optional) - Query resolution step (default: auto)

**Example**:
```bash
curl -s "https://prometheus.jclee.me/api/v1/query_range?query=up&start=2025-10-17T00:00:00Z&end=2025-10-17T23:59:59Z&step=1h" | jq '.'
```

### List Targets

**Endpoint**: `/api/v1/targets`
**Method**: GET

**Example**:
```bash
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": {
    "activeTargets": [
      {
        "discoveredLabels": {...},
        "labels": {
          "job": "prometheus",
          "instance": "prometheus-container:9090"
        },
        "scrapePool": "prometheus",
        "scrapeUrl": "http://prometheus-container:9090/metrics",
        "globalUrl": "http://prometheus-container:9090/metrics",
        "lastError": "",
        "lastScrape": "2025-10-17T08:00:00.000Z",
        "lastScrapeDuration": 0.005,
        "health": "up"
      }
    ]
  }
}
```

### List Metrics (Label Values)

**Endpoint**: `/api/v1/label/__name__/values`
**Method**: GET

**Example**:
```bash
curl -s https://prometheus.jclee.me/api/v1/label/__name__/values | \
  jq -r '.data[]' | grep n8n
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": [
    "n8n_active_workflow_count",
    "n8n_workflow_started_total",
    "n8n_cache_hits_total",
    "n8n_cache_misses_total"
  ]
}
```

### Reload Configuration

**Endpoint**: `/-/reload`
**Method**: POST
**Auth**: None required (enabled with --web.enable-lifecycle)

**Example**:
```bash
curl -X POST https://prometheus.jclee.me/-/reload
```

**Response** (200 OK):
```
(empty response on success)
```

### List Rules (Recording + Alerting)

**Endpoint**: `/api/v1/rules`
**Method**: GET

**Example**:
```bash
curl -s https://prometheus.jclee.me/api/v1/rules | \
  jq '.data.groups[] | {name: .name, rules: (.rules | length)}'
```

### List Alerts

**Endpoint**: `/api/v1/alerts`
**Method**: GET

**Example**:
```bash
curl -s https://prometheus.jclee.me/api/v1/alerts | \
  jq '.data.alerts[] | {name: .labels.alertname, state: .state}'
```

---

## Loki API

### Base URL
```
https://loki.jclee.me
```

### Authentication
No authentication required (internal network only)

### Readiness Check

**Endpoint**: `/ready`
**Method**: GET

**Example**:
```bash
curl -sf https://loki.jclee.me/ready
```

**Response** (200 OK):
```
ready
```

### Query Logs

**Endpoint**: `/loki/api/v1/query`
**Method**: GET
**Parameters**:
- `query` (required) - LogQL query string
- `limit` (optional) - Max entries to return (default: 100)
- `time` (optional) - Query timestamp

**Example**:
```bash
curl -s --get \
  --data-urlencode 'query={job="grafana"}' \
  --data-urlencode 'limit=10' \
  https://loki.jclee.me/loki/api/v1/query | jq '.'
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": {
    "resultType": "streams",
    "result": [
      {
        "stream": {
          "job": "grafana",
          "container_name": "grafana-container"
        },
        "values": [
          ["1697548800000000000", "log line content"]
        ]
      }
    ]
  }
}
```

### Query Range (Log Stream)

**Endpoint**: `/loki/api/v1/query_range`
**Method**: GET
**Parameters**:
- `query` (required) - LogQL query string
- `start` (optional) - Start timestamp
- `end` (optional) - End timestamp
- `limit` (optional) - Max entries (default: 100)

**Example**:
```bash
curl -s --get \
  --data-urlencode 'query={job="grafana"} |= "error"' \
  --data-urlencode 'start=1697548800000000000' \
  --data-urlencode 'limit=50' \
  https://loki.jclee.me/loki/api/v1/query_range | jq '.'
```

### List Labels

**Endpoint**: `/loki/api/v1/labels`
**Method**: GET

**Example**:
```bash
curl -s https://loki.jclee.me/loki/api/v1/labels | jq '.data[]'
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": [
    "job",
    "container_name",
    "host",
    "environment"
  ]
}
```

### List Label Values

**Endpoint**: `/loki/api/v1/label/:name/values`
**Method**: GET

**Example**:
```bash
curl -s https://loki.jclee.me/loki/api/v1/label/job/values | jq '.data[]'
```

**Response** (200 OK):
```json
{
  "status": "success",
  "data": [
    "grafana",
    "prometheus",
    "loki",
    "promtail"
  ]
}
```

---

## AlertManager API

### Base URL
```
https://alertmanager.jclee.me
```

### Authentication
No authentication required (internal network only)

### Health Check

**Endpoint**: `/-/healthy`
**Method**: GET

**Example**:
```bash
curl -sf https://alertmanager.jclee.me/-/healthy
```

**Response** (200 OK):
```
OK
```

### List Alerts

**Endpoint**: `/api/v2/alerts`
**Method**: GET

**Example**:
```bash
curl -s https://alertmanager.jclee.me/api/v2/alerts | jq '.'
```

**Response** (200 OK):
```json
[
  {
    "labels": {
      "alertname": "PrometheusTargetDown",
      "severity": "critical",
      "job": "n8n"
    },
    "annotations": {
      "description": "Prometheus target n8n is down",
      "summary": "Target down"
    },
    "startsAt": "2025-10-17T08:00:00.000Z",
    "endsAt": "0001-01-01T00:00:00.000Z",
    "generatorURL": "https://prometheus.jclee.me/...",
    "status": {
      "state": "active",
      "silencedBy": [],
      "inhibitedBy": []
    }
  }
]
```

### List Silences

**Endpoint**: `/api/v2/silences`
**Method**: GET

**Example**:
```bash
curl -s https://alertmanager.jclee.me/api/v2/silences | jq '.'
```

### Create Silence

**Endpoint**: `/api/v2/silences`
**Method**: POST
**Body**: JSON

**Example**:
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {"name": "alertname", "value": "PrometheusTargetDown", "isRegex": false}
    ],
    "startsAt": "2025-10-17T08:00:00.000Z",
    "endsAt": "2025-10-17T10:00:00.000Z",
    "createdBy": "admin",
    "comment": "Maintenance window"
  }' \
  https://alertmanager.jclee.me/api/v2/silences
```

---

## Webhook Integration (n8n)

### AlertManager Webhook

**Endpoint**: Configured in `configs/alertmanager.yml`

**Webhook URL**:
```
https://n8n.jclee.me/webhook/alertmanager
```

**Payload Structure**:
```json
{
  "version": "4",
  "groupKey": "...",
  "status": "firing",
  "receiver": "default",
  "groupLabels": {
    "alertname": "PrometheusTargetDown"
  },
  "commonLabels": {
    "alertname": "PrometheusTargetDown",
    "severity": "critical"
  },
  "commonAnnotations": {
    "description": "Target down",
    "summary": "Prometheus target is down"
  },
  "externalURL": "https://alertmanager.jclee.me",
  "alerts": [
    {
      "status": "firing",
      "labels": {...},
      "annotations": {...},
      "startsAt": "2025-10-17T08:00:00.000Z",
      "endsAt": "0001-01-01T00:00:00.000Z",
      "generatorURL": "https://prometheus.jclee.me/..."
    }
  ]
}
```

**n8n Workflow**: `configs/n8n-workflows/alertmanager-webhook.json`

**Actions**:
- Parse webhook payload
- Format notification message
- Send to Slack (#alerts channel)
- Create ticket (optional, if critical)
- Log to database (optional)

---

## Metrics Exporters

### AI Metrics Exporter

**Port**: 9091 (on 192.168.50.100)
**Endpoint**: `/metrics`
**Format**: Prometheus text format

**Metrics Exposed**:
```
# AI agent metrics
mcp_ai_requests_total{model="gemini-2.5-pro",status="success"} 1234
mcp_ai_tokens_total{model="gemini-2.5-pro",type="input"} 56789
mcp_ai_cost_total{model="gemini-2.5-pro"} 12.34
mcp_ai_quota_used{model="gemini-2.5-pro",type="requests_per_day"} 45
```

**Example**:
```bash
curl -s http://192.168.50.100:9091/metrics | grep mcp_ai
```

**Source**: `scripts/ai-metrics-exporter/index.js`

### HYCU Automation Exporter

**Port**: 9092 (on 192.168.50.100)
**Endpoint**: `/metrics`
**Format**: Prometheus text format

**Metrics Exposed**:
```
# HYCU backup metrics
hycu_backup_jobs_total{status="success"} 10
hycu_backup_duration_seconds{job="database"} 123.45
hycu_backup_size_bytes{job="database"} 1234567890
```

**Example**:
```bash
curl -s http://192.168.50.100:9092/metrics | grep hycu
```

---

## Client Libraries

### Python Example (Prometheus Query)

```python
import requests

def query_prometheus(query):
    url = "https://prometheus.jclee.me/api/v1/query"
    params = {"query": query}
    response = requests.get(url, params=params)
    return response.json()

# Example usage
result = query_prometheus("up{job='grafana'}")
print(result["data"]["result"])
```

### Python Example (Loki Query)

```python
import requests

def query_loki(query, limit=100):
    url = "https://loki.jclee.me/loki/api/v1/query"
    params = {"query": query, "limit": limit}
    response = requests.get(url, params=params)
    return response.json()

# Example usage
result = query_loki('{job="grafana"} |= "error"')
print(result["data"]["result"])
```

### Bash Example (Health Check)

```bash
#!/bin/bash
# Check all services health

services=(
  "https://grafana.jclee.me/api/health"
  "https://prometheus.jclee.me/-/healthy"
  "https://loki.jclee.me/ready"
  "https://alertmanager.jclee.me/-/healthy"
)

for url in "${services[@]}"; do
  if curl -sf "$url" > /dev/null 2>&1; then
    echo "✅ $url"
  else
    echo "❌ $url"
  fi
done
```

---

## API Rate Limits

### Grafana
- No explicit rate limits
- Recommended: Max 100 requests/minute per client

### Prometheus
- No explicit rate limits
- Query timeout: 2 minutes (configurable)
- Recommended: Use recording rules for frequent queries

### Loki
- Ingestion: No rate limit (internal network)
- Query: No rate limit (internal network)
- Recommended: Use LogQL aggregations for large queries

### AlertManager
- No explicit rate limits
- Webhook retry: 3 attempts with exponential backoff

---

## Error Responses

### Standard Error Format

**HTTP Status Codes**:
- 200: Success
- 400: Bad Request (invalid query syntax)
- 404: Not Found (dashboard/metric not found)
- 500: Internal Server Error
- 503: Service Unavailable

**Grafana Error**:
```json
{
  "message": "Dashboard not found",
  "status": "not-found"
}
```

**Prometheus Error**:
```json
{
  "status": "error",
  "errorType": "bad_data",
  "error": "invalid parameter 'query': parse error at char 5: bad_token"
}
```

**Loki Error**:
```json
{
  "status": "error",
  "message": "parse error at line 1, col 5: syntax error: unexpected IDENTIFIER"
}
```

---

## Best Practices

### Query Optimization

**Prometheus**:
- Use recording rules for frequently queried metrics
- Limit query time range (max 7 days for detailed queries)
- Use metric relabeling to filter at scrape time
- Aggregate data with `sum by (label)` instead of returning all series

**Loki**:
- Use label filters first: `{job="grafana"}`, not `{} |= "grafana"`
- Limit query time range (max 24 hours for detailed queries)
- Use `| json` parser only when needed
- Aggregate logs with `count_over_time()` instead of returning all lines

### Security

**API Keys**:
- Store in `.env` file (gitignored)
- Never commit credentials to git
- Rotate Grafana admin password every 90 days

**Network Access**:
- Keep Prometheus/Loki/AlertManager on internal network only
- External access only via Traefik (SSL)
- Use SSH key authentication for Synology NAS

**Webhook Validation**:
- Verify webhook source (n8n.jclee.me)
- Use HTTPS for all webhook endpoints
- Implement webhook signature validation (future)

---

## Troubleshooting

### Common Issues

**"Connection refused" errors**:
- Check service is running: `docker ps | grep <service>`
- Check network connectivity: `curl http://<service>:<port>/-/healthy`
- Check Traefik routing: `docker logs traefik`

**"No data" in queries**:
- Verify metric exists: `/api/v1/label/__name__/values`
- Check scrape target health: `/api/v1/targets`
- Validate query syntax in Prometheus UI

**Webhook not triggering**:
- Check AlertManager config: `configs/alertmanager.yml`
- Verify alert is firing: `https://alertmanager.jclee.me/api/v2/alerts`
- Check n8n workflow logs

---

## Additional Resources

- Grafana API Docs: https://grafana.com/docs/grafana/latest/developers/http_api/
- Prometheus API Docs: https://prometheus.io/docs/prometheus/latest/querying/api/
- Loki API Docs: https://grafana.com/docs/loki/latest/api/
- AlertManager API Docs: https://prometheus.io/docs/alerting/latest/clients/

---

**Last Updated**: 2025-10-17
**API Version**: 1.0
**Maintainer**: DevOps Team
