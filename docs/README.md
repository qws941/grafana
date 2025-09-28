# Grafana Monitoring Stack

Complete monitoring infrastructure with Grafana, Prometheus, Loki, and supporting services.

## 📁 Directory Structure

```
grafana/
├── config/                    # Configuration files for each service
│   ├── grafana/              # Grafana configuration
│   │   └── grafana.ini       # Main Grafana config
│   ├── prometheus/           # Prometheus configuration
│   │   └── prometheus.yml    # Scraping and rules config
│   ├── loki/                 # Loki configuration
│   │   └── loki-config.yaml  # Log aggregation config
│   ├── promtail/             # Promtail configuration
│   │   └── promtail-config.yml # Log shipping config
│   └── alertmanager/         # Alertmanager configuration
│       └── alertmanager.yml  # Alert routing config
│
├── volumes/                  # Data persistence volumes
│   ├── grafana/             # Grafana data (dashboards, users)
│   ├── prometheus/          # Prometheus time-series data
│   ├── loki/                # Loki log storage
│   ├── promtail/            # Promtail positions
│   └── alertmanager/        # Alertmanager data
│
├── provisioning/            # Auto-provisioning configs
│   ├── dashboards/         # Dashboard definitions
│   ├── datasources/        # Data source configs
│   └── notifiers/          # Notification channels
│
├── scripts/                # Utility scripts
│   ├── fix-nfs-permissions.sh  # Fix NFS volume permissions
│   └── start-grafana.sh       # Startup script with checks
│
├── docker-compose.yml      # Main orchestration file
├── .env.example           # Environment variables template
└── .env                   # Local environment settings
```

## 🚀 Quick Start

1. **Copy environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Set required variables in `.env`:**
   - `GRAFANA_DOMAIN` - Your Grafana domain
   - `GF_ADMIN_PASSWORD` - Admin password
   - `NFS_MOUNT_PATH` - NFS mount path (if using)

3. **Fix permissions (if using NFS):**
   ```bash
   ./scripts/fix-nfs-permissions.sh
   ```

4. **Start the stack:**
   ```bash
   docker-compose up -d
   ```

5. **Access services:**
   - Grafana: https://grafana.jclee.me
   - Prometheus: Internal only (port 9090)
   - Loki: Internal only (port 3100)
   - Alertmanager: Internal only (port 9093)

## 🔧 Services

| Service | Purpose | Image |
|---------|---------|-------|
| **Grafana** | Visualization & Dashboards | `grafana/grafana:latest` |
| **Prometheus** | Metrics Collection | `prom/prometheus:latest` |
| **Loki** | Log Aggregation | `grafana/loki:2.9.0` |
| **Promtail** | Log Shipping | `grafana/promtail:latest` |
| **Node Exporter** | Host Metrics | `prom/node-exporter:latest` |
| **cAdvisor** | Container Metrics | `gcr.io/cadvisor/cadvisor:latest` |
| **Alertmanager** | Alert Management | `prom/alertmanager:latest` |

## 🔐 Security Features

- **No external ports exposed** - All services accessible only through Traefik
- **TLS/SSL enabled** - Cloudflare certificates via Traefik
- **Authentication required** - Grafana admin authentication
- **Network isolation** - Internal monitoring network
- **Read-only configs** - Configuration files mounted read-only

## 📊 Default Dashboards

The stack comes with pre-configured dashboards:
- System Overview (CPU, Memory, Disk, Network)
- Docker Containers (Resource usage per container)
- Application Logs (Aggregated from Loki)
- Alert Status (Active alerts and silences)

## 🔄 Backup & Restore

### Backup
```bash
# Backup all data volumes
tar -czf grafana-backup-$(date +%Y%m%d).tar.gz volumes/
```

### Restore
```bash
# Stop services
docker-compose down

# Restore volumes
tar -xzf grafana-backup-YYYYMMDD.tar.gz

# Start services
docker-compose up -d
```

## 📝 Configuration

### Adding New Scrape Targets

Edit `config/prometheus/prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'new-service'
    static_configs:
      - targets: ['service:port']
```

### Adding New Log Sources

Edit `config/promtail/promtail-config.yml`:
```yaml
scrape_configs:
  - job_name: new-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: new-service
          __path__: /var/log/new-service/*.log
```

### Creating Alert Rules

Edit `config/prometheus/prometheus.yml` or create rules files in `config/prometheus/rules/`

## 🐛 Troubleshooting

### Permission Issues
```bash
# Run the permission fix script
./scripts/fix-nfs-permissions.sh
```

### Service Not Starting
```bash
# Check logs
docker-compose logs -f <service-name>

# Verify config
docker-compose config
```

### Data Not Persisting
```bash
# Check volume mounts
docker inspect <container-name> | grep -A 10 Mounts
```

## 📚 Documentation

- [Grafana Docs](https://grafana.com/docs/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Loki Docs](https://grafana.com/docs/loki/)
- [Promtail Docs](https://grafana.com/docs/loki/latest/clients/promtail/)

## 🔗 GitHub Token

GitHub token is stored securely at:
```bash
source /home/jclee/.claude/secure_store/github-tokens.env
echo $GITHUB_TOKEN
```

Use with GitHub CLI:
```bash
gh auth login --with-token < <(echo $GITHUB_TOKEN)
```