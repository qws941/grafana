# AI Cost Dashboard Implementation Guide

**Created**: 2025-10-16  
**Status**: Ready for Instrumentation  
**Dashboard**: AI Agent Costs (REDS)

## Overview

A comprehensive monitoring dashboard for tracking AI agent costs across Grok, Gemini, and Claude providers has been created using REDS methodology (Rate, Errors, Duration, Saturation). The dashboard is **template-ready** but requires metrics instrumentation before it can display data.

## What Was Created

### 1. Dashboard (`configs/provisioning/dashboards/ai-agent-costs-reds.json`)

**Features**:
- ✅ 17 panels across 5 sections (Golden Signals, Cost Analysis, Model Usage, Token Usage, Rate Limits)
- ✅ REDS methodology implementation
- ✅ Multi-provider support (Grok, Gemini, Claude)
- ✅ Cost projections (hourly, daily)
- ✅ Performance metrics (latency percentiles)
- ✅ Token efficiency tracking
- ✅ Rate limit monitoring

**Dashboard Structure**:
```
📊 REDS Golden Signals (Overview)
├── Rate: Total Requests/min
├── Errors: Error Rate (%)
├── Duration: P99 Latency
└── Saturation: Cost/Hour (USD)

💵 Cost Analysis
├── Daily Cost Projection by Provider (timeseries)
├── Cost Distribution by Provider (pie chart)
└── Cumulative Cost by Provider (stacked area)

📊 Model Usage & Performance
├── Request Rate by Model
├── Response Time Percentiles (P50, P95, P99)
└── Model Selection Distribution

🎯 Token Usage
├── Token Rate by Provider & Type (input/output)
├── Average Tokens per Request
└── Token Output/Input Ratio

⚡ Rate Limits & Health
├── Rate Limit Utilization (%)
├── Rate Limit Hits (Throttling)
├── Success Rate by Provider (%)
└── Error Breakdown by Type
```

**Auto-Provisioning**: Grafana scans every 10 seconds → Dashboard appears 10-12 seconds after sync

### 2. Metrics Specification (`docs/AI-METRICS-SPECIFICATION.md`)

**Defines**:
- ✅ 9 core metric types (requests, duration, tokens, cost, rate limits, model selection)
- ✅ Prometheus naming conventions
- ✅ Label specifications (provider, model, operation, status, type)
- ✅ Histogram buckets
- ✅ Example queries
- ✅ TypeScript/Python instrumentation code
- ✅ Cost calculation formulas

**Core Metrics**:
```yaml
Requests:
  - mcp_ai_requests_total (counter)
  - mcp_ai_request_duration_seconds (histogram)

Tokens:
  - mcp_ai_tokens_total (counter)
  - mcp_ai_tokens_per_request (histogram)

Cost:
  - mcp_ai_cost_usd_total (counter)
  - mcp_ai_cost_per_1k_tokens_usd (gauge)

Rate Limits:
  - mcp_ai_rate_limit_remaining (gauge)
  - mcp_ai_rate_limit_hits_total (counter)

Model Selection:
  - mcp_ai_model_selection_total (counter)
```

### 3. Prometheus Configuration

#### Recording Rules (`configs/recording-rules.yml`)

Added **ai_cost_recording_rules** group with 9 rules:
```yaml
Request Metrics:
  - ai:requests:rate5m
  - ai:requests:success_rate

Token Metrics:
  - ai:tokens:rate5m
  - ai:tokens:per_request_avg

Cost Metrics:
  - ai:cost:hourly_usd
  - ai:cost:daily_projection_usd

Latency Metrics:
  - ai:duration:p50
  - ai:duration:p95
  - ai:duration:p99
```

#### Scrape Config (`configs/prometheus.yml`)

Added **ai-agents** job (commented out, ready to enable):
```yaml
- job_name: 'ai-agents'
  static_configs:
    - targets: ['192.168.50.100:9090']  # Update with actual endpoint
  metrics_path: '/metrics'
  scrape_interval: 15s
  metric_relabel_configs:
    - source_labels: [__name__]
      regex: 'mcp_ai_.*'
      action: keep
```

## Implementation Workflow

### Phase 1: Metrics Instrumentation (REQUIRED)

**Status**: ⚠️ NOT YET IMPLEMENTED

You must instrument MCP servers (Grok, Gemini, Claude) to expose Prometheus metrics.

#### Option A: Centralized Metrics Exporter (Recommended)

Create a standalone metrics collector that wraps all MCP calls:

```typescript
// mcp-metrics-exporter/src/index.ts
import express from 'express';
import { register } from 'prom-client';
import { setupMetrics } from './metrics';

const app = express();
const metrics = setupMetrics(register);

// Wrap all MCP calls through this middleware
app.use('/ai-call', async (req, res) => {
  const { provider, model, operation, input } = req.body;
  const startTime = Date.now();
  
  try {
    const result = await callMCP(provider, model, input);
    
    // Record metrics
    metrics.requests.inc({provider, model, operation, status: 'success'});
    metrics.duration.observe({provider, model, operation}, (Date.now() - startTime) / 1000);
    metrics.tokens.inc({provider, model, type: 'input'}, result.inputTokens);
    metrics.tokens.inc({provider, model, type: 'output'}, result.outputTokens);
    
    const cost = calculateCost(provider, model, result.inputTokens, result.outputTokens);
    metrics.cost.inc({provider, model, operation}, cost);
    
    res.json(result);
  } catch (error) {
    metrics.requests.inc({provider, model, operation, status: 'error'});
    res.status(500).json({error: error.message});
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(9090, () => {
  console.log('MCP Metrics Exporter listening on :9090');
});
```

**Implementation Steps**:
1. Create `mcp-metrics-exporter` project
2. Install dependencies: `prom-client`, `express`
3. Copy instrumentation code from `docs/AI-METRICS-SPECIFICATION.md`
4. Update pricing table with actual costs
5. Deploy exporter (Docker recommended)
6. Route all MCP calls through exporter

#### Option B: Direct Instrumentation

Instrument each MCP server individually:

```typescript
// In your MCP client wrapper
import { aiMetrics } from './metrics';

export async function callAI(provider, model, operation, input) {
  const startTime = Date.now();
  
  try {
    const result = await mcp.call({provider, model, input});
    
    // Record metrics
    aiMetrics.recordSuccess(provider, model, operation, 
      Date.now() - startTime, 
      result.inputTokens, 
      result.outputTokens
    );
    
    return result;
  } catch (error) {
    aiMetrics.recordError(provider, model, operation);
    throw error;
  }
}
```

### Phase 2: Enable Prometheus Scraping

Once metrics endpoint is ready:

1. **Update target in `configs/prometheus.yml`**:
```yaml
# Uncomment and update
- job_name: 'ai-agents'
  static_configs:
    - targets: ['your-metrics-exporter:9090']  # Update this!
```

2. **Sync to NAS** (automatic if grafana-sync service running):
```bash
# Check sync status
sudo systemctl status grafana-sync

# Manual sync if needed
rsync -avz configs/ jclee@192.168.50.215:/volume1/grafana/configs/
```

3. **Reload Prometheus**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

4. **Verify target is UP**:
```bash
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.job=="ai-agents")'
```

### Phase 3: Validate Metrics

**CRITICAL**: Always validate metrics exist before assuming dashboard works.

```bash
# List all AI metrics
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/label/__name__/values'" | \
  jq -r '.data[]' | grep 'mcp_ai_'

# Test specific metric returns data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=mcp_ai_requests_total'" | \
  jq '.data.result'

# Verify all dashboard metrics
./scripts/validate-metrics.sh -d configs/provisioning/dashboards/ai-agent-costs-reds.json
```

**Expected Output** (when instrumented):
```
✓ mcp_ai_requests_total
✓ mcp_ai_request_duration_seconds_bucket
✓ mcp_ai_tokens_total
✓ mcp_ai_cost_usd_total
✓ mcp_ai_rate_limit_remaining
✓ mcp_ai_model_selection_total
```

### Phase 4: Access Dashboard

Once metrics are flowing:

1. **Open Grafana**: https://grafana.jclee.me
2. **Navigate to**: Applications folder → "AI Agent Costs (REDS)"
3. **Verify panels show data** (not "No data")

**Dashboard UID**: `ai-agent-costs-reds`  
**Direct URL**: `https://grafana.jclee.me/d/ai-agent-costs-reds`

## Cost Pricing Configuration

**IMPORTANT**: Update pricing in your metrics exporter to reflect actual costs.

Current pricing is **EXAMPLE ONLY**:

```typescript
const PRICING = {
  grok: {
    'grok-code-fast-1': { input: 0.0001, output: 0.0002 },
    'grok4-0709': { input: 0.001, output: 0.002 },
    'grok-vision': { input: 0.005, output: 0.01 }
  },
  gemini: {
    'gemini-2.5-pro': { input: 0.00025, output: 0.001 },
    'gemini-2.5-flash': { input: 0.00001, output: 0.00005 },
    'gemini-2.0-flash-exp': { input: 0.00001, output: 0.00005 }
  },
  claude: {
    'claude-sonnet-4-5': { input: 0.003, output: 0.015 }
  }
};
```

**Where to find actual pricing**:
- Grok: https://console.x.ai/pricing (or API docs)
- Gemini: https://ai.google.dev/pricing
- Claude: https://www.anthropic.com/pricing

## Troubleshooting

### Dashboard shows "No Data"

**Root Cause**: Metrics not instrumented or not flowing to Prometheus.

**Resolution**:
1. Verify metrics endpoint exists: `curl http://your-exporter:9090/metrics | grep mcp_ai_`
2. Check Prometheus target status: https://prometheus.jclee.me/targets
3. Validate metric exists: `./scripts/validate-metrics.sh --list`
4. Check recording rules loaded: https://prometheus.jclee.me/rules

### Prometheus target DOWN

**Root Cause**: Metrics exporter not running or wrong endpoint.

**Resolution**:
```bash
# Check exporter is running
curl http://your-exporter:9090/health

# Verify target in prometheus.yml matches actual endpoint
cat configs/prometheus.yml | grep -A5 'ai-agents'

# Reload Prometheus after config change
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
```

### Costs seem incorrect

**Root Cause**: Pricing table not updated with actual costs.

**Resolution**:
1. Get actual pricing from provider documentation
2. Update `PRICING` object in metrics exporter
3. Restart metrics exporter
4. Costs will be accurate for new requests (historical costs unchanged)

### Recording rules not working

**Root Cause**: Recording rules need source metrics to exist first.

**Resolution**:
```bash
# Verify source metrics exist
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  'http://localhost:9090/api/v1/query?query=mcp_ai_requests_total'" | \
  jq '.data.result | length'

# If 0, metrics not instrumented yet
# If >0, check recording rules loaded
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container wget -qO- \
  http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[] | select(.name=="ai_cost_recording_rules")'
```

## Validation Checklist

Before marking as complete:

- [ ] Metrics exporter deployed and running
- [ ] `/metrics` endpoint returns `mcp_ai_*` metrics
- [ ] Prometheus target `ai-agents` shows UP
- [ ] All 9 core metrics exist in Prometheus
- [ ] Recording rules loaded (9 rules in `ai_cost_recording_rules` group)
- [ ] Dashboard shows data (not "No Data")
- [ ] Cost calculations verified against actual pricing
- [ ] All 17 panels display correctly
- [ ] Golden Signals (top row) show realistic values

## Next Steps

1. **Immediate**: Implement metrics instrumentation (Phase 1)
2. **After instrumentation**: Enable Prometheus scraping (Phase 2)
3. **Before using**: Validate all metrics (Phase 3)
4. **Finally**: Access and verify dashboard (Phase 4)

## References

- **Metrics Specification**: `docs/AI-METRICS-SPECIFICATION.md` (detailed implementation guide)
- **Dashboard JSON**: `configs/provisioning/dashboards/ai-agent-costs-reds.json`
- **Recording Rules**: `configs/recording-rules.yml` (lines 106-145)
- **Prometheus Config**: `configs/prometheus.yml` (lines 85-104, commented out)
- **REDS Methodology**: https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/
- **Prometheus Best Practices**: https://prometheus.io/docs/practices/naming/

## Version History

| Date | Change |
|------|--------|
| 2025-10-16 | Initial creation - dashboard template, metrics spec, recording rules |

---

**Status**: 🟡 Ready for Instrumentation  
**Blocker**: Metrics exporter must be implemented and deployed  
**Estimated Effort**: 4-6 hours for instrumentation + testing
