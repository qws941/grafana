# 🚀 n8n 통합 모니터링 스택 배포 확인 가이드

## 📦 배포된 구성

### 서비스 12개
```
✅ 모니터링 스택 (7개):
1. grafana-container
2. prometheus-container
3. loki-container
4. promtail-container
5. alertmanager-container
6. node-exporter-container
7. cadvisor-container

✅ n8n 스택 (5개):
8. n8n-container
9. n8n-postgres-container
10. n8n-redis-container
11. n8n-postgres-exporter-container
12. n8n-redis-exporter-container
```

### Config 파일 연결
```
✅ grafana       → configs/provisioning/
✅ prometheus    → configs/prometheus.yml (n8n 스크랩 포함)
✅ loki          → configs/loki-config.yaml
✅ promtail      → configs/promtail-config.yml
✅ alertmanager  → configs/alertmanager.yml
```

---

## 🔍 배포 상태 확인

### 1. 컨테이너 실행 확인
```bash
# grafana.jclee.me 서버에서
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**예상 출력**: 12개 컨테이너 모두 `Up` 상태

### 2. n8n 웹 접속 확인
```bash
# 로컬에서
curl -I https://n8n.jclee.me

# 또는 브라우저에서
https://n8n.jclee.me
```

**예상**: HTTP 200 또는 로그인 페이지

### 3. Prometheus n8n 타겟 확인
```bash
# Prometheus API로 확인
curl -s http://prometheus.jclee.me/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("n8n")) | {job: .labels.job, health: .health}'
```

**예상 출력**:
```json
{"job": "n8n", "health": "up"}
{"job": "n8n-postgres", "health": "up"}
{"job": "n8n-redis", "health": "up"}
```

---

## 📊 로그 수집 확인

### 1. Loki에 n8n 로그 확인
```bash
# Loki API로 로그 스트림 확인
curl -s -G http://loki.jclee.me:3100/loki/api/v1/label/__name__/values | jq '.'

# n8n 로그 쿼리
curl -s -G "http://loki.jclee.me:3100/loki/api/v1/query" \
  --data-urlencode 'query={container_name="n8n-container"}' \
  --data-urlencode 'limit=10' | jq '.data.result'
```

**예상**: n8n 컨테이너 로그 스트림 존재

### 2. Promtail 수집 상태 확인
```bash
# Promtail이 Docker 로그를 수집하는지 확인
docker logs promtail-container --tail 50 | grep "n8n"
```

**예상**: n8n 관련 로그 파싱 메시지

### 3. Grafana Explore에서 로그 확인
```
1. https://grafana.jclee.me 접속
2. 왼쪽 메뉴 → Explore
3. Data source: Loki 선택
4. Query: {container_name="n8n-container"}
5. Run query
```

**예상**: n8n 컨테이너 로그가 실시간으로 보임

---

## 📈 메트릭 수집 확인

### 1. Prometheus에서 n8n 메트릭 쿼리
```bash
# n8n 메트릭 존재 확인
curl -s "http://prometheus.jclee.me/api/v1/query?query=n8n_workflow_executions_total" | jq '.data.result'

# Postgres 메트릭
curl -s "http://prometheus.jclee.me/api/v1/query?query=pg_up" | jq '.data.result'

# Redis 메트릭
curl -s "http://prometheus.jclee.me/api/v1/query?query=redis_up" | jq '.data.result'
```

**예상**: 각 메트릭의 value 값이 존재

### 2. n8n 메트릭 엔드포인트 직접 확인
```bash
# n8n 컨테이너 내부에서
docker exec n8n-container curl -s http://localhost:5678/metrics | grep "n8n_"
```

**예상**: `n8n_workflow_executions_total`, `n8n_execution_duration` 등 메트릭 출력

---

## 🎯 종합 헬스체크 스크립트

```bash
#!/bin/bash
# check-n8n-stack.sh

echo "🔍 n8n 스택 종합 점검"
echo "===================="

echo ""
echo "1️⃣ 컨테이너 상태"
docker ps --filter "name=n8n" --format "✅ {{.Names}}: {{.Status}}"

echo ""
echo "2️⃣ n8n 웹 접근"
if curl -f -s https://n8n.jclee.me > /dev/null; then
    echo "✅ n8n 웹 UI 접근 가능"
else
    echo "❌ n8n 웹 UI 접근 불가"
fi

echo ""
echo "3️⃣ Prometheus 타겟"
curl -s http://prometheus.jclee.me/api/v1/targets 2>/dev/null | \
  jq -r '.data.activeTargets[] | select(.labels.job | contains("n8n")) | "✅ \(.labels.job): \(.health)"'

echo ""
echo "4️⃣ Loki 로그 수집"
LOG_COUNT=$(curl -s -G "http://loki.jclee.me:3100/loki/api/v1/query" \
  --data-urlencode 'query={container_name="n8n-container"}' \
  --data-urlencode 'limit=1' 2>/dev/null | jq '.data.result | length')

if [ "$LOG_COUNT" -gt 0 ]; then
    echo "✅ n8n 로그 수집 중 (${LOG_COUNT} 스트림)"
else
    echo "⚠️ n8n 로그 스트림 없음"
fi

echo ""
echo "5️⃣ 메트릭 데이터"
METRIC_COUNT=$(curl -s "http://prometheus.jclee.me/api/v1/query?query=n8n_workflow_executions_total" 2>/dev/null | jq '.data.result | length')

if [ "$METRIC_COUNT" -gt 0 ]; then
    echo "✅ n8n 메트릭 수집 중 (${METRIC_COUNT} 시계열)"
else
    echo "⚠️ n8n 메트릭 데이터 없음 (워크플로우 실행 후 생성됨)"
fi

echo ""
echo "===================="
echo "🎉 점검 완료!"
```

---

## 🚨 트러블슈팅

### n8n 컨테이너가 시작되지 않는 경우
```bash
# 로그 확인
docker logs n8n-container

# 일반적인 원인:
# 1. PostgreSQL 연결 실패 → n8n-postgres 컨테이너 상태 확인
# 2. Redis 연결 실패 → n8n-redis 컨테이너 상태 확인
# 3. 환경 변수 오류 → .env 파일 또는 docker-compose.yml 확인
```

### 메트릭이 수집되지 않는 경우
```bash
# 1. n8n 메트릭 엔드포인트 확인
docker exec n8n-container curl http://localhost:5678/metrics

# 2. Prometheus 설정 리로드
curl -X POST http://prometheus.jclee.me/-/reload

# 3. Prometheus 타겟 상태 확인
curl http://prometheus.jclee.me/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="n8n")'
```

### 로그가 수집되지 않는 경우
```bash
# 1. Promtail 상태 확인
docker logs promtail-container --tail 100

# 2. Docker 소켓 접근 확인
docker exec promtail-container ls -la /var/run/docker.sock

# 3. Loki 연결 확인
docker exec promtail-container wget -O- http://loki:3100/ready
```

---

## 📋 체크리스트

### 배포 완료 확인
- [ ] 12개 컨테이너 모두 실행 중
- [ ] https://n8n.jclee.me 접속 가능
- [ ] Prometheus에 n8n 타겟 3개 UP 상태
- [ ] Grafana에서 n8n 로그 조회 가능
- [ ] Prometheus에서 n8n 메트릭 조회 가능

### Config 파일 연결 확인
- [ ] Grafana provisioning 폴더 마운트
- [ ] Prometheus config 마운트 및 n8n scrape 설정
- [ ] Loki config 마운트
- [ ] Promtail config 마운트
- [ ] Alertmanager config 마운트

---

## 🎯 성공 기준

1. **서비스 접근**: https://n8n.jclee.me → HTTP 200
2. **로그 수집**: Grafana Explore에서 n8n 로그 실시간 확인
3. **메트릭 수집**: Prometheus에서 n8n_* 메트릭 쿼리 가능
4. **워크플로우 실행**: n8n에서 워크플로우 생성 및 실행 → 메트릭 증가 확인

---

**배포 완료!** 🎉
