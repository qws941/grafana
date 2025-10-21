# Deprecated Sync Scripts

**Deprecation Date**: 2025-10-18
**Reason**: Replaced by NFS mount architecture
**Status**: Archived for historical reference

---

## Background

These scripts were used for real-time synchronization between local development machine (192.168.50.100) and Synology NAS (192.168.50.215) before the implementation of NFS mount.

### Original Sync Architecture

```
Local Machine                    Synology NAS
/home/jclee/app/grafana/  --->  /volume1/grafana/
                          <---
        grafana-sync.service
        (systemd daemon watching for changes)
```

**Problems with sync service**:
- 1-2 second delay for file changes
- Additional daemon to manage
- Complexity in bidirectional sync
- Occasional sync conflicts

### Current NFS Architecture

```
Local Machine                    Synology NAS
/home/jclee/app/grafana/  ═══>  /volume1/grafana/
(NFS mount point)                (NFS share)

Mount: 192.168.50.215:/volume1/grafana
Type: NFS v3 (rw,noatime,hard)
Sync: INSTANT (filesystem-level)
```

**Benefits of NFS**:
- ✅ **Instant sync** - No delay, filesystem handles it
- ✅ **No daemon needed** - No additional service to manage
- ✅ **Bidirectional by default** - Built into filesystem
- ✅ **No sync conflicts** - Single source of truth
- ✅ **Simpler** - Standard Linux filesystem operation

---

## Deprecated Scripts

### Sync Scripts (7 files)

| Script | Purpose | Last Used |
|--------|---------|-----------|
| `realtime-sync.sh` | Manual sync trigger | 2025-10-11 |
| `start-sync-daemon.sh` | Start sync daemon | 2025-10-11 |
| `start-sync-service.sh` | Start systemd service | 2025-10-11 |
| `status-sync-daemon.sh` | Check daemon status | 2025-10-11 |
| `stop-sync-daemon.sh` | Stop sync daemon | 2025-10-11 |
| `sync-from-synology.sh` | Pull from NAS | 2025-10-11 |
| `sync-to-synology.sh` | Push to NAS | 2025-10-11 |

### Systemd Service

- **grafana-sync.service**: Systemd daemon for automatic sync
- **Status**: Disabled and stopped (2025-10-18)
- **Location**: `/etc/systemd/system/grafana-sync.service`

---

## Migration Guide

If you need to set up the current NFS architecture:

### 1. Stop and Disable Sync Service

```bash
sudo systemctl stop grafana-sync.service
sudo systemctl disable grafana-sync.service
```

### 2. Add NFS Mount to /etc/fstab

```bash
# Add this line:
192.168.50.215:/volume1/grafana /home/jclee/app/grafana nfs rw,noatime,hard 0 0
```

### 3. Mount NFS Share

```bash
sudo mount -a
```

### 4. Verify Mount

```bash
mount | grep grafana
# Should show: 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs
```

### 5. Test Write Access

```bash
touch /home/jclee/app/grafana/test.txt
rm /home/jclee/app/grafana/test.txt
```

---

## Historical Reference

For detailed information about the original sync architecture, see:
- `/home/jclee/app/grafana/docs/DEPRECATED-REALTIME_SYNC.md`

For current NFS architecture, see:
- `/home/jclee/app/grafana/CLAUDE.md` (section: "⚠️ CRITICAL: NFS Mount Architecture")
- `/home/jclee/app/grafana/README.md` (section: "Verify NFS Mount")

---

**Note**: These scripts are preserved for historical reference only. They are no longer needed and should not be used in the current NFS-based architecture.
