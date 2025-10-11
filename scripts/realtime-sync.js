#!/usr/bin/env node
/**
 * Real-time directory sync to Synology NAS
 * Uses Node.js fs.watch (no dependencies needed)
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// Configuration
const CONFIG = {
  remoteHost: '192.168.50.215',
  remotePort: '1111',
  remoteUser: 'jclee',
  remotePath: '/volume1/grafana',
  localPath: '/home/jclee/app/grafana',
  watchDirs: ['.'],  // Sync entire directory
  excludeDirs: ['.git', 'node_modules', '.claude', '.serena', 'demo', 'resume', 'docs'],
  debounceMs: 1000, // Wait 1s after last change before syncing
};

// Colors
const colors = {
  blue: '\x1b[34m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  reset: '\x1b[0m',
};

const log = (msg) => {
  const time = new Date().toTimeString().split(' ')[0];
  console.log(`${colors.blue}[${time}]${colors.reset} ${msg}`);
};

const logSync = (msg) => {
  console.log(`${colors.green}[SYNC]${colors.reset} ${msg}`);
};

// Debounce map for each directory
const debouncers = {};

/**
 * Execute rsync command
 */
function rsync(dir) {
  return new Promise((resolve, reject) => {
    const localDir = dir === '.' ? CONFIG.localPath : path.join(CONFIG.localPath, dir);
    const remoteDir = dir === '.'
      ? `${CONFIG.remoteUser}@${CONFIG.remoteHost}:${CONFIG.remotePath}/`
      : `${CONFIG.remoteUser}@${CONFIG.remoteHost}:${CONFIG.remotePath}/${dir}/`;

    const args = [
      '-az',
      '--delete',
      '-e', `ssh -p ${CONFIG.remotePort}`,
    ];

    // Add exclude patterns
    CONFIG.excludeDirs.forEach(excludeDir => {
      args.push('--exclude', excludeDir);
    });

    args.push(`${localDir}/`);
    args.push(remoteDir);

    const proc = spawn('rsync', args);

    proc.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`rsync exited with code ${code}`));
      }
    });

    proc.on('error', reject);
  });
}

/**
 * Sync directory with debouncing
 */
function scheduleSync(dir) {
  // Clear existing timer
  if (debouncers[dir]) {
    clearTimeout(debouncers[dir]);
  }

  // Schedule new sync
  debouncers[dir] = setTimeout(async () => {
    logSync(`Syncing ${dir}/...`);
    try {
      await rsync(dir);
      console.log(`  ✓ ${dir}/ synced successfully`);
    } catch (err) {
      console.error(`  ✗ Failed to sync ${dir}/: ${err.message}`);
    }
    delete debouncers[dir];
  }, CONFIG.debounceMs);
}

/**
 * Initial sync all directories
 */
async function initialSync() {
  log('🚀 Starting initial sync...');

  for (const dir of CONFIG.watchDirs) {
    try {
      await rsync(dir);
      logSync(`Initial sync: ${dir}/`);
    } catch (err) {
      console.error(`  ✗ Failed initial sync of ${dir}/: ${err.message}`);
    }
  }

  log('✅ Initial sync complete');
}

/**
 * Watch directory recursively
 */
function watchDirectory(dir) {
  const fullPath = path.join(CONFIG.localPath, dir);

  try {
    const watcher = fs.watch(fullPath, { recursive: true }, (eventType, filename) => {
      if (filename) {
        // Ignore hidden files and temporary files
        if (filename.startsWith('.') || filename.endsWith('.swp') || filename.endsWith('~')) {
          return;
        }

        log(`Change detected in ${dir}/${filename}`);
        scheduleSync(dir);
      }
    });

    watcher.on('error', (err) => {
      console.error(`Watch error for ${dir}: ${err.message}`);
    });

    log(`👀 Watching ${dir}/`);
  } catch (err) {
    console.error(`Failed to watch ${dir}: ${err.message}`);
  }
}

/**
 * Main
 */
async function main() {
  console.log('');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  log('  Grafana Real-time Sync to Synology NAS');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  // Initial sync
  await initialSync();
  console.log('');

  // Start watching
  log(`Watching directories: ${CONFIG.watchDirs.join(', ')}`);
  log('Press Ctrl+C to stop');
  console.log('');

  CONFIG.watchDirs.forEach(watchDirectory);

  // Keep process alive
  process.on('SIGINT', () => {
    console.log('');
    log('👋 Stopping real-time sync...');
    process.exit(0);
  });
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
