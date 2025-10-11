# Grafana Monitoring Stack - 프로젝트 이력서

## 프로젝트 개요
**중앙 모니터링 시스템** - Synology NAS 기반 통합 관측성 스택

## 핵심 기능
- ✅ Grafana 대시보드 (grafana.jclee.me)
- ✅ Prometheus 메트릭 수집 (prometheus.jclee.me)
- ✅ Loki 로그 집계 (loki.jclee.me)
- ✅ Promtail 로그 수집
- ✅ AlertManager 알림 관리
- ✅ n8n 워크플로우 자동화 (n8n.jclee.me)
- ✅ Node Exporter (시스템 메트릭)
- ✅ cAdvisor (컨테이너 메트릭)

## 기술 스택
### 모니터링 스택
- **Grafana:** 10.x (시각화 및 대시보드)
- **Prometheus:** latest (메트릭 수집/저장)
- **Loki:** latest (로그 집계)
- **Promtail:** latest (로그 수집)
- **AlertManager:** latest (알림 관리)

### 워크플로우 자동화
- **n8n:** latest (노코드 자동화)
- **PostgreSQL:** 15-alpine (n8n 데이터베이스)
- **Redis:** 7-alpine (n8n 큐 시스템)

### 메트릭 익스포터
- **Node Exporter:** 시스템 메트릭
- **cAdvisor:** 컨테이너 메트릭
- **PostgreSQL Exporter:** DB 메트릭
- **Redis Exporter:** 캐시 메트릭

### 인프라
- **호스트:** Synology NAS (192.168.50.215)
- **프록시:** Traefik (HTTPS)
- **네트워크:** grafana-monitoring-net (bridge)
- **스토리지:** Docker volumes (named)

## 아키텍처

### 데이터 흐름
```
[로컬 프로젝트들]
    ↓ (expose /metrics)
[Prometheus] ← (scrape) ← [각 프로젝트 /metrics 엔드포인트]
    ↓ (store)
[Prometheus TSDB]
    ↓ (query)
[Grafana 대시보드] → [사용자]

[로컬 Docker]
    ↓ (logs)
[Promtail] → (push) → [Loki]
    ↓ (store)
[Loki Storage]
    ↓ (query)
[Grafana 대시보드] → [사용자]
```

### 서비스 구성
**Synology NAS (192.168.50.215)**
- Grafana (3000) → grafana.jclee.me
- Prometheus (9090) → prometheus.jclee.me
- Loki (3100) → loki.jclee.me
- AlertManager (9093) → alertmanager.jclee.me
- n8n (5678) → n8n.jclee.me

**로컬 RHEL 호스트**
- Promtail (로그 수집 → Synology Loki 전송)
- 각 프로젝트 /metrics (Synology Prometheus가 scrape)

## 주요 성과

### 통합 관측성
- **로그:** 모든 프로젝트 로그 중앙 집계 (Loki)
- **메트릭:** 통합 메트릭 대시보드 (Prometheus + Grafana)
- **알림:** 자동화된 장애 알림 (AlertManager)

### 성능
- **메트릭 보존:** 30일 (Prometheus TSDB)
- **로그 보존:** 설정 가능 (Loki)
- **쿼리 성능:** < 1초 (인덱싱 최적화)

### 자동화
- **n8n 워크플로우:** 자동화된 운영 작업
- **알림 라우팅:** 조건별 알림 전송 (Slack, Email)
- **데이터 수집:** 자동 메트릭/로그 수집

### 보안
- **HTTPS:** Traefik + Cloudflare SSL
- **인증:** Basic Auth (n8n), Admin 패스워드 (Grafana)
- **네트워크 격리:** 별도 Docker 네트워크

## 통합 프로젝트

### 현재 모니터링 중인 서비스
1. **Grafana 자체** (grafana:3000)
2. **Prometheus** (prometheus:9090)
3. **Loki** (loki:3100)
4. **Node Exporter** (node-exporter:9100)
5. **cAdvisor** (cadvisor:8080)
6. **n8n** (n8n:5678)
7. **n8n PostgreSQL** (n8n-postgres-exporter:9187)
8. **n8n Redis** (n8n-redis-exporter:9121)
9. **Blacklist Service** (blacklist.jclee.me:2542)

### Prometheus Scrape 설정
- 간격: 15초
- 타임아웃: 10초
- 보존 기간: 30일

## Constitutional Compliance
✅ **CLAUDE.md v11.6 준수**
- Synology NAS 중앙 모니터링 (Constitutional Principle #1)
- 로컬 Grafana/Prometheus 금지 (Class 1 Violation 방지)
- 모든 프로젝트 통합 관측성 (Universal Observability)

## 관련 문서
- [Prometheus 설정](../configs/prometheus.yml)
- [Loki 설정](../configs/loki-config.yaml)
- [데모 가이드](../demo/README.md)
- [Grafana 대시보드](https://grafana.jclee.me)
