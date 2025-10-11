# Real-time Directory Sync to Synology NAS

## Overview

Automatic real-time synchronization of Grafana configuration files to Synology NAS using Node.js `fs.watch`.

**Architecture:**
```
Local: /home/jclee/app/grafana/{configs,compose,scripts}
         │
         ▼ (fs.watch detects changes)
Node.js Daemon (realtime-sync.js)
         │
         ▼ (rsync via SSH)
Remote: 192.168.50.215:/volume1/grafana/{configs,compose,scripts}
```

**Features:**
- ✅ **Zero dependencies** - Uses built-in Node.js `fs.watch`
- ✅ **Recursive watching** - Monitors all subdirectories automatically
- ✅ **Debouncing** - Groups multiple changes within 1 second
- ✅ **Daemon mode** - Runs in background with PID management
- ✅ **Initial sync** - Full sync on startup
- ✅ **Delete propagation** - `--delete` flag removes files on remote

## Quick Start

### Start Real-time Sync

```bash
# Start daemon in background
./scripts/start-sync-daemon.sh

# Output:
# ✅ Sync daemon started successfully (PID: 123456)
# 📝 Logs: tail -f /tmp/grafana-sync.log
```

### Check Status

```bash
./scripts/status-sync-daemon.sh

# Output:
# Status: ✅ Running
# PID: 123456
# Uptime: 01:23:45
```

### Stop Daemon

```bash
./scripts/stop-sync-daemon.sh

# Output:
# ✅ Sync daemon stopped (PID: 123456)
```

## Manual Control

### Run in Foreground (for debugging)

```bash
node scripts/realtime-sync.js

# Output (live):
# [22:24:07] 🚀 Starting initial sync...
# [SYNC] Initial sync: configs/
# [SYNC] Initial sync: compose/
# [SYNC] Initial sync: scripts/
# [22:24:08] ✅ Initial sync complete
# [22:24:08] 👀 Watching configs/
# [22:24:08] 👀 Watching compose/
# [22:24:08] 👀 Watching scripts/
# [22:24:10] Change detected in configs/prometheus.yml
# [SYNC] Syncing configs/...
#   ✓ configs/ synced successfully
```

Press `Ctrl+C` to stop.

### Direct rsync (one-time sync)

```bash
# Sync all directories
rsync -azv --delete -e "ssh -p 1111" \
  /home/jclee/app/grafana/{configs,compose,scripts} \
  jclee@192.168.50.215:/volume1/grafana/

# Sync specific directory
rsync -azv --delete -e "ssh -p 1111" \
  /home/jclee/app/grafana/configs/ \
  jclee@192.168.50.215:/volume1/grafana/configs/
```

## Configuration

Edit `scripts/realtime-sync.js`:

```javascript
const CONFIG = {
  remoteHost: '192.168.50.215',
  remotePort: '1111',
  remoteUser: 'jclee',
  remotePath: '/volume1/grafana',
  localPath: '/home/jclee/app/grafana',
  watchDirs: ['configs', 'compose', 'scripts'],  // Add more directories here
  debounceMs: 1000,  // Wait 1s after last change before syncing
};
```

## Watched Directories

- `configs/` - All Grafana/Prometheus/Loki/Promtail configurations
- `compose/` - Docker Compose files
- `scripts/` - Management and automation scripts

## Excluded Files

The following files are automatically ignored:
- Hidden files (starting with `.`)
- Vim swap files (`.swp`, `~`)
- Temporary files (`.tmp`)

To exclude more files, edit `rsync` command in `realtime-sync.js`:

```javascript
const args = [
  '-az',
  '--delete',
  '--exclude', '.git',
  '--exclude', '*.tmp',
  '--exclude', 'node_modules',  // Add more excludes here
  '-e', `ssh -p ${CONFIG.remotePort}`,
  `${localDir}/`,
  remoteDir,
];
```

## Troubleshooting

### Daemon not starting

```bash
# Check if port 1111 is accessible
ssh -p 1111 jclee@192.168.50.215 "echo OK"

# Check Node.js version
node --version  # Should be v22.20.0+

# Check if rsync is installed
which rsync
```

### Sync not happening

```bash
# Check daemon status
./scripts/status-sync-daemon.sh

# View live logs
tail -f /tmp/grafana-sync.log

# Restart daemon
./scripts/stop-sync-daemon.sh
./scripts/start-sync-daemon.sh
```

### Manual verification

```bash
# Test manual sync
rsync -azv --delete --dry-run -e "ssh -p 1111" \
  /home/jclee/app/grafana/configs/ \
  jclee@192.168.50.215:/volume1/grafana/configs/

# Check remote files
ssh -p 1111 jclee@192.168.50.215 \
  "ls -la /volume1/grafana/configs/"
```

## System Integration

### Run on system startup (optional)

Create systemd service:

```bash
sudo tee /etc/systemd/system/grafana-sync.service > /dev/null <<'EOF'
[Unit]
Description=Grafana Real-time Sync to Synology NAS
After=network.target

[Service]
Type=simple
User=jclee
WorkingDirectory=/home/jclee/app/grafana
ExecStart=/usr/bin/node /home/jclee/app/grafana/scripts/realtime-sync.js
Restart=on-failure
RestartSec=10
StandardOutput=append:/tmp/grafana-sync.log
StandardError=append:/tmp/grafana-sync.log

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable grafana-sync.service
sudo systemctl start grafana-sync.service

# Check status
sudo systemctl status grafana-sync.service
```

## Performance

**Debouncing example:**
```
22:24:10.000 - configs/prometheus.yml modified
22:24:10.100 - configs/prometheus.yml modified (again)
22:24:10.500 - configs/loki-config.yaml modified
22:24:11.000 - Trigger sync (1 second after last change)
22:24:11.200 - rsync completes
```

Only 1 rsync operation runs, even though 3 file changes occurred.

**Network usage:**
- rsync only transfers changed blocks (delta transfer)
- Compression enabled (`-z` flag)
- Typical sync: < 1 KB for config file changes

## Comparison: Cron vs Real-time

| Method | Latency | CPU Usage | Network | Detection |
|--------|---------|-----------|---------|-----------|
| Cron (5 min) | 0-5 minutes | Low (periodic) | Full scan | None |
| Real-time | ~1 second | Low (event-driven) | Delta only | Instant |

Real-time sync is **significantly faster** with minimal overhead.
