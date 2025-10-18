# DEPRECATED: Real-time Sync Documentation

**⚠️ THIS DOCUMENT IS DEPRECATED AND NO LONGER APPLICABLE**

**Reason**: The project now uses **NFS mount** instead of sync scripts.

**NFS Mount Details**:
- Local: `/home/jclee/app/grafana`
- Remote: `192.168.50.215:/volume1/grafana`
- Type: NFS v3
- Changes are **instant** (filesystem-level synchronization)

**Deprecated Scripts** (located in `scripts/`):
- `realtime-sync.sh` - No longer needed
- `realtime-sync.js` - No longer needed
- `start-sync-daemon.sh` - No longer needed
- `start-sync-service.sh` - No longer needed
- `status-sync-daemon.sh` - No longer needed
- `stop-sync-daemon.sh` - No longer needed
- `sync-from-synology.sh` - No longer needed
- `sync-to-synology.sh` - No longer needed

**Systemd Service**:
- `grafana-sync.service` - **Disabled and stopped** (2025-10-18)

**Migration Notes**:
- All sync scripts can be safely deleted
- NFS mount is configured in `/etc/fstab`
- No manual synchronization required
- Changes are reflected immediately on Synology NAS

---

## Original Documentation (For Historical Reference)

See `REALTIME_SYNC.md.backup` for original content if needed.

**Last Updated**: 2025-10-18
**Status**: Deprecated
**Replacement**: NFS Mount (see main CLAUDE.md)
