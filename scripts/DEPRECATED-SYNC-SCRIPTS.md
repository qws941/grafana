# DEPRECATED: Sync Scripts

**⚠️ ALL SYNC SCRIPTS IN THIS DIRECTORY ARE DEPRECATED**

## Reason

The project now uses **NFS mount** for automatic synchronization. All sync-related scripts are no longer needed.

## Deprecated Scripts

| Script | Status | Safe to Delete |
|--------|--------|----------------|
| `realtime-sync.sh` | ❌ Deprecated | ✅ Yes |
| `realtime-sync.js` | ❌ Deprecated | ✅ Yes |
| `start-sync-daemon.sh` | ❌ Deprecated | ✅ Yes |
| `start-sync-service.sh` | ❌ Deprecated | ✅ Yes |
| `status-sync-daemon.sh` | ❌ Deprecated | ✅ Yes |
| `stop-sync-daemon.sh` | ❌ Deprecated | ✅ Yes |
| `sync-from-synology.sh` | ❌ Deprecated | ✅ Yes |
| `sync-to-synology.sh` | ❌ Deprecated | ✅ Yes |

## NFS Mount Configuration

**Current Setup**:
```bash
# /etc/fstab entry
192.168.50.215:/volume1/grafana  /home/jclee/app/grafana  nfs  rw,noatime,hard  0  0
```

**Verification**:
```bash
mount | grep grafana
# Output: 192.168.50.215:/volume1/grafana on /home/jclee/app/grafana type nfs
```

## Migration Completed

- **Date**: 2025-10-18
- **Action**: grafana-sync.service stopped and disabled
- **Replacement**: NFS mount (instant synchronization)
- **Status**: All sync scripts can be safely deleted

## Cleanup Commands

```bash
# Remove all deprecated sync scripts
cd /home/jclee/app/grafana/scripts
rm -f realtime-sync.* start-sync-* stop-sync-* status-sync-* sync-*.sh

# Remove systemd service file
sudo rm /etc/systemd/system/grafana-sync.service
sudo systemctl daemon-reload
```

**Note**: Keep this file until all sync scripts are deleted.
