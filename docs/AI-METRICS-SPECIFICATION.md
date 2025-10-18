# AI Agent Metrics Specification

**Version**: 1.0  
**Date**: 2025-10-16  
**Status**: Design Document

## Overview

This specification defines Prometheus metrics for tracking AI agent costs across multiple providers (Grok, Gemini, Claude). These metrics enable comprehensive monitoring of usage, performance, and costs through Grafana dashboards.

## Metric Naming Convention

All AI metrics follow the pattern: `mcp_ai_<metric>_<unit>_<suffix>`

- Prefix: `mcp_ai_` (MCP AI namespace)
- Metric: Descriptive name (requests, tokens, cost)
- Unit: Standard Prometheus units (seconds, bytes, total)
- Suffix: Prometheus type indicator (total for counters)

## Core Metrics

### 1. Request Metrics

#### `mcp_ai_requests_total`
**Type**: Counter  
**Description**: Total number of AI requests by provider, model, and status  
**Labels**:
- `provider`: AI provider (grok, gemini, claude)
- `model`: Specific model name
- `operation`: Type of operation (chat, vision, function_call, embedding)
- `status`: Request outcome (success, error, timeout, rate_limited)

**Example**:
```promql
# Request rate per minute
rate(mcp_ai_requests_total[5m]) * 60

# Success rate percentage
rate(mcp_ai_requests_total{status="success"}[5m]) 
  / rate(mcp_ai_requests_total[5m]) * 100

# Error count by provider
sum by (provider) (mcp_ai_requests_total{status="error"})
```

#### `mcp_ai_request_duration_seconds`
**Type**: Histogram  
**Description**: Request latency distribution  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `operation`: Operation type

**Buckets**: [0.1, 0.5, 1, 2, 5, 10, 30, 60]

**Example**:
```promql
# P99 latency
histogram_quantile(0.99, 
  rate(mcp_ai_request_duration_seconds_bucket[5m]))

# Average duration
rate(mcp_ai_request_duration_seconds_sum[5m]) 
  / rate(mcp_ai_request_duration_seconds_count[5m])
```

### 2. Token Metrics

#### `mcp_ai_tokens_total`
**Type**: Counter  
**Description**: Total tokens consumed (input + output)  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `type`: Token type (input, output, cached)

**Example**:
```promql
# Tokens per minute
rate(mcp_ai_tokens_total[5m]) * 60

# Input vs output ratio
rate(mcp_ai_tokens_total{type="output"}[5m]) 
  / rate(mcp_ai_tokens_total{type="input"}[5m])

# Total tokens by provider
sum by (provider) (mcp_ai_tokens_total)
```

#### `mcp_ai_tokens_per_request`
**Type**: Histogram  
**Description**: Token distribution per request  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `type`: Token type

**Buckets**: [100, 500, 1000, 5000, 10000, 50000, 100000]

### 3. Cost Metrics

#### `mcp_ai_cost_usd_total`
**Type**: Counter  
**Description**: Cumulative cost in USD  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `operation`: Operation type

**Example**:
```promql
# Cost per hour
rate(mcp_ai_cost_usd_total[1h]) * 3600

# Daily cost projection
rate(mcp_ai_cost_usd_total[1h]) * 3600 * 24

# Cost breakdown by provider
sum by (provider) (mcp_ai_cost_usd_total)
```

#### `mcp_ai_cost_per_1k_tokens_usd`
**Type**: Gauge  
**Description**: Current pricing per 1K tokens  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `type`: Token type (input, output)

### 4. Rate Limit Metrics

#### `mcp_ai_rate_limit_remaining`
**Type**: Gauge  
**Description**: Remaining requests in current rate limit window  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name
- `limit_type`: Type of limit (requests_per_minute, tokens_per_minute, requests_per_day)

**Example**:
```promql
# Rate limit utilization percentage
(1 - mcp_ai_rate_limit_remaining 
  / mcp_ai_rate_limit_max) * 100
```

#### `mcp_ai_rate_limit_hits_total`
**Type**: Counter  
**Description**: Number of rate limit hits  
**Labels**:
- `provider`: AI provider
- `model`: Specific model name

### 5. Model Selection Metrics

#### `mcp_ai_model_selection_total`
**Type**: Counter  
**Description**: Model routing decisions  
**Labels**:
- `provider`: Selected provider
- `model`: Selected model
- `reason`: Selection reason (fast, complex, vision, fallback)
- `task_type`: Task classification

**Example**:
```promql
# Model usage distribution
sum by (model) (mcp_ai_model_selection_total)

# Fallback rate
rate(mcp_ai_model_selection_total{reason="fallback"}[5m]) 
  / rate(mcp_ai_model_selection_total[5m]) * 100
```

## Recording Rules

Add to `configs/recording-rules.yml`:

```yaml
- name: ai_cost_recording_rules
  interval: 30s
  rules:
    # Request rates
    - record: ai:requests:rate5m
      expr: rate(mcp_ai_requests_total[5m]) * 60

    - record: ai:requests:success_rate
      expr: |
        rate(mcp_ai_requests_total{status="success"}[5m]) 
        / rate(mcp_ai_requests_total[5m]) * 100

    # Token consumption
    - record: ai:tokens:rate5m
      expr: rate(mcp_ai_tokens_total[5m]) * 60

    - record: ai:tokens:per_request_avg
      expr: |
        rate(mcp_ai_tokens_total[5m]) 
        / rate(mcp_ai_requests_total[5m])

    # Cost metrics
    - record: ai:cost:hourly_usd
      expr: rate(mcp_ai_cost_usd_total[1h]) * 3600

    - record: ai:cost:daily_projection_usd
      expr: rate(mcp_ai_cost_usd_total[1h]) * 3600 * 24

    # Latency percentiles
    - record: ai:duration:p50
      expr: |
        histogram_quantile(0.50, 
          rate(mcp_ai_request_duration_seconds_bucket[5m]))

    - record: ai:duration:p95
      expr: |
        histogram_quantile(0.95, 
          rate(mcp_ai_request_duration_seconds_bucket[5m]))

    - record: ai:duration:p99
      expr: |
        histogram_quantile(0.99, 
          rate(mcp_ai_request_duration_seconds_bucket[5m]))
```

## Provider-Specific Models

### Grok Models
- `grok-code-fast-1`: Fast code generation
- `grok4-0709`: Deep analysis (8+ files)
- `grok-vision`: Image analysis

**Pricing** (example, update with actual):
- grok-code-fast-1: $0.0001/1K input, $0.0002/1K output
- grok4-0709: $0.001/1K input, $0.002/1K output
- grok-vision: $0.005/1K input, $0.01/1K output

### Gemini Models
- `gemini-2.5-pro`: Complex tasks, architecture
- `gemini-2.5-flash`: General purpose, fallback
- `gemini-2.0-flash-exp`: Quick operations

**Pricing** (example, update with actual):
- gemini-2.5-pro: $0.00025/1K input, $0.001/1K output
- gemini-2.5-flash: $0.00001/1K input, $0.00005/1K output

### Claude Models
- `claude-sonnet-4-5`: Current model (from CLAUDE.md context)

**Pricing** (example, update with actual):
- claude-sonnet-4-5: $0.003/1K input, $0.015/1K output

## Instrumentation Guide

### Node.js/TypeScript Implementation

```typescript
import { Counter, Histogram, Gauge, Registry } from 'prom-client';

// Create metrics registry
const register = new Registry();

// Request counter
const aiRequests = new Counter({
  name: 'mcp_ai_requests_total',
  help: 'Total AI requests',
  labelNames: ['provider', 'model', 'operation', 'status'],
  registers: [register]
});

// Duration histogram
const aiDuration = new Histogram({
  name: 'mcp_ai_request_duration_seconds',
  help: 'AI request duration',
  labelNames: ['provider', 'model', 'operation'],
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
  registers: [register]
});

// Token counter
const aiTokens = new Counter({
  name: 'mcp_ai_tokens_total',
  help: 'Total tokens consumed',
  labelNames: ['provider', 'model', 'type'],
  registers: [register]
});

// Cost counter
const aiCost = new Counter({
  name: 'mcp_ai_cost_usd_total',
  help: 'Total cost in USD',
  labelNames: ['provider', 'model', 'operation'],
  registers: [register]
});

// Example usage
async function callAI(provider: string, model: string, operation: string, input: string) {
  const startTime = Date.now();
  
  try {
    const result = await aiProvider.call({provider, model, input});
    
    // Record success
    aiRequests.inc({provider, model, operation, status: 'success'});
    
    // Record duration
    const duration = (Date.now() - startTime) / 1000;
    aiDuration.observe({provider, model, operation}, duration);
    
    // Record tokens
    aiTokens.inc({provider, model, type: 'input'}, result.inputTokens);
    aiTokens.inc({provider, model, type: 'output'}, result.outputTokens);
    
    // Calculate and record cost
    const cost = calculateCost(provider, model, result.inputTokens, result.outputTokens);
    aiCost.inc({provider, model, operation}, cost);
    
    return result;
  } catch (error) {
    // Record error
    aiRequests.inc({provider, model, operation, status: 'error'});
    throw error;
  }
}

// Pricing table
const PRICING = {
  grok: {
    'grok-code-fast-1': { input: 0.0001, output: 0.0002 },
    'grok4-0709': { input: 0.001, output: 0.002 },
    'grok-vision': { input: 0.005, output: 0.01 }
  },
  gemini: {
    'gemini-2.5-pro': { input: 0.00025, output: 0.001 },
    'gemini-2.5-flash': { input: 0.00001, output: 0.00005 }
  },
  claude: {
    'claude-sonnet-4-5': { input: 0.003, output: 0.015 }
  }
};

function calculateCost(provider: string, model: string, inputTokens: number, outputTokens: number): number {
  const pricing = PRICING[provider]?.[model];
  if (!pricing) return 0;
  
  return (inputTokens / 1000 * pricing.input) + (outputTokens / 1000 * pricing.output);
}

// Expose metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

### Python Implementation

```python
from prometheus_client import Counter, Histogram, Gauge, CollectorRegistry
import time

# Create registry
registry = CollectorRegistry()

# Define metrics
ai_requests = Counter(
    'mcp_ai_requests_total',
    'Total AI requests',
    ['provider', 'model', 'operation', 'status'],
    registry=registry
)

ai_duration = Histogram(
    'mcp_ai_request_duration_seconds',
    'AI request duration',
    ['provider', 'model', 'operation'],
    buckets=[0.1, 0.5, 1, 2, 5, 10, 30, 60],
    registry=registry
)

ai_tokens = Counter(
    'mcp_ai_tokens_total',
    'Total tokens consumed',
    ['provider', 'model', 'type'],
    registry=registry
)

ai_cost = Counter(
    'mcp_ai_cost_usd_total',
    'Total cost in USD',
    ['provider', 'model', 'operation'],
    registry=registry
)

# Example usage
def call_ai(provider: str, model: str, operation: str, input_text: str):
    start_time = time.time()
    
    try:
        result = ai_provider.call(provider=provider, model=model, input=input_text)
        
        # Record metrics
        ai_requests.labels(provider, model, operation, 'success').inc()
        ai_duration.labels(provider, model, operation).observe(time.time() - start_time)
        ai_tokens.labels(provider, model, 'input').inc(result['input_tokens'])
        ai_tokens.labels(provider, model, 'output').inc(result['output_tokens'])
        
        cost = calculate_cost(provider, model, result['input_tokens'], result['output_tokens'])
        ai_cost.labels(provider, model, operation).inc(cost)
        
        return result
    except Exception as e:
        ai_requests.labels(provider, model, operation, 'error').inc()
        raise
```

## Prometheus Scrape Configuration

Add to `configs/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'ai-agents'
    static_configs:
      - targets: ['mcp-server:9090']  # Update with actual MCP server endpoint
    metrics_path: '/metrics'
    scrape_interval: 15s
    scrape_timeout: 10s
```

## Validation Checklist

Before using metrics in dashboards:

- [ ] Verify metric exists in Prometheus: `/api/v1/label/__name__/values`
- [ ] Test query returns data: `/api/v1/query?query=metric_name`
- [ ] Validate all label combinations exist
- [ ] Check histogram buckets are appropriate
- [ ] Verify cost calculations are accurate
- [ ] Confirm pricing table is up-to-date

## References

- [Prometheus Naming Best Practices](https://prometheus.io/docs/practices/naming/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- CLAUDE.md: Metrics validation requirements (2025-10-13 incident)
