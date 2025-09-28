#!/bin/bash
# Grafana Stack Backup Script

BACKUP_DIR="/backup/grafana-$(date +%Y%m%d_%H%M%S)"
COMPOSE_DIR="/home/jclee/.claude/grafana/compose"

echo "🔄 Starting Grafana stack backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup volumes
echo "📦 Backing up volumes..."
docker run --rm -v grafana_grafana-vol:/source -v "$BACKUP_DIR":/backup alpine tar czf /backup/grafana-vol.tar.gz -C /source .
docker run --rm -v grafana_prometheus-vol:/source -v "$BACKUP_DIR":/backup alpine tar czf /backup/prometheus-vol.tar.gz -C /source .
docker run --rm -v grafana_loki-vol:/source -v "$BACKUP_DIR":/backup alpine tar czf /backup/loki-vol.tar.gz -C /source .
docker run --rm -v grafana_alertmanager-vol:/source -v "$BACKUP_DIR":/backup alpine tar czf /backup/alertmanager-vol.tar.gz -C /source .

# Backup configuration files
echo "⚙️ Backing up configurations..."
cp -r /home/jclee/.claude/grafana/configs "$BACKUP_DIR/"
cp -r /home/jclee/.claude/grafana/compose "$BACKUP_DIR/"

echo "✅ Backup completed: $BACKUP_DIR"