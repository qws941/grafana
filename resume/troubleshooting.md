# Troubleshooting Guide

## Quick Diagnosis

### Health Check Dashboard

**First step for any issue**: Run automated health check
```bash
./scripts/health-check.sh
```

**Expected output (healthy system)**:
```
✅ Grafana: OK
✅ Prometheus: OK
✅ Loki: OK
✅ AlertManager: OK
✅ All Prometheus targets are up
✅ Loki is ingesting logs (15 streams active)
✅ All health checks passed!
```

---

## Service-Specific Issues

### Grafana

#### Issue: Grafana unreachable (HTTP 502/504)

**Symptoms**:
- https://grafana.jclee.me returns 502 Bad Gateway or 504 Gateway Timeout
- Cannot access Grafana UI

**Diagnosis**:
```bash
# Check container status
ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep grafana"

# Check container logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs grafana-container --tail 50"

# Check health
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container wget -qO- http://localhost:3000/api/health" | jq '.'
```

**Common causes & fixes**:

1. **Container crashed/exited**:
   ```bash
   # Restart container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
   ```

2. **Volume permission issues**:
   ```bash
   # Fix permissions
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo chown -R 472:472 /volume1/grafana/data/grafana"
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
   ```

3. **Database corruption**:
   ```bash
   # Check database
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec grafana-container sqlite3 /var/lib/grafana/grafana.db 'PRAGMA integrity_check;'"

   # If corrupted, restore from backup
   # See resume/deployment.md - Backup and Restore
   ```

4. **Traefik routing issues**:
   ```bash
   # Check Traefik logs
   ssh -p 1111 jclee@192.168.50.215 "sudo docker logs traefik | grep grafana"

   # Verify traefik-public network
   ssh -p 1111 jclee@192.168.50.215 \
     "docker network inspect traefik-public | jq '.[] | .Containers'"
   ```

#### Issue: Dashboards not loading / "No Data"

**Symptoms**:
- Dashboard panels show "No Data"
- Queries return empty results

**Diagnosis**:
```bash
# Check datasource status
curl -u admin:bingogo1 https://grafana.jclee.me/api/datasources | \
  jq '.[] | {name: .name, type: .type, url: .url}'

# Test Prometheus connectivity from Grafana
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container wget -qO- http://prometheus-container:9090/-/healthy"

# Validate metrics exist
./scripts/validate-metrics.sh -d <dashboard-file>
```

**Common causes & fixes**:

1. **Datasource unavailable**:
   ```bash
   # Check Prometheus/Loki containers
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep -E 'prometheus|loki'"

   # Restart datasource container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart prometheus-container"
   ```

2. **Metric doesn't exist** (learned from 2025-10-13 incident):
   ```bash
   # Validate metric exists
   curl -s "https://prometheus.jclee.me/api/v1/label/__name__/values" | \
     jq -r '.data[]' | grep <metric-name>

   # If not found, check Prometheus targets
   curl -s https://prometheus.jclee.me/api/v1/targets | \
     jq '.data.activeTargets[] | select(.health != "up")'
   ```

3. **Wrong datasource UID**:
   ```bash
   # Check datasource UID in dashboard JSON
   grep '"uid"' configs/provisioning/dashboards/*/*.json | grep datasource

   # Should be: "uid": "prometheus" or "uid": "loki"
   ```

4. **Dashboard auto-provision failed**:
   ```bash
   # Check Grafana logs for provisioning errors
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker logs grafana-container | grep -i provision"

   # Restart Grafana to re-provision
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
   ```

#### Issue: Cannot login / Authentication failed

**Symptoms**:
- Invalid username/password
- Login page not accessible

**Diagnosis**:
```bash
# Check Grafana logs
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs grafana-container | grep -i auth"

# Verify environment variable
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container env | grep GF_SECURITY_ADMIN_PASSWORD"
```

**Fix**:
```bash
# Reset admin password
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container grafana-cli admin reset-admin-password <new-password>"

# Update .env file
vim .env  # Update GRAFANA_ADMIN_PASSWORD

# Restart Grafana
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart grafana-container"
```

---

### Prometheus

#### Issue: Prometheus targets down

**Symptoms**:
- Prometheus targets page shows red/down status
- Metrics not being collected

**Diagnosis**:
```bash
# Check targets status
curl -s https://prometheus.jclee.me/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, error: .lastError}'

# Check scrape config
curl -s https://prometheus.jclee.me/api/v1/status/config | \
  jq '.data.yaml' | grep -A5 'job_name'
```

**Common causes & fixes**:

1. **Target service down**:
   ```bash
   # Check target container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep <service-name>"

   # Restart target container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart <service-container>"
   ```

2. **Wrong target address**:
   ```bash
   # Verify container name and port
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker inspect <service-container> | jq '.[0].NetworkSettings.Networks'"

   # Fix in configs/prometheus.yml
   vim configs/prometheus.yml
   # Update target: 'correct-container-name:port'

   # Wait for auto-sync, then reload
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
   ```

3. **Network connectivity**:
   ```bash
   # Test connectivity from Prometheus
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget -qO- http://<target-container>:<port>/metrics"

   # Check network membership
   ssh -p 1111 jclee@192.168.50.215 \
     "docker network inspect grafana-monitoring-net" | \
     jq '.[] | .Containers | keys'
   ```

4. **Metrics endpoint missing**:
   ```bash
   # Verify service exposes /metrics
   curl -s http://<target>:<port>/metrics | head -20
   ```

#### Issue: Prometheus query slow/timeout

**Symptoms**:
- Queries take >2 minutes
- Query timeout errors in Grafana

**Diagnosis**:
```bash
# Check Prometheus metrics
curl -s "https://prometheus.jclee.me/api/v1/query?query=prometheus_tsdb_head_series" | \
  jq '.data.result[0].value[1]'  # Number of active series

curl -s "https://prometheus.jclee.me/api/v1/query?query=rate(prometheus_tsdb_compactions_total[5m])" | \
  jq '.'  # Compaction rate
```

**Common causes & fixes**:

1. **Too many active series**:
   ```bash
   # Drop unnecessary metrics with metric_relabel_configs
   vim configs/prometheus.yml
   # Add under scrape_configs:
   #   metric_relabel_configs:
   #     - source_labels: [__name__]
   #       regex: 'unwanted_metric_.*'
   #       action: drop

   # Reload Prometheus
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget --post-data='' -qO- http://localhost:9090/-/reload"
   ```

2. **Large time range query**:
   ```bash
   # Use recording rules for frequently queried metrics
   vim configs/recording-rules.yml
   # Add pre-aggregated metrics

   # Use smaller time ranges in dashboards
   # Change from: [30d] to: [7d]
   ```

3. **High cardinality labels**:
   ```bash
   # Identify high cardinality metrics
   curl -s "https://prometheus.jclee.me/api/v1/label/__name__/values" | \
     jq -r '.data[]' | while read metric; do
       count=$(curl -s "https://prometheus.jclee.me/api/v1/query?query=count($metric)" | jq '.data.result[0].value[1]')
       echo "$count $metric"
     done | sort -rn | head -10

   # Drop or relabel high cardinality metrics
   ```

#### Issue: Prometheus running out of disk space

**Symptoms**:
- Prometheus container exits with OOM
- Disk usage alert

**Diagnosis**:
```bash
# Check Prometheus data size
ssh -p 1111 jclee@192.168.50.215 \
  "du -sh /volume1/grafana/data/prometheus"

# Check retention period
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker inspect prometheus-container | jq '.[0].Args'"
```

**Fix**:
```bash
# Option 1: Reduce retention period
vim .env
# Change: PROMETHEUS_RETENTION_TIME=15d (from 30d)

# Recreate container
ssh -p 1111 jclee@192.168.50.215 \
  "cd /volume1/grafana && docker compose up -d prometheus"

# Option 2: Expand disk space (NAS level)

# Option 3: Drop old data
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec prometheus-container promtool tsdb delete --time-range=0-<timestamp>"
```

---

### Loki

#### Issue: Logs not appearing in Loki

**Symptoms**:
- No logs in Grafana Explore (Loki datasource)
- Loki query returns empty results

**Diagnosis**:
```bash
# Check Loki ingestion rate
curl -s --get \
  --data-urlencode 'query=rate({job=~".+"}[5m])' \
  https://loki.jclee.me/loki/api/v1/query | \
  jq '.data.result | length'

# Check Promtail status
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs promtail-container --tail 50"

# List discovered targets
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec promtail-container wget -qO- http://localhost:9080/targets" | jq '.'
```

**Common causes & fixes**:

1. **Promtail not running**:
   ```bash
   # Check Promtail container
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep promtail"

   # Restart Promtail
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart promtail-container"
   ```

2. **Synology `db` logging driver** (documented limitation):
   ```bash
   # Check container logging driver
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker inspect <container> | jq '.[0].HostConfig.LogConfig.Type'"

   # If "db", Promtail cannot read logs
   # Solution: Use Prometheus metrics instead (more reliable)
   # See: docs/N8N-LOG-INVESTIGATION-2025-10-12.md
   ```

3. **Loki retention expired**:
   ```bash
   # Check retention period (default: 3 days)
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec loki-container cat /etc/loki/local-config.yaml | grep retention"

   # Logs older than retention are rejected
   # Query within retention window
   ```

4. **Network connectivity (Promtail → Loki)**:
   ```bash
   # Test from Promtail container
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec promtail-container wget -qO- http://loki-container:3100/ready"
   ```

#### Issue: Loki high memory usage

**Symptoms**:
- Loki container using >4GB RAM
- Container OOMKilled

**Diagnosis**:
```bash
# Check Loki memory usage
ssh -p 1111 jclee@192.168.50.215 \
  "docker stats loki-container --no-stream"

# Check number of active streams
curl -s "https://loki.jclee.me/loki/api/v1/query?query=count(count by (job) ({job=~\".+\"}))" | \
  jq '.data.result[0].value[1]'
```

**Fix**:
```bash
# Reduce retention period
vim configs/loki-config.yaml
# Change: retention_period: 2d (from 3d)

# Restart Loki
ssh -p 1111 jclee@192.168.50.215 "sudo docker restart loki-container"

# Limit ingestion rate (optional)
vim configs/loki-config.yaml
# Add under limits_config:
#   ingestion_rate_mb: 10
#   ingestion_burst_size_mb: 20
```

---

### AlertManager

#### Issue: Alerts not firing

**Symptoms**:
- Expected alerts not appearing in AlertManager
- No notifications received

**Diagnosis**:
```bash
# Check Prometheus alert rules
curl -s https://prometheus.jclee.me/api/v1/rules | \
  jq '.data.groups[] | .rules[] | select(.type == "alerting") | {name: .name, state: .state}'

# Check AlertManager alerts
curl -s https://alertmanager.jclee.me/api/v2/alerts | \
  jq '.[] | {name: .labels.alertname, state: .status.state}'

# Check AlertManager logs
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs alertmanager-container --tail 50"
```

**Common causes & fixes**:

1. **Alert rule not firing**:
   ```bash
   # Test alert query
   curl -s "https://prometheus.jclee.me/api/v1/query?query=<alert-expr>" | jq '.'

   # Check alert evaluation
   curl -s https://prometheus.jclee.me/api/v1/rules | \
     jq '.data.groups[] | .rules[] | select(.name == "<alert-name>")'

   # Verify alert rule syntax
   vim configs/alert-rules/*.yml
   yamllint configs/alert-rules/*.yml
   ```

2. **AlertManager not receiving alerts**:
   ```bash
   # Check Prometheus alerting config
   curl -s https://prometheus.jclee.me/api/v1/status/config | \
     jq '.data.yaml' | grep -A3 'alerting:'

   # Test connectivity
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container wget -qO- http://alertmanager-container:9093/-/healthy"
   ```

3. **Alert silenced**:
   ```bash
   # List silences
   curl -s https://alertmanager.jclee.me/api/v2/silences | \
     jq '.[] | {comment: .comment, endsAt: .endsAt}'

   # Delete silence
   curl -X DELETE "https://alertmanager.jclee.me/api/v2/silence/<silence-id>"
   ```

#### Issue: Webhook not triggering (n8n)

**Symptoms**:
- AlertManager shows alerts firing
- n8n workflow not triggered

**Diagnosis**:
```bash
# Check AlertManager config
cat configs/alertmanager.yml | grep -A5 webhook

# Test webhook manually
curl -X POST https://n8n.jclee.me/webhook/alertmanager \
  -H "Content-Type: application/json" \
  -d '{
    "version": "4",
    "groupKey": "test",
    "status": "firing",
    "alerts": [{
      "status": "firing",
      "labels": {"alertname": "TestAlert"},
      "annotations": {"summary": "Test"}
    }]
  }'

# Check n8n workflow status
# Access n8n UI: https://n8n.jclee.me
```

**Common causes & fixes**:

1. **Wrong webhook URL**:
   ```bash
   # Verify webhook URL
   vim configs/alertmanager.yml
   # Should be: url: 'https://n8n.jclee.me/webhook/alertmanager'

   # Restart AlertManager
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart alertmanager-container"
   ```

2. **Network connectivity**:
   ```bash
   # Test from AlertManager container
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec alertmanager-container wget -qO- https://n8n.jclee.me/healthz"
   ```

3. **n8n workflow deactivated**:
   - Login to n8n UI
   - Navigate to Workflows → AlertManager Webhook
   - Verify Status = Active

---

## Real-time Sync Issues

### Issue: Config changes not syncing

**Symptoms**:
- Edit config locally, changes not on NAS
- Sync latency >10 seconds

**Diagnosis**:
```bash
# Check sync service status
sudo systemctl status grafana-sync

# Check real-time logs
sudo journalctl -u grafana-sync -f

# Test SSH connection
ssh -p 1111 jclee@192.168.50.215 "echo 'Connection OK'"

# Manual sync test
./scripts/sync-to-synology.sh
```

**Common causes & fixes**:

1. **Sync service stopped**:
   ```bash
   # Restart service
   sudo systemctl restart grafana-sync

   # Enable on boot
   sudo systemctl enable grafana-sync
   ```

2. **SSH authentication failed**:
   ```bash
   # Test SSH key
   ssh -p 1111 -i ~/.ssh/id_rsa jclee@192.168.50.215

   # If fails, regenerate key
   ssh-keygen -t rsa -b 4096
   ssh-copy-id -p 1111 jclee@192.168.50.215
   ```

3. **rsync failed**:
   ```bash
   # Check rsync installed
   which rsync

   # Test rsync
   rsync -avz --progress -e "ssh -p 1111" \
     configs/ jclee@192.168.50.215:/volume1/grafana/configs/
   ```

4. **File watcher limit exceeded**:
   ```bash
   # Increase inotify limit
   sudo sysctl fs.inotify.max_user_watches=524288

   # Make permanent
   echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

---

## Performance Issues

### Issue: Grafana dashboard slow to load

**Symptoms**:
- Dashboard takes >10 seconds to load
- Panels timeout

**Diagnosis**:
```bash
# Check panel queries
# In Grafana UI: Dashboard → Panel → Edit → Query Inspector

# Check Prometheus query performance
curl -s "https://prometheus.jclee.me/api/v1/query?query=<panel-query>" | \
  jq '.data.stats'

# Check Grafana logs
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs grafana-container | grep -i timeout"
```

**Fix**:
1. **Use recording rules** for complex queries
2. **Reduce time range** in dashboard settings
3. **Use `$__rate_interval`** instead of fixed intervals
4. **Aggregate data** with `sum by (label)` instead of all series

### Issue: High CPU usage

**Symptoms**:
- Prometheus/Grafana container using >80% CPU
- NAS slow/unresponsive

**Diagnosis**:
```bash
# Check container CPU usage
ssh -p 1111 jclee@192.168.50.215 \
  "docker stats --no-stream | grep -E 'grafana|prometheus|loki'"

# Check active series count
curl -s "https://prometheus.jclee.me/api/v1/query?query=prometheus_tsdb_head_series" | \
  jq '.data.result[0].value[1]'

# Check query rate
curl -s "https://prometheus.jclee.me/api/v1/query?query=rate(prometheus_http_requests_total[5m])" | \
  jq '.data.result[] | {handler: .metric.handler, value: .value[1]}'
```

**Fix**:
1. **Drop unnecessary metrics** (metric_relabel_configs)
2. **Use recording rules** for frequently queried metrics
3. **Reduce scrape frequency** for non-critical targets
4. **Increase NAS resources** (CPU, memory)

---

## Network Issues

### Issue: Cannot access services externally

**Symptoms**:
- https://grafana.jclee.me unreachable from external network
- Works from internal network

**Diagnosis**:
```bash
# Check DNS resolution
dig grafana.jclee.me

# Check from external network
curl -vI https://grafana.jclee.me

# Check Traefik status
ssh -p 1111 jclee@192.168.50.215 "sudo docker logs traefik | tail -50"

# Check SSL certificates
curl -vI https://grafana.jclee.me 2>&1 | grep "SSL certificate"
```

**Common causes & fixes**:

1. **DNS not propagated**:
   - Wait 5-10 minutes for DNS propagation
   - Check CloudFlare DNS settings
   - Verify A record points to correct IP

2. **Firewall blocking**:
   ```bash
   # Check NAS firewall rules
   # Synology DSM → Control Panel → Security → Firewall
   # Ensure ports 80, 443 are open
   ```

3. **Traefik not running**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "sudo docker ps | grep traefik"

   # Restart Traefik (if exists)
   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart traefik"
   ```

4. **SSL certificate expired**:
   ```bash
   # Check certificate expiry
   echo | openssl s_client -connect grafana.jclee.me:443 2>/dev/null | \
     openssl x509 -noout -dates

   # Renew via CloudFlare (automatic)
   ```

---

## Data Loss / Corruption

### Issue: Grafana data corrupted

**Symptoms**:
- Dashboards missing
- Users cannot login
- Settings lost

**Diagnosis**:
```bash
# Check Grafana database
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker exec grafana-container sqlite3 /var/lib/grafana/grafana.db 'PRAGMA integrity_check;'"

# Check data volume
ssh -p 1111 jclee@192.168.50.215 \
  "ls -la /volume1/grafana/data/grafana/"
```

**Recovery**:
```bash
# Stop Grafana
ssh -p 1111 jclee@192.168.50.215 "sudo docker stop grafana-container"

# Restore from backup (see resume/deployment.md)
ssh -p 1111 jclee@192.168.50.215 "
  sudo rm -rf /volume1/grafana/data/grafana/*
  sudo tar -xzf /volume1/backups/grafana-backup-<date>.tar.gz -C /
  sudo chown -R 472:472 /volume1/grafana/data/grafana
"

# Start Grafana
ssh -p 1111 jclee@192.168.50.215 "sudo docker start grafana-container"

# Verify
curl -sf https://grafana.jclee.me/api/health
```

### Issue: Prometheus data loss

**Symptoms**:
- Historical metrics missing
- Gaps in graphs

**Diagnosis**:
```bash
# Check Prometheus data size
ssh -p 1111 jclee@192.168.50.215 \
  "du -sh /volume1/grafana/data/prometheus"

# Check retention period
curl -s https://prometheus.jclee.me/api/v1/status/flags | \
  jq '.data | ."storage.tsdb.retention.time"'
```

**Recovery**:
- Historical data cannot be recovered (time-series database)
- Ensure future data is retained:
  1. Verify retention period: `PROMETHEUS_RETENTION_TIME=30d`
  2. Monitor disk space
  3. Implement backup strategy (optional)

---

## Emergency Procedures

### Complete System Failure

**Scenario**: All services down, cannot access Grafana/Prometheus/Loki

**Recovery steps**:

1. **SSH to NAS**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215
   cd /volume1/grafana
   ```

2. **Check all containers**:
   ```bash
   sudo docker ps -a | grep -E 'grafana|prometheus|loki'
   ```

3. **Restart all services**:
   ```bash
   sudo docker compose down
   sudo docker compose up -d
   ```

4. **Monitor startup**:
   ```bash
   # Watch container health
   watch -n 2 "docker ps | grep -E 'grafana|prometheus|loki'"

   # Check logs
   sudo docker compose logs -f
   ```

5. **Run health check** (from local machine):
   ```bash
   ./scripts/health-check.sh
   ```

6. **If still failing, restore from backup**:
   - See resume/deployment.md - Backup and Restore section

### Prometheus Target Mass Outage

**Scenario**: All Prometheus targets suddenly go down

**Investigation**:

1. **Check Prometheus connectivity**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container ping -c 3 grafana-container"
   ```

2. **Check network**:
   ```bash
   ssh -p 1111 jclee@192.168.50.215 \
     "docker network inspect grafana-monitoring-net" | \
     jq '.[] | .Containers | length'
   ```

3. **Restart network** (if needed):
   ```bash
   ssh -p 1111 jclee@192.168.50.215 "
     sudo docker compose down
     sudo docker network rm grafana-monitoring-net
     sudo docker compose up -d
   "
   ```

### Disk Space Critical

**Scenario**: NAS disk >95% full

**Immediate actions**:

1. **Reduce Prometheus retention**:
   ```bash
   vim .env
   # Change: PROMETHEUS_RETENTION_TIME=7d (from 30d)

   ssh -p 1111 jclee@192.168.50.215 \
     "cd /volume1/grafana && docker compose up -d prometheus"
   ```

2. **Reduce Loki retention**:
   ```bash
   vim configs/loki-config.yaml
   # Change: retention_period: 1d (from 3d)

   ssh -p 1111 jclee@192.168.50.215 "sudo docker restart loki-container"
   ```

3. **Clean old data**:
   ```bash
   # Clean Prometheus data
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo docker exec prometheus-container rm -rf /prometheus/wal/*"

   # Clean Loki data
   ssh -p 1111 jclee@192.168.50.215 \
     "sudo rm -rf /volume1/grafana/data/loki/chunks/*"
   ```

---

## Preventive Maintenance

### Regular Checks (Weekly)

- [ ] Run health check: `./scripts/health-check.sh`
- [ ] Check disk space: `du -sh /volume1/grafana/data/*`
- [ ] Verify all targets UP: https://prometheus.jclee.me/targets
- [ ] Review alerts: https://alertmanager.jclee.me
- [ ] Check sync service: `sudo systemctl status grafana-sync`

### Scheduled Maintenance (Monthly)

- [ ] Review and rotate logs (if needed)
- [ ] Update Docker images (minor versions)
- [ ] Backup Grafana data: `./scripts/backup.sh`
- [ ] Review alert rules (tuning)
- [ ] Check SSL certificate expiry

### Long-term Maintenance (Quarterly)

- [ ] Review recording rules (optimization)
- [ ] Audit dashboard usage (remove unused)
- [ ] Review security settings
- [ ] Test disaster recovery procedures
- [ ] Update documentation

---

## Getting Help

### Documentation

- resume/architecture.md - System architecture
- resume/api.md - API reference
- resume/deployment.md - Deployment procedures
- docs/OPERATIONAL-RUNBOOK.md - Day-to-day operations
- docs/GRAFANA-BEST-PRACTICES-2025.md - Dashboard design

### Logs

**View all logs**:
```bash
ssh -p 1111 jclee@192.168.50.215 "sudo docker compose logs --tail 100"
```

**Search logs**:
```bash
# Search for errors
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker compose logs | grep -i error"

# Service-specific
ssh -p 1111 jclee@192.168.50.215 \
  "sudo docker logs prometheus-container 2>&1 | grep -i 'reload\|error'"
```

### Contact

- Slack: #monitoring-support
- Email: devops@example.com
- On-call: Check PagerDuty

---

**Last Updated**: 2025-10-17
**Troubleshooting Version**: 1.0
**Maintainer**: DevOps Team
