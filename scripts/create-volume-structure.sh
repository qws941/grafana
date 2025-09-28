#!/bin/bash

# Grafana Monitoring Stack Volume Structure Creator
# This script creates the necessary directory structure for the monitoring stack

set -e

# Default GRAFANA_PATH (can be overridden by environment variable)
GRAFANA_PATH="${GRAFANA_PATH:-/volume1/docker/grafana}"

echo "🏗️ Creating Grafana monitoring stack directory structure..."
echo "📁 Base path: ${GRAFANA_PATH}"

# Create base directory
echo "Creating base directory: ${GRAFANA_PATH}"
sudo mkdir -p "${GRAFANA_PATH}"

# Create service-specific directories
echo "Creating service directories..."

# Grafana data directory
sudo mkdir -p "${GRAFANA_PATH}/grafana"
echo "  ✅ ${GRAFANA_PATH}/grafana"

# Prometheus data directory
sudo mkdir -p "${GRAFANA_PATH}/prometheus"
echo "  ✅ ${GRAFANA_PATH}/prometheus"

# Loki data directory
sudo mkdir -p "${GRAFANA_PATH}/loki"
echo "  ✅ ${GRAFANA_PATH}/loki"

# Alertmanager data directory
sudo mkdir -p "${GRAFANA_PATH}/alertmanager"
echo "  ✅ ${GRAFANA_PATH}/alertmanager"

# Set proper ownership (Docker containers typically run as specific users)
echo "🔐 Setting proper ownership and permissions..."

# Grafana runs as user 472
sudo chown -R 472:472 "${GRAFANA_PATH}/grafana"
sudo chmod -R 755 "${GRAFANA_PATH}/grafana"

# Prometheus runs as user 65534 (nobody)
sudo chown -R 65534:65534 "${GRAFANA_PATH}/prometheus"
sudo chmod -R 755 "${GRAFANA_PATH}/prometheus"

# Loki runs as user 10001
sudo chown -R 10001:10001 "${GRAFANA_PATH}/loki"
sudo chmod -R 755 "${GRAFANA_PATH}/loki"

# Alertmanager runs as user 65534 (nobody)
sudo chown -R 65534:65534 "${GRAFANA_PATH}/alertmanager"
sudo chmod -R 755 "${GRAFANA_PATH}/alertmanager"

echo "📊 Directory structure created successfully!"
echo ""
echo "📁 Created structure:"
echo "   ${GRAFANA_PATH}/"
echo "   ├── grafana/     (uid:472, gid:472)"
echo "   ├── prometheus/  (uid:65534, gid:65534)"
echo "   ├── loki/        (uid:10001, gid:10001)"
echo "   └── alertmanager/ (uid:65534, gid:65534)"
echo ""
echo "🚀 Ready for Docker Compose deployment!"
echo ""
echo "💡 To use a different base path, run:"
echo "   GRAFANA_PATH=/your/path $0"