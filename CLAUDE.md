# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Grafana Monitoring Stack deployment configuration for Synology NAS, providing a complete observability solution with Grafana, Prometheus, Loki, and Alertmanager. The stack is optimized for Docker deployment with Traefik integration and supports both Portainer and docker-compose deployments.

## Key Commands

### Deployment
```bash
# Create volume structure (required before first deployment)
./scripts/create-volume-structure.sh
# Or with custom path:
GRAFANA_PATH=/custom/path ./scripts/create-volume-structure.sh

# Deploy with docker-compose
cd compose
docker-compose up -d

# Deploy with Portainer (use portainer-stack.yml)
# Upload to Portainer as stack with Git repository integration
```

### Operations
```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs -f [service-name]

# Update services
docker-compose pull
docker-compose up -d

# Backup Grafana data
./scripts/backup.sh
```

## Architecture

### Service Topology
- **Grafana** (port 3000): Central dashboard and visualization platform
- **Prometheus** (port 9090): Time-series metrics database scraping targets every 15s
- **Loki** (port 3100): Log aggregation system for centralized logging
- **Alertmanager** (port 9093): Alert routing and management
- **Promtail**: Log collector shipping logs to Loki
- **Node Exporter** (port 9100): Host metrics collector
- **cAdvisor** (port 8080): Container metrics collector

### Network Architecture
- **traefik-public**: External network for Traefik reverse proxy integration
- **monitoring-net**: Internal bridge network for inter-service communication
- All services exposed via Traefik with SSL termination at `*.jclee.me` domains

### Volume Management
Two deployment strategies:
1. **Local volumes** (docker-compose.yml): Simple Docker volumes for single-host deployments
2. **NFS volumes** (portainer-stack.yml): Network-attached storage for multi-host/Portainer deployments

Volume ownership requirements:
- Grafana: uid=472, gid=472
- Prometheus/Alertmanager: uid=65534, gid=65534 (nobody)
- Loki: uid=10001, gid=10001

## Configuration Files

### Critical Configurations
- `compose/docker-compose.yml`: Primary deployment configuration
- `compose/portainer-stack.yml`: Portainer-optimized with NFS support
- `configs/prometheus.yml`: Prometheus scrape configurations and targets
- `configs/promtail-config.yml`: Log collection and forwarding rules
- `configs/provisioning/`: Grafana auto-provisioning (datasources, dashboards)

### Environment Variables
Key variables (set in `.env` or Portainer):
- `GRAFANA_PATH`: Base directory for volumes (default: `/volume1/docker/grafana`)
- `GRAFANA_ADMIN_PASSWORD`: Admin password (default: bingogo1)
- `*_DOMAIN`: Service domains for Traefik routing
- `PROMETHEUS_RETENTION`: Data retention period (default: 30d)

## Development Workflow

### Making Configuration Changes
1. Edit configuration files in `configs/` directory
2. For Prometheus changes: Reload via API or restart container
3. For Grafana provisioning: Changes auto-reload on container restart
4. Test changes locally before committing

### Adding New Monitoring Targets
1. Add scrape config to `configs/prometheus.yml`
2. Deploy exporter container if needed (add to docker-compose.yml)
3. Configure network connectivity (ensure monitoring-net access)
4. Create Grafana dashboard for new metrics

### Troubleshooting
```bash
# Check volume permissions
ls -la /volume1/docker/grafana/

# Verify network connectivity
docker network inspect grafana-monitoring-net

# Test Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check Grafana datasources
curl http://localhost:3000/api/datasources
```

## Important Considerations

1. **Volume Permissions**: The create-volume-structure.sh script MUST be run before first deployment to set correct ownership
2. **Network Dependencies**: Requires external `traefik-public` network to exist
3. **Synology Compatibility**: Configured specifically for Synology NAS paths and constraints
4. **Security**: Default admin password should be changed in production
5. **Resource Usage**: Monitor disk usage as Prometheus/Loki can consume significant storage over time