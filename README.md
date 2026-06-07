# server

자가 호스팅 인프라 IaC 저장소 (jinhee_tutorial.md 실습용).

도메인 placeholder는 `mytest.example`. 실 도메인 정해지면 `infra/.env`의 `DOMAIN=` 한 줄만 교체.

## 디렉토리

- `infra/` : 인프라 컨테이너 정의 (Traefik, Jenkins, Postgres, landing, autoheal)
- `infra/.env.example` : 환경변수 템플릿 (실제 `.env`는 gitignore)
- `scripts/` : cron 헬스체크 스크립트 (cert-check, health-monitor, ssh-login-notify)
- `logs/` : 실행 로그 (gitignore)
- `data/` : 영속 데이터 (gitignore)

## EC2 배포 절차

> 사전 조건: 튜토리얼 Part 2–4 완료 (EC2 인스턴스 + 탄력적 IP + Docker 설치 + 도메인 + DNS 와일드카드 A 레코드).

### 0. clone

```bash
git clone https://github.com/tletle7102/server.git ~/server
cd ~/server
```

### 1. 호스트 사전 설정 (튜토리얼 Part 3.6, 7.1)

```bash
# postgres 데이터 디렉토리 생성 + UID 999 부여
sudo mkdir -p /mydata/postgres
sudo chown -R 999:999 /mydata/postgres

# 호스트 docker 그룹 GID 확인 (.env의 HOST_DOCKER_GID에 기입)
getent group docker | cut -d: -f3
```

### 2. .env 작성 (튜토리얼 Part 12.3, 14)

```bash
cp infra/.env.example infra/.env
chmod 600 infra/.env
vi infra/.env
```

채울 항목:
- `DOMAIN` — 실 도메인 (예: yourdomain.com)
- `HOST_DOCKER_GID` — 위 1번에서 확인한 숫자
- `POSTGRES_PASSWORD`, `JENKINS_ADMIN_PASSWORD`, `SAMPLEAPP_DB_PASSWORD` — `openssl rand -base64 24`로 생성
- `JENKINS_ADMIN_EMAIL` — `tletle7102@gmail.com`
- `TRAEFIK_DASHBOARD_AUTH` — `sudo apt-get install -y apache2-utils && htpasswd -nbB admin '비번' | sed -e 's/\$/\$\$/g'`
- `DISCORD_WEBHOOK_*` — 5개 채널 webhook URL (Part 14)

### 3. 첫 기동 + 검증 (튜토리얼 Part 13)

```bash
docker volume create jenkins_home
cd infra
docker compose up -d --build   # Jenkins 이미지 빌드 5–10분
docker ps --format "table {{.Names}}\t{{.Status}}"
```

모든 컨테이너 `healthy` 도달까지 약 3분. 브라우저:
- `https://mytest.example` → 랜딩 페이지
- `https://jenkins.mytest.example` → Jenkins 로그인 (admin / JENKINS_ADMIN_PASSWORD)
- `https://traefik.mytest.example` → BasicAuth 프롬프트

### 4. sampleapp DB 생성 + cron 등록 (튜토리얼 Part 13.4, 15.3)

```bash
# sampleapp용 DB 생성
docker exec postgres psql -U dbuser -d postgres \
  -c "CREATE DATABASE sampleapp WITH OWNER dbuser ENCODING 'UTF8';"

# cron 등록 (매일 09:00 cert-check, 5분마다 health-monitor)
( crontab -l 2>/dev/null;
  echo "0 9 * * * cd $HOME/server && bash scripts/cert-check.sh >/dev/null 2>&1";
  echo "*/5 * * * * cd $HOME/server && bash scripts/health-monitor.sh >/dev/null 2>&1" ) | crontab -

# SSH 로그인 알림 (Part 17.1)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > ~/.ssh/rc <<'EOF'
#!/bin/bash
[ -x $HOME/server/scripts/ssh-login-notify.sh ] && \
  $HOME/server/scripts/ssh-login-notify.sh >/dev/null 2>&1 &
EOF
chmod 700 ~/.ssh/rc
```

### 5. sampleapp 배포 (튜토리얼 Part 18)

별도 레포 [tletle7102/sampleapp](https://github.com/tletle7102/sampleapp)이 GitHub webhook 등록 후 push 시 자동 배포됨.

## 트러블슈팅

튜토리얼 Part 20에 7대 사고 사례와 진단법 정리되어 있음.
