#!/usr/bin/env node

/**
 * AI Usage Log Parser & Metrics Exporter
 * Parses Claude Code logs to extract real AI usage metrics
 */

const fs = require('fs');
const express = require('express');
const promClient = require('prom-client');

const app = express();
const register = new promClient.Registry();

// Metrics
const aiRequests = new promClient.Counter({
  name: 'mcp_ai_requests_total',
  help: 'Total AI requests',
  labelNames: ['provider', 'model', 'operation', 'status'],
  registers: [register]
});

const aiTokens = new promClient.Counter({
  name: 'mcp_ai_tokens_total',
  help: 'Total tokens consumed',
  labelNames: ['provider', 'model', 'type'],
  registers: [register]
});

const aiCost = new promClient.Counter({
  name: 'mcp_ai_cost_usd_total',
  help: 'Total cost in USD',
  labelNames: ['provider', 'model', 'operation'],
  registers: [register]
});

const aiDuration = new promClient.Histogram({
  name: 'mcp_ai_request_duration_seconds',
  help: 'AI request duration',
  labelNames: ['provider', 'model', 'operation'],
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
  registers: [register]
});

// Pricing (per 1K tokens)
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

// Parse environment variables for API usage tracking
function trackFromEnv() {
  // Check if Claude Code sets usage info in env
  const usage = {
    inputTokens: parseInt(process.env.CLAUDE_INPUT_TOKENS || 0),
    outputTokens: parseInt(process.env.CLAUDE_OUTPUT_TOKENS || 0),
    model: process.env.CLAUDE_MODEL || 'claude-sonnet-4-5',
    provider: 'claude'
  };
  
  if (usage.inputTokens > 0 || usage.outputTokens > 0) {
    aiRequests.inc({ 
      provider: usage.provider, 
      model: usage.model, 
      operation: 'chat', 
      status: 'success' 
    });
    
    aiTokens.inc({ provider: usage.provider, model: usage.model, type: 'input' }, usage.inputTokens);
    aiTokens.inc({ provider: usage.provider, model: usage.model, type: 'output' }, usage.outputTokens);
    
    const cost = calculateCost(usage.provider, usage.model, usage.inputTokens, usage.outputTokens);
    aiCost.inc({ provider: usage.provider, model: usage.model, operation: 'chat' }, cost);
  }
}

// Watch for real-time usage updates
let lastPosition = 0;

function watchUsageFile() {
  const usageFile = process.env.AI_USAGE_LOG || '/tmp/ai-usage.log';
  
  if (!fs.existsSync(usageFile)) {
    console.log(`Usage log not found: ${usageFile}`);
    console.log('Creating stub file for manual updates...');
    fs.writeFileSync(usageFile, '# AI Usage Log\n# Format: timestamp,provider,model,operation,status,input_tokens,output_tokens,duration_ms\n');
  }
  
  fs.watchFile(usageFile, { interval: 1000 }, (curr, prev) => {
    if (curr.mtime > prev.mtime) {
      const content = fs.readFileSync(usageFile, 'utf8');
      const lines = content.split('\n').slice(lastPosition);
      
      lines.forEach(line => {
        if (line.startsWith('#') || !line.trim()) return;
        
        const [timestamp, provider, model, operation, status, inputTokens, outputTokens, durationMs] = line.split(',');
        
        if (!provider || !model) return;
        
        // Record metrics
        aiRequests.inc({ provider, model, operation: operation || 'chat', status: status || 'success' });
        
        const input = parseInt(inputTokens) || 0;
        const output = parseInt(outputTokens) || 0;
        aiTokens.inc({ provider, model, type: 'input' }, input);
        aiTokens.inc({ provider, model, type: 'output' }, output);
        
        const cost = calculateCost(provider, model, input, output);
        aiCost.inc({ provider, model, operation: operation || 'chat' }, cost);
        
        if (durationMs) {
          aiDuration.observe({ provider, model, operation: operation || 'chat' }, parseFloat(durationMs) / 1000);
        }
      });
      
      lastPosition += lines.length;
    }
  });
}

// HTTP endpoint for manual updates
app.use(express.json());

app.post('/usage', (req, res) => {
  const { provider, model, operation, status, inputTokens, outputTokens, durationMs } = req.body;
  
  if (!provider || !model) {
    return res.status(400).json({ error: 'provider and model required' });
  }
  
  // Record metrics
  aiRequests.inc({ 
    provider, 
    model, 
    operation: operation || 'chat', 
    status: status || 'success' 
  });
  
  const input = parseInt(inputTokens) || 0;
  const output = parseInt(outputTokens) || 0;
  
  if (input > 0) aiTokens.inc({ provider, model, type: 'input' }, input);
  if (output > 0) aiTokens.inc({ provider, model, type: 'output' }, output);
  
  const cost = calculateCost(provider, model, input, output);
  if (cost > 0) aiCost.inc({ provider, model, operation: operation || 'chat' }, cost);
  
  if (durationMs) {
    aiDuration.observe({ provider, model, operation: operation || 'chat' }, parseFloat(durationMs) / 1000);
  }
  
  res.json({ success: true, cost });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Health endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    uptime: process.uptime(),
    mode: 'real-usage',
    usageLog: process.env.AI_USAGE_LOG || '/tmp/ai-usage.log'
  });
});

// Status page
app.get('/', (req, res) => {
  res.send(`
    <html>
    <head><title>AI Metrics - Real Usage</title></head>
    <body style="font-family: monospace; padding: 20px;">
      <h1>AI Metrics Exporter (Real Usage)</h1>
      <p>Tracking real AI API usage</p>
      
      <h2>Endpoints:</h2>
      <ul>
        <li><a href="/metrics">/metrics</a> - Prometheus metrics</li>
        <li><a href="/health">/health</a> - Health check</li>
        <li>POST /usage - Manual usage update</li>
      </ul>
      
      <h2>Usage Log:</h2>
      <p>${process.env.AI_USAGE_LOG || '/tmp/ai-usage.log'}</p>
      
      <h2>Manual Update Example:</h2>
      <pre>
curl -X POST http://localhost:9091/usage -H "Content-Type: application/json" -d '{
  "provider": "grok",
  "model": "grok-code-fast-1",
  "operation": "chat",
  "status": "success",
  "inputTokens": 1500,
  "outputTokens": 800,
  "durationMs": 2300
}'
      </pre>
      
      <h2>Log File Format:</h2>
      <pre>
# timestamp,provider,model,operation,status,input_tokens,output_tokens,duration_ms
2025-10-16T12:30:00,grok,grok-code-fast-1,chat,success,1500,800,2300
2025-10-16T12:31:00,gemini,gemini-2.5-pro,chat,success,2000,1200,3500
      </pre>
      
      <p>Status: <span style="color: green;">Running</span></p>
      <p>Uptime: ${Math.floor(process.uptime())}s</p>
    </body>
    </html>
  `);
});

const PORT = process.env.PORT || 9091;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 AI Metrics Exporter (Real Usage) listening on port ${PORT}`);
  console.log(`📊 Metrics: http://localhost:${PORT}/metrics`);
  console.log(`🏥 Health: http://localhost:${PORT}/health`);
  console.log(`📝 Usage log: ${process.env.AI_USAGE_LOG || '/tmp/ai-usage.log'}\n`);
  
  // Start watching usage file
  watchUsageFile();
  
  // Track env variables
  trackFromEnv();
});
