# Grafana Monitoring Stack - 데모 가이드

## 빠른 시작 (Quick Start)

### 1. 접속 정보
```
Grafana:       https://grafana.jclee.me
Prometheus:    https://prometheus.jclee.me
Loki:          https://loki.jclee.me
AlertManager:  https://alertmanager.jclee.me
n8n:           https://n8n.jclee.me
```

### 2. Grafana 로그인
```
URL: https://grafana.jclee.me
Username: admin
Password: (환경 변수 GRAFANA_ADMIN_PASSWORD)
```

### 3. 주요 대시보드

#### 시스템 모니터링
```
Grafana → Dashboards → Browse
- System Overview
- Docker Containers
- Node Exporter
- Network Traffic
```

#### 애플리케이션 모니터링
```
- Blacklist Service Dashboard
- n8n Workflow Dashboard
- Service Health Overview
```

## 데모 시나리오

### 시나리오 1: 서비스 메트릭 확인

#### 1.1 Prometheus 메트릭 조회
```bash
# Blacklist 서비스 HTTP 요청 수
curl 'https://prometheus.jclee.me/api/v1/query?query=rate(http_requests_total{job="blacklist"}[5m])'

# n8n 워크플로우 실행 수
curl 'https://prometheus.jclee.me/api/v1/query?query=n8n_workflow_executions_total'
```

#### 1.2 Grafana 대시보드
```
1. grafana.jclee.me 접속
2. Explore → Prometheus 선택
3. Query:
   rate(http_requests_total{job="blacklist"}[5m])
4. Run Query → 그래프 확인
```

### 시나리오 2: 로그 분석

#### 2.1 Loki 로그 쿼리
```
1. grafana.jclee.me → Explore
2. Data source: Loki 선택
3. LogQL 쿼리:
   {job="blacklist"} |~ "error|ERROR"
4. Run Query → 에러 로그 확인
```

#### 2.2 실시간 로그 스트림
```
1. Explore → Loki
2. Query: {job="blacklist"}
3. "Live" 버튼 클릭
4. 실시간 로그 스트림 확인
```

### 시나리오 3: 알림 설정

#### 3.1 AlertManager 규칙
```yaml
# Prometheus Alert Rule 예시
groups:
  - name: blacklist_alerts
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{job="blacklist",status=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Blacklist service high error rate"
```

#### 3.2 알림 확인
```
1. alertmanager.jclee.me 접속
2. Active Alerts 확인
3. Silences 관리
```

### 시나리오 4: n8n 워크플로우 자동화

#### 4.1 n8n 로그인
```
URL: https://n8n.jclee.me
Username: admin
Password: (환경 변수 N8N_PASSWORD)
```

#### 4.2 워크플로우 예제
```
1. New Workflow 생성
2. Trigger: Webhook
3. Action: Prometheus Query
4. Condition: Error rate > 0.1
5. Action: Send Slack Alert
6. Save & Activate
```

## 고급 사용법

### PromQL 쿼리 예제

#### 서비스 가용성
```promql
# 서비스 Up 상태
up{job="blacklist"}

# 5분간 평균 응답 시간
rate(http_request_duration_seconds_sum{job="blacklist"}[5m])
/ rate(http_request_duration_seconds_count{job="blacklist"}[5m])

# P99 레이턴시
histogram_quantile(0.99,
  rate(http_request_duration_seconds_bucket{job="blacklist"}[5m])
)
```

#### 리소스 사용량
```promql
# CPU 사용률
rate(container_cpu_usage_seconds_total{name="blacklist-app"}[5m]) * 100

# 메모리 사용률
container_memory_usage_bytes{name="blacklist-app"}
/ container_spec_memory_limit_bytes{name="blacklist-app"} * 100
```

### LogQL 쿼리 예제

#### 로그 필터링
```logql
# 에러 로그만
{job="blacklist"} |~ "error|ERROR|exception"

# 특정 시간대
{job="blacklist"} | json | level="error"

# 메트릭 변환
rate({job="blacklist"} |~ "error" [5m])
```

### 대시보드 생성

#### 1. 새 대시보드
```
1. Grafana → Dashboards → New Dashboard
2. Add Panel
3. Query: Prometheus 또는 Loki
4. Visualization: Graph, Gauge, Table 등
5. Save Dashboard
```

#### 2. 변수 활용
```
1. Dashboard Settings → Variables
2. Add Variable: $service
3. Query: label_values(up, job)
4. Panel Query: up{job="$service"}
```

## Troubleshooting

### 문제 1: Grafana 접속 불가
```bash
# Synology NAS 연결 확인
ping 192.168.50.215

# Grafana 컨테이너 상태 (Synology에서)
docker ps | grep grafana

# 로그 확인
docker logs grafana-container
```

### 문제 2: Prometheus 메트릭 수집 실패
```bash
# Prometheus targets 확인
curl https://prometheus.jclee.me/api/v1/targets

# 서비스 /metrics 엔드포인트 확인
curl http://blacklist.jclee.me:2542/metrics
```

### 문제 3: Loki 로그 없음
```bash
# Promtail 상태 확인
docker ps | grep promtail

# Promtail 로그
docker logs promtail-container

# Loki 연결 테스트
curl https://loki.jclee.me/ready
```

## 관련 링크
- [프로젝트 이력서](../resume/README.md)
- [Prometheus 설정](../configs/prometheus.yml)
- [Loki 설정](../configs/loki-config.yaml)
- [AlertManager 설정](../configs/alertmanager.yml)
- [Grafana 공식 문서](https://grafana.com/docs/)
