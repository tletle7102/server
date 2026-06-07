# server

자가 호스팅 인프라 IaC 저장소 (jinhee_tutorial.md 실습용).

## 디렉토리

- `infra/` : 인프라 컨테이너 정의 (Traefik, Jenkins, Postgres, landing, autoheal)
- `scripts/` : cron 헬스체크 스크립트
- `logs/` : 실행 로그 (gitignore)
- `data/` : 영속 데이터 (gitignore)

## EC2에서 배포 절차

```bash
git clone https://github.com/tletle7102/server.git ~/server
cd ~/server/infra
cp .env.example .env
# .env 편집해서 실제 값 채우기
docker compose up -d --build
```

## 도메인 placeholder

`mytest.example` 로 표기. 실제 도메인으로 교체는 `.env`의 `DOMAIN=` 한 줄만 바꾸면 됨.
