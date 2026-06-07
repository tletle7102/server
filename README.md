# server

자가 호스팅 인프라 IaC 저장소 (jinhee_tutorial 학습용).

> **메인 가이드는 따로 있음**: 본인 PC의 `~/documents/cicd정리문서/오늘하루완성.md` — 도메인 구입 없이 nip.io로 오늘 안에 완성하는 단계별 절차 (3–4시간).

## 핵심 컨셉

- 도메인 0원 — nip.io 와일드카드 DNS 사용 (`<EIP>.nip.io`)
- DNS 등록·전파 대기 없음 (탄력적 IP만 정해지면 즉시 사용)
- Let's Encrypt 자동 발급으로 자물쇠 ✓

## 디렉토리

| 경로 | 용도 |
|---|---|
| `infra/docker-compose.yml` | 인프라 5종 통합 (Traefik+Jenkins+Postgres+landing+autoheal) |
| `infra/.env.example` | 환경변수 템플릿 |
| `infra/traefik/` | 리버스 프록시 + Let's Encrypt 설정 |
| `infra/jenkins/` | 커스텀 Jenkins 이미지 + JCasC (sampleapp 잡 자동 선언) |
| `infra/landing/` | apex 도메인 정적 페이지 |
| `scripts/` | cron 헬스체크 (cert-check, health-monitor, ssh-login-notify) |
| `logs/`, `data/` | 런타임 (gitignore) |

## EC2 배포 절차 요약

> 전체 단계는 `오늘하루완성.md` 참조. 여기는 명령어만.

### 1. clone

```bash
git clone https://github.com/tletle7102/server.git ~/server
cd ~/server
```

### 2. 호스트 사전 설정

```bash
sudo mkdir -p /mydata/postgres
sudo chown -R 999:999 /mydata/postgres
getent group docker | cut -d: -f3   # 결과 메모 (HOST_DOCKER_GID에 사용)
```

### 3. .env 작성

```bash
cp infra/.env.example infra/.env
chmod 600 infra/.env
vi infra/.env
```

필수 항목:
- `DOMAIN` — `<EC2_탄력적_IP>.nip.io` 형식 (예: `52.79.123.45.nip.io`)
- `HOST_DOCKER_GID` — 위 2단계 결과
- `POSTGRES_PASSWORD`, `JENKINS_ADMIN_PASSWORD`, `SAMPLEAPP_DB_PASSWORD` — `openssl rand -base64 24`로 생성
- `TRAEFIK_DASHBOARD_AUTH` — `htpasswd -nbB admin '비번' | sed -e 's/\$/\$\$/g'`
- `DISCORD_WEBHOOK_*` — Discord 채널 5개 webhook URL (디스코드 서버에서 발급)

### 4. 첫 기동

```bash
docker volume create jenkins_home
cd infra && docker compose up -d --build
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Jenkins healthy 도달까지 약 3분.

### 5. sampleapp DB + cron

```bash
docker exec postgres psql -U dbuser -d postgres \
  -c "CREATE DATABASE sampleapp WITH OWNER dbuser ENCODING 'UTF8';"

( crontab -l 2>/dev/null;
  echo "0 9 * * * cd \$HOME/server && bash scripts/cert-check.sh >/dev/null 2>&1";
  echo "*/5 * * * * cd \$HOME/server && bash scripts/health-monitor.sh >/dev/null 2>&1" ) | crontab -

mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > ~/.ssh/rc <<'EOF'
#!/bin/bash
[ -x $HOME/server/scripts/ssh-login-notify.sh ] && \
  $HOME/server/scripts/ssh-login-notify.sh >/dev/null 2>&1 &
EOF
chmod 700 ~/.ssh/rc
```

### 6. 검증 (본인 PC에서)

`<EIP>`는 본인 탄력적 IP:

- `https://<EIP>.nip.io` — 랜딩
- `https://jenkins.<EIP>.nip.io` — Jenkins (admin/JENKINS_ADMIN_PASSWORD)
- `https://traefik.<EIP>.nip.io` — Traefik 대시보드 (admin/위 비번)

모두 자물쇠 ✓ 확인.

## 페어 레포

- [tletle7102/sampleapp](https://github.com/tletle7102/sampleapp) — CI/CD 테스트용 더미 Spring Boot 앱. GitHub webhook 등록 후 push 시 자동 배포.

## 트러블슈팅

`오늘하루완성.md` 단계 12 참조.
