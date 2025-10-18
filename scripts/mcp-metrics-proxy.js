#!/usr/bin/env node
/**
 * MCP Metrics Proxy
 *
 * Intercepts MCP JSON-RPC calls to AI providers (Gemini, Grok)
 * and records usage metrics to Prometheus exporter.
 *
 * Architecture:
 *   Claude Code → This Proxy (stdio) → Original MCP Server (stdio)
 *                      ↓
 *               HTTP POST to metrics exporter
 */

const { spawn } = require('child_process');
const readline = require('readline');
const http = require('http');

// Configuration
const config = {
  provider: process.env.MCP_PROVIDER || 'unknown', // 'gemini' or 'grok'
  metricsUrl: process.env.METRICS_URL || 'http://localhost:9091/usage',
  targetCommand: process.env.MCP_TARGET_COMMAND,
  targetArgs: process.env.MCP_TARGET_ARGS ? process.env.MCP_TARGET_ARGS.split(',') : [],
  debug: process.env.MCP_DEBUG === 'true'
};

// Validate configuration
if (!config.targetCommand) {
  console.error('Error: MCP_TARGET_COMMAND not set');
  process.exit(1);
}

// Log to stderr (stdout is reserved for JSON-RPC)
const log = (...args) => {
  if (config.debug) {
    console.error(`[MCP-PROXY:${config.provider}]`, ...args);
  }
};

// Start target MCP server
log(`Starting target: ${config.targetCommand} ${config.targetArgs.join(' ')}`);
const targetProcess = spawn(config.targetCommand, config.targetArgs, {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: { ...process.env }
});

// Handle target process errors
targetProcess.on('error', (err) => {
  console.error(`Failed to start target MCP server: ${err.message}`);
  process.exit(1);
});

targetProcess.on('exit', (code) => {
  log(`Target process exited with code ${code}`);
  process.exit(code);
});

// Track in-flight requests
const pendingRequests = new Map();

/**
 * Send metrics to Prometheus exporter
 */
async function recordMetrics(data) {
  return new Promise((resolve) => {
    const postData = JSON.stringify(data);

    const options = {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const url = new URL(config.metricsUrl);
    options.hostname = url.hostname;
    options.port = url.port;
    options.path = url.pathname;

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          log('Metrics recorded:', data);
        } else {
          log('Failed to record metrics:', res.statusCode, body);
        }
        resolve();
      });
    });

    req.on('error', (err) => {
      log('Metrics recording error:', err.message);
      resolve(); // Don't fail proxy if metrics fail
    });

    req.write(postData);
    req.end();
  });
}

/**
 * Extract token usage from MCP response
 */
function extractTokenUsage(method, params, result) {
  // Different MCP servers return token info differently
  let inputTokens = 0;
  let outputTokens = 0;
  let model = 'unknown';

  // Gemini MCP format
  if (result?.usage) {
    inputTokens = result.usage.promptTokens || result.usage.inputTokens || 0;
    outputTokens = result.usage.completionTokens || result.usage.outputTokens || 0;
  }

  // Grok MCP format
  if (result?.usage_metadata) {
    inputTokens = result.usage_metadata.prompt_tokens || 0;
    outputTokens = result.usage_metadata.completion_tokens || 0;
  }

  // Try to extract model from params or result
  model = params?.model || params?.arguments?.model || result?.model || 'default';

  return { inputTokens, outputTokens, model };
}

/**
 * Process JSON-RPC request (Claude Code → Target MCP)
 */
function processRequest(line) {
  try {
    const request = JSON.parse(line);

    // Track request for later matching with response
    if (request.id) {
      pendingRequests.set(request.id, {
        method: request.method,
        params: request.params,
        timestamp: Date.now()
      });
    }

    log('Request:', request.method, request.id);
  } catch (err) {
    log('Failed to parse request:', err.message);
  }

  // Forward to target
  targetProcess.stdin.write(line + '\n');
}

/**
 * Process JSON-RPC response (Target MCP → Claude Code)
 */
async function processResponse(line) {
  try {
    const response = JSON.parse(line);

    // Match with original request
    if (response.id && pendingRequests.has(response.id)) {
      const request = pendingRequests.get(response.id);
      const duration = Date.now() - request.timestamp;

      // Extract token usage
      const { inputTokens, outputTokens, model } = extractTokenUsage(
        request.method,
        request.params,
        response.result
      );

      // Record metrics if we have token data
      if (inputTokens > 0 || outputTokens > 0) {
        await recordMetrics({
          provider: config.provider,
          model: model,
          operation: request.method,
          status: response.error ? 'error' : 'success',
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          durationMs: duration
        });
      }

      pendingRequests.delete(response.id);
      log('Response:', request.method, response.id, `${inputTokens}in/${outputTokens}out`, `${duration}ms`);
    }
  } catch (err) {
    log('Failed to parse response:', err.message);
  }

  // Forward to Claude Code
  process.stdout.write(line + '\n');
}

// Setup stdin/stdout pipes
const stdinReader = readline.createInterface({
  input: process.stdin,
  terminal: false
});

const stdoutReader = readline.createInterface({
  input: targetProcess.stdout,
  terminal: false
});

// Process lines
stdinReader.on('line', processRequest);
stdoutReader.on('line', processResponse);

// Cleanup on exit
process.on('SIGINT', () => {
  log('Shutting down...');
  targetProcess.kill('SIGINT');
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...');
  targetProcess.kill('SIGTERM');
  process.exit(0);
});

log('MCP Metrics Proxy started');
