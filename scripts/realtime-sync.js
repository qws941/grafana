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
  watchDirs: ['configs', 'docs', 'demo', 'resume', 'scripts'],  // Sync specific directories
  excludeDirs: ['.git', 'node_modules', '.claude', '.serena'],
  debounceMs: 1000, // Wait 1s after last change before syncing
  syncRootFiles: true, // Also sync root files like docker-compose.yml, .env
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
      '-azv',  // Added verbose
      '--delete',
      '-e', `/usr/bin/ssh -p ${CONFIG.remotePort} -i /home/jclee/.ssh/id_ed25519 -o StrictHostKeyChecking=no`,  // Use full path and explicit key for systemd
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
    try {
      if (dir === 'root') {
        logSync('Syncing root files...');
        await rsyncRootFiles();
        console.log('  ✓ Root files synced successfully');
      } else {
        logSync(`Syncing ${dir}/...`);
        await rsync(dir);
        console.log(`  ✓ ${dir}/ synced successfully`);
      }
    } catch (err) {
      console.error(`  ✗ Failed to sync ${dir}: ${err.message}`);
      if (err.stderr) console.error(`     stderr: ${err.stderr.trim()}`);
    }
    delete debouncers[dir];
  }, CONFIG.debounceMs);
}

/**
 * Sync root files (docker-compose.yml, .env, etc.)
 */
function rsyncRootFiles() {
  return new Promise((resolve, reject) => {
    const args = [
      '-azv',  // Added verbose
      '--delete',
      '-e', `/usr/bin/ssh -p ${CONFIG.remotePort} -i /home/jclee/.ssh/id_ed25519 -o StrictHostKeyChecking=no`,  // Use full path and explicit key for systemd
      '--include', 'docker-compose.yml',
      '--include', '.env',
      '--include', '.gitignore',
      '--include', 'CLAUDE.md',
      '--include', 'README.md',
      '--exclude', '*',
      `${CONFIG.localPath}/`,
      `${CONFIG.remoteUser}@${CONFIG.remoteHost}:${CONFIG.remotePath}/`,
    ];

    let stdout = '';
    let stderr = '';

    const proc = spawn('rsync', args);

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        const error = new Error(`rsync exited with code ${code}`);
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      }
    });

    proc.on('error', reject);
  });
}

/**
 * Initial sync all directories
 */
async function initialSync() {
  log('🚀 Starting initial sync...');

  // Sync root files first
  if (CONFIG.syncRootFiles) {
    try {
      await rsyncRootFiles();
      logSync('Initial sync: root files');
    } catch (err) {
      console.error(`  ✗ Failed initial sync of root files: ${err.message}`);
      if (err.stderr) console.error(`     stderr: ${err.stderr.trim()}`);
    }
  }

  // Sync each directory
  for (const dir of CONFIG.watchDirs) {
    try {
      await rsync(dir);
      logSync(`Initial sync: ${dir}/`);
    } catch (err) {
      console.error(`  ✗ Failed initial sync of ${dir}/: ${err.message}`);
      if (err.stderr) console.error(`     stderr: ${err.stderr.trim()}`);
    }
  }

  log('✅ Initial sync complete');
}

/**
 * Watch root files
 */
function watchRootFiles() {
  const rootFiles = ['docker-compose.yml', '.env', '.gitignore', 'CLAUDE.md', 'README.md'];

  rootFiles.forEach(file => {
    const fullPath = path.join(CONFIG.localPath, file);

    try {
      fs.watch(fullPath, (eventType) => {
        log(`Change detected in ${file}`);
        scheduleSync('root');
      });
    } catch (err) {
      // File might not exist yet, ignore
    }
  });

  log('👀 Watching root files');
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
        if (filename.startsWith('.') || filename.endsWith('.swp') || filename.endsWith('~') || filename.endsWith('.tmp')) {
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

  if (CONFIG.syncRootFiles) {
    watchRootFiles();
  }
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
