# Screenshots

This directory contains screenshots of the Grafana Monitoring Stack in action.

## Required Screenshots

### Core Monitoring
- [ ] 01-grafana-home.png - Grafana homepage with dashboard list
- [ ] 02-monitoring-stack-health.png - Monitoring Stack Health dashboard
- [ ] 03-prometheus-targets.png - Prometheus targets page (all UP)
- [ ] 04-loki-explore.png - Loki logs in Grafana Explore
- [ ] 05-alertmanager-alerts.png - AlertManager alerts page

### Dashboards
- [ ] 06-infrastructure-metrics.png - Infrastructure Metrics dashboard
- [ ] 07-container-performance.png - Container Performance dashboard
- [ ] 08-n8n-workflow-automation.png - n8n Workflow Automation (REDS) dashboard
- [ ] 09-log-analysis.png - Log Analysis dashboard
- [ ] 10-alert-overview.png - Alert Overview dashboard

### Configuration
- [ ] 11-datasources.png - Grafana datasources configuration
- [ ] 12-dashboard-provisioning.png - Dashboard provisioning setup
- [ ] 13-prometheus-config.png - Prometheus configuration editor
- [ ] 14-recording-rules.png - Prometheus recording rules

### Operations
- [ ] 15-health-check-output.png - Health check script output
- [ ] 16-metrics-validation.png - Metrics validation script output
- [ ] 17-real-time-sync-logs.png - Real-time sync service logs
- [ ] 18-docker-ps-output.png - Docker container status

## Screenshot Guidelines

**Format**: PNG (preferred), JPEG
**Resolution**: 1920x1080 or higher
**Compression**: Optimize for web (use pngquant or similar)

**Capture tool**:
```bash
# Linux (with scrot)
scrot -s screenshot.png

# macOS
Cmd+Shift+4

# Windows
Win+Shift+S
```

**Naming convention**: `<number>-<descriptive-name>.png`
