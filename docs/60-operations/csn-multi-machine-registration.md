# 여러 머신에 CSN별로 giip 스케줄 일괄 등록하기 (AI용 정본 가이드)

> 정본 문서 · giip #3405 · 대상: `giip-fde-agent` + `giipAgentLinux` 를 여러 머신(CSN)에 클론해
> 운영하는 사람/AI 에이전트

이 문서는 giip 환경(giip-fde-agent + giipAgentLinux 모니터링 세트)을 **새 머신에 클론**할 때,
그 머신의 CSN 하나만 정하면 **giip-agent / giip-cqe / gissue-scheduler 3개 스케줄이 전부 그 CSN 으로
정합성 있게** 등록되도록 하는 절차다. AI 에이전트가 그대로 따라 실행해도 안전하게 끝나도록 썼다.

## 배경 — 왜 이 문서가 필요한가 (caci-skp 인시던트, 2026-09-30)

"환경을 클론하고 CSN 만 바꾼다"는 운영 방식에서, CSN 이 **두 경로로 나뉘어** 들어가는 게 문제였다.

- `docker/entrypoint.sh` 는 컨테이너 프로세스의 `GIIP_CSN` 환경변수를 그대로 `-OnlyCsn` 인자로 박아
  `/etc/cron.d/gissue-scheduler` 를 만든다.
- 그런데 `GIIP_CSN` 은 **컨테이너 최초 기동 시점에 프로세스에 박히는 값**이라, 나중에
  `csn-projects.json`(매핑)과 `giipAgent.cnf`(sk/lssn)만 새 CSN 으로 수동 편집해도 바뀌지 않는다.

caci-skp(CSN 70434) 머신은 처음에 `GIIP_CSN=47`(giipprj)로 떴다가 매핑만 70434 로 고쳐져,
**cron 은 47 인데 매핑은 70434** 인 상태로 조용히 돌고 있었다.

## 단일 진실 소스(SSOT) — CSN 은 여기 한 곳에만

> **이 머신의 CSN = `scripts/gissue/csn-projects.json` 의 단일 최상위 `csn` 키.**

이 docker 배포 모델은 **"컨테이너 1개 = 프로젝트(CSN) 1개"** 다. 그래서 이 파일의 `csn` 블록에는
키가 **정확히 1개**만 있어야 한다.

- 이 파일은 `/work`(영속 볼륨) 밑에 있어 재기동해도 유지되고, 스케줄러(`run-gissue-claude.ps1`)가
  이미 CSN→workdir 정본 매핑으로 사용한다.
- `GIIP_CSN` 환경변수는 **최초 기동 때 이 파일을 만드는 입력**일 뿐이다. 한 번 파일이 생기면
  `docker/setup-registration.js` 는 이 파일을 다시 건드리지 않는다(idempotent).
- `giipAgent.cnf` 에는 CSN 리터럴이 없다. sk/lssn 만 있고, CSN 은 서버가 sk 로 판정한다.
  giip-cqe(`giipCQE.sh`)도 같은 `../giipAgent.cnf` 를 읽으므로 giip-agent 와 같은 CSN 에 얹혀 간다.

### CSN 이 흘러가는 경로

```
csn-projects.json 의 csn 키  ─(SSOT)─►  entrypoint.sh 가 읽어 -OnlyCsn 파생  ─►  gissue-scheduler cron
GIIP_SK (giipAgent.cnf)      ──────────►  giipAgent3.sh 자기등록(lssn 발급)   ─►  giip-agent cron
                                          └► 같은 sk/lssn 사용                 ─►  giip-cqe cron (giipCQE.sh)
```

`GIIP_CSN` 환경변수는 "입력"일 뿐 "정본"이 아니다 — 클론 후에는 SSOT(csn-projects.json)만 맞으면 된다.

## 새 머신 복제 절차 (사람/AI 공통)

### 방법 A — 처음부터 새 컨테이너로 띄우는 경우(권장)

1. `.env` 에 이 머신의 값을 넣는다: `GIIP_LOGIN_ID` / `GIIP_SK` / `GIIP_CSN`(= 이 머신의 CSN).
2. `docker compose up -d --build`.
3. entrypoint 가 `setup-registration.js` 로 `csn-projects.json`(csn 키 = `GIIP_CSN`)을 만들고,
   그 SSOT 에서 `-OnlyCsn` 을 파생해 3개 cron 을 등록한다.
4. 아래 [정합성 점검](#정합성-점검) 으로 확인한다.

### 방법 B — 기존 컨테이너를 클론해 CSN 만 바꾸는 경우

1. `scripts/gissue/csn-projects.json` 의 `csn` 키를 **새 CSN 하나로** 교체한다(SSOT 갱신).
   - `project` / `workdir` 도 새 머신에 맞게 바꾼다.
2. `giipAgent.cnf` 의 `sk` 를 새 머신(새 CSN)의 sk 로 바꾸고, `lssn` 은 `0` 으로 비운다
   (새 CSN 아래 새 lssn 을 다시 발급받기 위해).
3. `slack-bot/.secrets/giip-accounts.json` 의 csn/sk 도 새 값으로 맞춘다(슬랙봇을 쓰는 경우).
4. **컨테이너를 재기동**한다(`docker compose restart` 또는 `up -d`).
   - 재기동 시 entrypoint 가 SSOT(csn-projects.json)에서 `-OnlyCsn` 을 다시 파생하므로, 옛
     `GIIP_CSN` 환경변수가 남아 있어도 cron 은 새 CSN 으로 재생성된다(경고 로그가 함께 뜬다).
   - env 자체도 깔끔히 맞추려면 `.env` 의 `GIIP_CSN` 도 새 값으로 바꾸고 `up -d --force-recreate`.
5. lssn 자기등록이 필요하면(방법 B-2 로 비웠으면) 아래 `--register` 로 실행하거나 재기동으로
   entrypoint 가 `giipAgent.cnf` 를 다시 만들게 한다.
6. [정합성 점검](#정합성-점검) 으로 확인한다.

## 정합성 점검

새 머신에서 아래 한 줄로 giip-agent / giip-cqe / gissue-scheduler 3개가 같은 CSN 으로 정합한지 점검한다.

```bash
bash scripts/gissue/check-csn-consistency.sh            # 읽기 전용 점검
bash scripts/gissue/check-csn-consistency.sh --register # lssn 미등록이면 giipAgent3.sh 1회 자기등록까지
```

점검 항목:

1. **SSOT** — `csn-projects.json` 에 csn 키가 정확히 1개 있는가.
2. **giipAgent.cnf** — `sk` 가 있고 `lssn` 이 등록(양의 정수)됐는가. 미등록이면 `--register` 로
   `giipAgent3.sh` 를 1회 실행해 자기등록.
3. **GIIP_CSN(env) ↔ SSOT** — 둘이 같은가(다르면 클론 후 stale env — SSOT 가 정본).
4. **gissue-scheduler cron `-OnlyCsn` ↔ SSOT** — 같은가(이번 caci-skp 인시던트가 잡히는 지점).
5. **cron 파일 존재** — `/etc/cron.d/` 에 `giip-agent` / `giip-cqe` / `gissue-scheduler` 3개가 있는가.

`[FAIL]` 이 하나라도 있으면 종료코드 1. 모두 통과면 0.

## entrypoint 자동 가드 (요구사항 2)

`docker/entrypoint.sh` 는 기동/재기동 때마다 스스로 아래를 수행한다.

- **`-OnlyCsn` 을 SSOT 에서 파생**: `GIIP_CSN` 환경변수가 아니라 `csn-projects.json` 의 csn 키를 읽어
  cron 을 만든다(파일이 아직 없는 최초 기동에서만 `GIIP_CSN` 으로 폴백).
- **불일치 경고**: `GIIP_CSN`(env)과 SSOT 가 다르면 경고 로그를 남기고 **SSOT 값을 쓴다**.
- **cron 재검증**: 방금 쓴 cron 의 `-OnlyCsn` 이 SSOT 와 일치하는지 다시 확인한다.
- **부팅 후 자기점검**: 3개 cron 등록이 끝나면 `check-csn-consistency.sh` 를 한 번 돌려 로그에 남긴다.

### 엄격 모드 — `GIIP_STRICT_CSN=true`

기본값은 "경고만 남기고 계속 기동"이다. `.env` 에 `GIIP_STRICT_CSN=true` 를 주면 CSN 불일치나 SSOT
확정 실패 시 **컨테이너 기동 자체를 실패**시킨다(운영에서 "조용히 어긋난 채 도는 것"을 원천 차단하고
싶을 때).

## giip-cqe 자체 CSN 등록 (giip 3404 연계, 요구사항 3)

giip-cqe(`giipAgentLinux/cqe/giipCQE.sh`)는 자기 자신을 `tSchedulerAgent` 에 등록하는 코드가 없어,
giip-agent 의 서버 등록(`giipAgent3.sh` → lssn 발급)에 얹혀 간다. 별도 코드 수정은 **giip 3404** 에서
다룬다. 이 가이드에서는 다음만 확인하면 된다.

- `giipAgent.cnf` 에 `sk` 가 있고 `lssn` 이 등록돼 있으면(위 점검 [2]), giipCQE.sh 도 같은 sk/lssn 으로
  동작하므로 별도 CSN 입력이 필요 없다.
- giip 3404 가 반영되면 giip-cqe 도 giip-agent 와 동일한 자기등록 패턴을 따르게 되므로, 이 가이드의
  절차/점검 항목은 그대로 유효하다(추가 단계 불필요).

## 트러블슈팅

| 증상 | 원인 | 조치 |
|---|---|---|
| 점검 [4] FAIL: cron `-OnlyCsn` ≠ SSOT | 클론 후 옛 env 로 만들어진 stale cron | 컨테이너 재기동 → entrypoint 가 SSOT 로 재생성 |
| 점검 [3] FAIL: `GIIP_CSN`(env) ≠ SSOT | `.env` 의 `GIIP_CSN` 이 옛 값 | `.env` 를 새 CSN 으로 바꾸고 `up -d --force-recreate` |
| 점검 [1] FAIL: csn 키 0개 또는 2개 이상 | csn-projects.json 이 없거나 다중 CSN | csn 키를 새 CSN **하나**로 정리 |
| 점검 [2] WARN: lssn 미등록 | 새 CSN 으로 아직 자기등록 안 됨 | `check-csn-consistency.sh --register` 또는 `cd /work/giipAgentLinux && bash giipAgent3.sh` |

## 관련

- 이슈: giip #3405(이 문서), giip #3404(giip-cqe 자체 CSN 등록 코드)
- 코드: `docker/entrypoint.sh`, `docker/setup-registration.js`,
  `scripts/gissue/lib/ssot-csn.js`, `scripts/gissue/check-csn-consistency.sh`
- 도커 배포 정본: `docs/60-operations/docker-deployment.md`
