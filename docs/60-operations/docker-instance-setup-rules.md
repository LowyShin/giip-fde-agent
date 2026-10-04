# Docker 인스턴스 세팅 룰 (정본, 단일 파일)

> 새 docker 인스턴스를 만들 때 **반드시 지켜야 하는 모든 룰**을 이 한 파일에 모은다.
> 사람이든 AI 에이전트든 이 문서만 따르면 인스턴스가 규칙에 맞게 서고, 인스턴스 간 정보가
> 섞이지 않는다. 관련 코드: `docker/entrypoint.sh`, `docker/setup-registration.js`,
> `docker/Dockerfile`, `scripts/gissue/lib/ssot-csn.js`, `scripts/gissue/lib/ssot-sk.js`,
> `scripts/gissue/check-csn-consistency.sh`.
> 배포 동작 원리는 [`docker-deployment.md`](./docker-deployment.md) 참고.

## 0. 대전제 — giip-fde-agent 는 범용 프레임워크다

이 저장소는 **여러 인스턴스(CSN)가 공유하는 범용 코드**다. 특정 인스턴스(특정 CSN·프로젝트명·sk·
lssn·hostname)의 값을 **코드/문서/주석 어디에도 하드코딩하지 않는다.** 인스턴스별 값은 아래
"배포별 파일"에만 담고, 그 파일들은 git 에 커밋하지 않는다.

## 1. 핵심 룰 (반드시 준수)

### R1. 1 인스턴스 = 1 CSN, SSOT 는 한 곳
- 컨테이너 1개는 정확히 하나의 CSN 에 속한다.
- 그 CSN 의 **단일 진실 소스(SSOT)** 는 `scripts/gissue/csn-projects.json` 의 단일 최상위 `csn` 키다.
  이 파일의 `csn` 블록에는 키가 **정확히 1개**만 있어야 한다(0개/2개 이상이면 오류).
- 스케줄러 cron 의 `-OnlyCsn`, giip-agent/giip-cqe 등 다른 값은 모두 이 SSOT 에서 파생/검증된다.
- `GIIP_CSN` 환경변수는 **최초 기동 때 이 파일을 만드는 입력일 뿐** 정본이 아니다. 컨테이너 프로세스에
  박혀 클론+CSN 교체 후 stale 되므로, 재기동 시 항상 SSOT 기준으로 다시 맞춘다.

### R2. 인스턴스 격리 — 다른 인스턴스 값을 가져오지 않는다
- 새 인스턴스를 만들 때 **다른 인스턴스의 CSN·sk·lssn·hostname 을 복사해오지 않는다.**
- 배포별 파일(아래 R3)에 이 인스턴스 고유의 값만 넣는다. 다른 인스턴스의 식별자가 이 인스턴스의
  설정·로그·문서에 섞이면 안 된다.

### R3. 시크릿·인스턴스별 설정은 배포별 파일에만 (커밋 금지)
아래는 **인스턴스마다 값이 다르고 git 에 커밋하지 않는다**(`.gitignore` 대상). 저장소에는 `*.example`/
`*.sample` 템플릿만 둔다.

| 파일 | 담는 값 |
|------|---------|
| `scripts/gissue/csn-projects.json` | 이 인스턴스의 CSN(SSOT) → 프로젝트/워크디렉토리 매핑 |
| `slack-bot/.secrets/giip-accounts.json` | login_id / sk / csn (슬랙봇 사용 시) |
| `giipAgent.cnf` (giipAgentLinux 부모 폴더) | sk / lssn (giip-agent·giip-cqe 공용) |

`.env` 의 `GIIP_LOGIN_ID`/`GIIP_SK`/`GIIP_CSN` 등도 인스턴스별 값이며 커밋하지 않는다.

> **sk 의 정본은 한 곳:** `giipAgent.cnf` 의 `sk` 는 사람이 매번 맞추는 값이 아니라, entrypoint 가
> `slack-bot/.secrets/giip-accounts.json` 에서 **SSOT CSN 에 해당하는 계정의 sk** 를
> (`scripts/gissue/lib/ssot-sk.js` 로) 파생해 쓴다. `GIIP_SK` env 는 최초 부팅 seed 일 뿐이고(이걸로
> `giip-accounts.json` 이 만들어진다), 재기동마다 정본에서 다시 끌어오므로 clone+교체 후에도 어긋나지
> 않는다. CSN 과 마찬가지로 sk 도 코드/cron 에 박지 않는다.

## 2. 3종 스케줄 (한 CSN 으로 자동 등록)

컨테이너 안에서 아래 3종이 같은 CSN 으로 함께 돈다.

- **giip-agent** (`/etc/cron.d/giip-agent`) — 이 인스턴스를 살아있는 서버로 등록, 매분 상태 보고.
- **giip-cqe** (`/etc/cron.d/giip-cqe`) — 배분된 명령(CQE)을 주기적으로 실행. `giipAgent.cnf` 의 sk/lssn 공용.
- **gissue-scheduler** (`/etc/cron.d/gissue-scheduler`) — 이 CSN 의 이슈를 주기 처리. `-OnlyCsn` 은 SSOT 에서 파생.

giip-cqe 자체 CSN 등록 코드는 giip #3404 참고(giip-agent 의 `giipAgent3.sh` 자기등록에 얹혀 감).

## 3. 새 인스턴스 세팅 절차

### 방법 A — 새 컨테이너 (권장)
1. `.env` 에 이 인스턴스 값 입력: `GIIP_LOGIN_ID`, `GIIP_SK`, `GIIP_CSN`(이 인스턴스의 CSN).
2. `docker compose up -d --build`.
3. 기동 중 `setup-registration.js` 가 `csn-projects.json`(csn=GIIP_CSN)을 만들고, entrypoint 가 그
   SSOT 로 3종 cron 을 등록한다.
4. 아래 §4 정합성 점검.

### 방법 B — 기존 환경 복제 후 CSN 만 교체
1. `csn-projects.json` 의 csn 키를 **이 인스턴스의 새 CSN 하나로** 교체(project/workdir 도).
2. `slack-bot/.secrets/giip-accounts.json` 의 csn/sk 를 이 인스턴스 값으로 교체(= 이 CSN 의 sk 정본).
3. `giipAgent.cnf` 의 `sk` 는 **직접 고치지 않아도 된다** — 재기동 시 entrypoint 가 §R3 의 정본
   (giip-accounts.json, SSOT CSN)에서 파생해 다르면 자동 갱신한다. CSN 자체를 바꾼 경우에는 `lssn` 을
   `0` 으로 비워 새 CSN 아래 새로 발급받게 한다(옛 CSN 의 lssn 은 새 sk 로 쓰면 giipfaw 가 거부).
4. 컨테이너 재기동 → entrypoint 가 SSOT 기준으로 cron 재생성 + giipAgent.cnf sk 재파생(옛 `GIIP_CSN`
   env 가 남아 있으면 경고 후 SSOT 사용).
5. §4 정합성 점검.

## 4. 정합성 점검 (필수)

```bash
bash scripts/gissue/check-csn-consistency.sh            # 읽기 전용 점검
bash scripts/gissue/check-csn-consistency.sh --register # lssn 미등록 시 giipAgent3.sh 자기등록까지
```
점검: SSOT csn 1개 · `giipAgent.cnf` sk/lssn · **sk↔SSOT 정본 일치**(giip-accounts.json 의 SSOT CSN sk 와
`giipAgent.cnf` sk 대조 — 다른 CSN 의 sk 로 조용히 어긋났는지) · `GIIP_CSN`(env)↔SSOT ·
gissue-scheduler cron `-OnlyCsn`↔SSOT · 3종 cron 파일 존재. 전부 PASS 여야 한다.

## 5. entrypoint 자동 가드

- `-OnlyCsn` 을 `GIIP_CSN` 이 아니라 SSOT(csn-projects.json)에서 파생.
- `GIIP_CSN`(env)≠SSOT 이면 경고 후 SSOT 사용, cron 생성 뒤 `-OnlyCsn`↔SSOT 재검증, 부팅 후 자기점검.
- **giipAgent.cnf sk 재파생**: giip-agent 블록에서 sk 를 `giip-accounts.json`(SSOT CSN, `ssot-sk.js`)에서
  파생해 쓰고, 기존 cnf 의 sk 가 정본과 다르면 **그 줄만 SSOT 값으로 갱신**한다(lssn 등 보존, inode 유지).
  정본에서 못 구하면 `GIIP_SK` env 로 폴백.
- **엄격 모드**: `.env` 에 `GIIP_STRICT_CSN=true` 를 주면 CSN 불일치/SSOT 확정 실패, **또는 giipAgent.cnf
  sk↔SSOT 불일치** 시 **기동 자체를 실패**시킨다.

## 6. gh CLI (PR 자동화)

- `gh` 는 `docker/Dockerfile` 에서 이미지에 설치된다 — 컨테이너를 재생성해도 유지된다.
- 인증은 이미지에 포함되지 않으므로 인스턴스별로 수행한다: `GH_TOKEN` env(권장, 무인 자동화용) 또는
  `gh auth login`. 토큰/인증정보는 커밋하지 않는다.

## 7. 신규 인스턴스 셋업 체크리스트

- [ ] `.env`(또는 `csn-projects.json`)에 이 인스턴스의 CSN **하나만** 넣었다(다른 인스턴스 값 미혼입).
- [ ] `csn-projects.json` 의 csn 키가 정확히 1개다.
- [ ] `giipAgent.cnf` 에 이 인스턴스 sk 가 있고, lssn 이 발급됐다(또는 `--register` 로 발급).
- [ ] `bash scripts/gissue/check-csn-consistency.sh` 가 전 항목 PASS.
- [ ] `/etc/cron.d/` 에 giip-agent·giip-cqe·gissue-scheduler 3종이 있다.
- [ ] 시크릿/인스턴스별 파일은 커밋하지 않았다(gitignore 확인).
- [ ] (PR 자동화 필요 시) `gh` 인증 완료(`GH_TOKEN` 또는 `gh auth login`).

## 관련

- 유저 대면 가이드(giipv3): `/{locale}/guides/agent-csn-registration`
- 배포 동작 원리: [`docker-deployment.md`](./docker-deployment.md)
- 이슈: giip #3405(이 룰), giip #3404(giip-cqe 자체 CSN 등록 코드)
