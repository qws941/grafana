#!/bin/bash
cd /home/jclee/app/grafana
exec /home/jclee/.nvm/versions/node/v22.20.0/bin/node scripts/realtime-sync.js
