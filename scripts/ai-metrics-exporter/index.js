const express = require('express');
const promClient = require('prom-client');

const app = express();
const register = new promClient.Registry();

// Enable default metrics
promClient.collectDefaultMetrics({ register });

// AI Request metrics
const aiRequests = new promClient.Counter({
  name: 'mcp_ai_requests_total',
  help: 'Total AI requests',
  labelNames: ['provider', 'model', 'operation', 'status'],
  registers: [register]
});

// Duration histogram
const aiDuration = new promClient.Histogram({
  name: 'mcp_ai_request_duration_seconds',
  help: 'AI request duration',
  labelNames: ['provider', 'model', 'operation'],
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
  registers: [register]
});

// Token counter
const aiTokens = new promClient.Counter({
  name: 'mcp_ai_tokens_total',
  help: 'Total tokens consumed',
  labelNames: ['provider', 'model', 'type'],
  registers: [register]
});

// Cost counter
const aiCost = new promClient.Counter({
  name: 'mcp_ai_cost_usd_total',
  help: 'Total cost in USD',
  labelNames: ['provider', 'model', 'operation'],
  registers: [register]
});

// Rate limit gauge
const aiRateLimit = new promClient.Gauge({
  name: 'mcp_ai_rate_limit_remaining',
  help: 'Remaining requests in rate limit window',
  labelNames: ['provider', 'model', 'limit_type'],
  registers: [register]
});

// Rate limit max gauge
const aiRateLimitMax = new promClient.Gauge({
  name: 'mcp_ai_rate_limit_max',
  help: 'Maximum rate limit',
  labelNames: ['provider', 'model', 'limit_type'],
  registers: [register]
});

// Rate limit hits counter
const aiRateLimitHits = new promClient.Counter({
  name: 'mcp_ai_rate_limit_hits_total',
  help: 'Number of rate limit hits',
  labelNames: ['provider', 'model'],
  registers: [register]
});

// Model selection counter
const aiModelSelection = new promClient.Counter({
  name: 'mcp_ai_model_selection_total',
  help: 'Model routing decisions',
  labelNames: ['provider', 'model', 'reason', 'task_type'],
  registers: [register]
});

// Pricing table (per 1K tokens)
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

function calculateCost(provider, model, inputTokens, outputTokens) {
  const pricing = PRICING[provider]?.[model];
  if (!pricing) return 0;
  
  return (inputTokens / 1000 * pricing.input) + (outputTokens / 1000 * pricing.output);
}

// Generate realistic mock data
function generateMockTraffic() {
  const providers = ['grok', 'gemini', 'claude'];
  const models = {
    grok: ['grok-code-fast-1', 'grok4-0709', 'grok-vision'],
    gemini: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash-exp'],
    claude: ['claude-sonnet-4-5']
  };
  const operations = ['chat', 'vision', 'function_call', 'embedding'];
  const statuses = ['success', 'error', 'timeout', 'rate_limited'];
  const reasons = ['fast', 'complex', 'vision', 'fallback'];
  const taskTypes = ['code', 'analysis', 'documentation', 'testing'];
  
  // Generate requests (weighted towards success)
  const provider = providers[Math.floor(Math.random() * providers.length)];
  const model = models[provider][Math.floor(Math.random() * models[provider].length)];
  const operation = operations[Math.floor(Math.random() * operations.length)];
  const status = Math.random() > 0.05 ? 'success' : statuses[Math.floor(Math.random() * statuses.length)];
  
  // Record request
  aiRequests.inc({ provider, model, operation, status });
  
  if (status === 'success') {
    // Record duration (0.5-5 seconds, weighted towards lower)
    const duration = Math.random() * 4.5 + 0.5;
    aiDuration.observe({ provider, model, operation }, duration);
    
    // Record tokens (100-5000 input, 50-2000 output)
    const inputTokens = Math.floor(Math.random() * 4900) + 100;
    const outputTokens = Math.floor(Math.random() * 1950) + 50;
    
    aiTokens.inc({ provider, model, type: 'input' }, inputTokens);
    aiTokens.inc({ provider, model, type: 'output' }, outputTokens);
    
    // Record cost
    const cost = calculateCost(provider, model, inputTokens, outputTokens);
    aiCost.inc({ provider, model, operation }, cost);
    
    // Model selection
    const reason = reasons[Math.floor(Math.random() * reasons.length)];
    const taskType = taskTypes[Math.floor(Math.random() * taskTypes.length)];
    aiModelSelection.inc({ provider, model, reason, task_type: taskType });
  }
  
  // Update rate limits (simulate)
  const limitTypes = ['requests_per_minute', 'tokens_per_minute', 'requests_per_day'];
  limitTypes.forEach(limitType => {
    const max = limitType === 'requests_per_day' ? 10000 : 
                limitType === 'tokens_per_minute' ? 100000 : 100;
    const remaining = Math.floor(Math.random() * max * 0.8) + max * 0.1;
    
    aiRateLimit.set({ provider, model, limit_type: limitType }, remaining);
    aiRateLimitMax.set({ provider, model, limit_type: limitType }, max);
  });
  
  // Occasional rate limit hit
  if (Math.random() > 0.99) {
    aiRateLimitHits.inc({ provider, model });
  }
}

// Generate traffic at varying rates
setInterval(() => {
  // Burst traffic (5-15 requests)
  const burstSize = Math.floor(Math.random() * 10) + 5;
  for (let i = 0; i < burstSize; i++) {
    generateMockTraffic();
  }
}, 1000); // Every second

// Health endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', uptime: process.uptime() });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Status page
app.get('/', (req, res) => {
  res.send(`
    <html>
    <head><title>AI Metrics Exporter</title></head>
    <body style="font-family: monospace; padding: 20px;">
      <h1>AI Metrics Exporter</h1>
      <p>Mock AI agent metrics for Grafana dashboard testing</p>
      <h2>Endpoints:</h2>
      <ul>
        <li><a href="/metrics">/metrics</a> - Prometheus metrics</li>
        <li><a href="/health">/health</a> - Health check</li>
      </ul>
      <h2>Providers:</h2>
      <ul>
        <li>Grok (grok-code-fast-1, grok4-0709, grok-vision)</li>
        <li>Gemini (gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash-exp)</li>
        <li>Claude (claude-sonnet-4-5)</li>
      </ul>
      <p>Status: <span style="color: green;">Running</span></p>
      <p>Uptime: ${Math.floor(process.uptime())}s</p>
    </body>
    </html>
  `);
});

const PORT = process.env.PORT || 9091;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`AI Metrics Exporter listening on port ${PORT}`);
  console.log(`Metrics: http://localhost:${PORT}/metrics`);
  console.log(`Health: http://localhost:${PORT}/health`);
});
