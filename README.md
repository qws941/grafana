# Grafana Monitoring Stack

완전한 모니터링 스택을 위한 Docker Compose 설정입니다.

## 🏗️ 아키텍처

```
grafana/
├── compose/
│   ├── docker-compose.yml    # 메인 컴포즈 파일
│   └── .env                  # 환경변수 설정
├── configs/
│   ├── provisioning/         # Grafana 프로비저닝 설정
│   ├── prometheus.yml        # Prometheus 설정
│   └── promtail-config.yml   # Promtail 설정
├── scripts/
│   └── create-volume-structure.sh  # 볼륨 구조 생성 스크립트
└── README.md
```

## 📁 볼륨 구조

기본 경로: `/volume1/docker/grafana`

```
/volume1/docker/grafana/
├── grafana/         # Grafana 데이터 (uid:472, gid:472)
├── prometheus/      # Prometheus 데이터 (uid:65534, gid:65534)
├── loki/           # Loki 데이터 (uid:10001, gid:10001)
└── alertmanager/   # Alertmanager 데이터 (uid:65534, gid:65534)
```

## 🚀 빠른 시작

### 1. 볼륨 구조 생성

```bash
# 기본 경로 사용
./scripts/create-volume-structure.sh

# 커스텀 경로 사용
GRAFANA_PATH=/your/custom/path ./scripts/create-volume-structure.sh
```

### 2. 환경변수 설정

`compose/.env` 파일에서 필요한 설정을 수정하세요:

```bash
# 기본 경로 변경
GRAFANA_PATH=/your/custom/path

# 도메인 설정
GRAFANA_DOMAIN=your-grafana.domain.com
LOKI_DOMAIN=your-loki.domain.com
PROMETHEUS_DOMAIN=your-prometheus.domain.com
ALERTMANAGER_DOMAIN=your-alertmanager.domain.com

# 비밀번호 설정
GRAFANA_ADMIN_PASSWORD=your-secure-password
```

### 3. 스택 배포

```bash
cd compose
docker-compose up -d
```

## 🔧 주요 특징

- **NFS 의존성 없음**: 로컬 바인드 마운트 사용
- **GRAFANA_PATH 기반**: 모든 볼륨이 하나의 기본 경로에서 확장
- **환경변수 중심**: 유연한 설정 관리
- **Traefik 통합**: SSL 터미네이션 지원
- **헬스체크**: 모든 서비스 상태 모니터링
- **Portainer 호환**: GitHub 스택으로 직접 배포 가능

## 📊 서비스 구성

| 서비스 | 포트 | 도메인 | 설명 |
|--------|------|--------|------|
| Grafana | 3000 | grafana.jclee.me | 메인 대시보드 |
| Prometheus | 9090 | prometheus.jclee.me | 메트릭 수집 |
| Loki | 3100 | loki.jclee.me | 로그 수집 |
| Alertmanager | 9093 | alertmanager.jclee.me | 알림 관리 |
| Promtail | - | - | 로그 포워더 |
| Node Exporter | 9100 | - | 시스템 메트릭 |
| cAdvisor | 8080 | - | 컨테이너 메트릭 |

## 🔐 보안 고려사항

- 각 서비스별 적절한 사용자 권한 설정
- Traefik을 통한 SSL 인증서 자동 관리
- 외부 네트워크와 내부 모니터링 네트워크 분리

## 🛠️ 커스터마이징

### 볼륨 경로 변경

`.env` 파일에서 `GRAFANA_PATH`를 수정하고 볼륨 구조를 다시 생성:

```bash
GRAFANA_PATH=/new/path ./scripts/create-volume-structure.sh
```

### 서비스 버전 변경

`.env` 파일에서 원하는 버전으로 수정:

```bash
GRAFANA_VERSION=9.5.0
PROMETHEUS_VERSION=v2.45.0
LOKI_VERSION=2.8.0
```

## 📝 문제 해결

### 권한 문제
```bash
# 볼륨 구조 스크립트 재실행
sudo ./scripts/create-volume-structure.sh
```

### 설정 검증
```bash
cd compose
docker-compose config
```

### 로그 확인
```bash
docker-compose logs -f [service-name]
```

## 🔄 업그레이드

```bash
cd compose
docker-compose pull
docker-compose up -d
```

## 📞 지원

문제가 발생하면 다음을 확인하세요:
1. 볼륨 디렉토리 권한
2. 네트워크 설정
3. 환경변수 설정
4. Docker Compose 구문