# Docker 배포

새 환경에서 giip-fde-agent를 auto clone + csn/sk/login_id 등록 + slack-bot/scheduler 기동까지
한 번에 세팅합니다. 전체 설명·검증 상태·알려진 한계는
[`docs/60-operations/docker-deployment.md`](../docs/60-operations/docker-deployment.md)가 정본입니다.

## Quick start

```bash
cp .env.example .env   # GIIP_LOGIN_ID / GIIP_SK / GIIP_CSN 등 실값 채움
docker compose up -d --build
docker compose logs -f
```

## 파일 구성

| 파일 | 역할 |
|---|---|
| `Dockerfile` | pwsh 7 + Node.js + git + claude CLI + pm2 런타임 |
| `entrypoint.sh` | clone/pull → 등록 스크립트 실행 → slack-bot(pm2) + scheduler(cron) 기동 |
| `setup-registration.js` | env var → `csn-projects.json` / `giip-accounts.json` 생성 (이미 있으면 건드리지 않음) |
| `docker-compose.yml` | 볼륨 영속화 포함 기동 정의 |
| `.env.example` | env var 계약(정본) |
