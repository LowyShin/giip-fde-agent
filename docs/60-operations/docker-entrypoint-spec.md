# docker/entrypoint.sh 사양서

> **기준**: `main` @ `cb25db5`(2026-10-06) + 부트스트랩 변경(단계 11) + giip #2855(2026-11-04: phantom 디렉터리·clone 잔해·fetch 실패·기동 요약). 코드: [`docker/entrypoint.sh`](../../docker/entrypoint.sh).
> **작성 방식**: 이 스크립트의 사양서는 따로 없었다(최초 커밋 `592ec89` 때부터 코드와 `docker-deployment.md` 가 함께 자라왔다).
> 이 문서는 **현재 코드를 읽고 역설계한 사양**이다. 코드가 바뀌면 이 문서도 같이 고친다. 코드와 어긋나면 **코드가 정본**이다.
> **관련 문서**: 세팅 룰 [`docker-instance-setup-rules.md`](./docker-instance-setup-rules.md), 배포 설명 [`docker-deployment.md`](./docker-deployment.md), 파일 표 [`docker/README.md`](../../docker/README.md).

## 1. 목적과 범위

컨테이너가 기동될 때 **한 번 실행되어 giip-fde-agent 인스턴스를 작동 상태로 만들고, 끝나면 로그를 tail 하며 컨테이너를 유지**한다.
하는 일: 저장소 동기화, 환경 주입, CSN/SK 등록 파일 생성, slack-bot 기동, 이슈 스케줄러·giipAgentLinux·CQE 의 cron 등록, 정합성 점검.

범위 밖: 이미지 빌드(`docker/Dockerfile`), 인스턴스 생성 화면(giipv3), 스케줄러 본체(`scripts/gissue/run-gissue-claude.ps1`).

## 2. 실행 환경

| 항목 | 값 | 근거 |
|---|---|---|
| 베이스 이미지 | `mcr.microsoft.com/powershell:7.4-debian-12` (pwsh, git, curl, cron, Node 20, claude CLI, pm2, gh, SqlServer 모듈, `powershell`→`pwsh` 링크) | `docker/Dockerfile` |
| 실행 사용자 | entrypoint 는 **root**(Dockerfile 에 `USER` 없음). **이슈 스케줄러 cron 만 `dev`**(`GIIP_SCHEDULER_USER`)로 돈다. giip-agent/giip-cqe cron 은 root | `docker/Dockerfile`, 아래 cron 줄 |
| 진입점 | `ENTRYPOINT ["/entrypoint.sh"]` — **이미지에 `COPY` 로 구워진 사본**을 실행한다 | `Dockerfile` 35~40행 |
| 쉘 옵션 | `set -euo pipefail` — 가드 없이 실패하는 명령은 기동을 중단시킨다(§5 표의 "실패 시") | 5행 |
| 영속 볼륨 | `/work` 전체(`giip-fde-agent-data`). 재기동해도 clone, 생성 파일, lssn 이 유지된다 | `docker-compose.yml` |
| 주입 env | `docker-compose.yml` 의 `env_file`(`${GIIP_ENV_FILE:-.env}`) | `docker-compose.yml` |

> ⚠️ **repo 의 `docker/entrypoint.sh` 를 고쳐도 기존 컨테이너에는 반영되지 않는다.** 이미지에 구워진 `/entrypoint.sh` 가 실행되므로 **이미지를 재빌드한 새 컨테이너**부터 적용된다.
> 이미지에 구워지는 것은 `entrypoint.sh`, `fetch-instance-env.sh`, `setup-registration.js` 세 파일이다. 반대로 entrypoint 가 호출하는 repo 안 스크립트(`scripts/gissue/*`, `scripts/fix-root-owned.sh` 등)는 기동 때 `git pull` 된 최신이 쓰인다.
> cron 의 실행 명령은 **기동 시점의 baked entrypoint 가 생성**하므로, cron 명령을 바꾸려면 이미지 재빌드가 필요하다.

## 3. 입력 — 환경변수

로컬에 이미 설정된 값이 항상 이긴다(§5 단계 2 의 fetch 는 비어 있는 키만 채운다).

| 변수 | 기본값 | 역할 | 쓰이는 단계 |
|---|---|---|---|
| `REPO_DIR` / `REPO_URL` / `REPO_BRANCH` | `/work/giip-fde-agent` / 공식 GitHub URL / `main` | 이 저장소의 clone 위치·출처 | 1 |
| `GIIP_INSTANCE_TOKEN` / `GIIP_INSTANCE_API_BASE` | 없음 / `https://giipfaw.azurewebsites.net/api` | 있으면 GIIP 웹의 `dockerInstanceFetch` 로 나머지 env 를 받아온다 | 2 |
| `GIIP_PROJECT_REPO_URL` / `_BRANCH` / `GIIP_WORKDIR` | 없음 / `main` / 레포명 기반 `/work/<repo>` | 스케줄러가 일할 대상 프로젝트 저장소를 clone(giip #2949) | 3 |
| `GIIP_CSN`, `GIIP_SK`, `GIIP_LOGIN_ID`, `GIIP_PROJECT_NAME`, `GIIP_REST_BRANCH`, `GIIP_API_BASE`, `SLACK_CHANNEL_ID`, `GIIP_FORCE_REGEN` | — | **최초 기동 seed**: `csn-projects.json`, `giip-accounts.json` 생성 입력. 이후 정본은 그 파일들 | 4 |
| `GIIP_SCHEDULER_HOSTNAME` | `<GIIP_PROJECT_NAME>-gissue-scheduler` | 스케줄러 자신의 heartbeat lssn 을 `AgentAutoRegister` 로 받을 때의 호스트명 | 4 |
| `GIIP_STRICT_CSN` | `false` | `true` 면 CSN/SK 정합성 위반 시 기동 중단(§6) | 5, 7, 8 |
| `GIIP_STRICT_FETCH` | `false` | `true` 면 `GIIP_INSTANCE_TOKEN` fetch 실패 시 기동 중단. `false` 면 경고만 남기고 계속(요약 블록 `fetch=failed` 로 재알림). giip #2855 | 2 |
| `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | 없음 | 둘 다 있을 때만 slack-bot 기동 | 6 |
| `GIIP_ENABLE_SCHEDULER` | `true` | `false` 면 이슈 스케줄러 cron 생략 | 7 |
| `GIIP_SCHEDULER_USER` | `dev` | 이슈 스케줄러 cron 을 돌릴 일반 사용자. 없으면 `useradd -m` 로 만들고, 만들 수 없으면 root 로 폴백하며 경고(이 경우 이슈가 처리되지 않음) | 7 |
| `GIIP_ENABLE_AGENT` | `true` | `false` 면 giipAgentLinux/CQE 생략 | 8 |
| `GIIP_AGENT_DIR` / `GIIP_AGENT_URL` | `/work/giipAgentLinux` / 공식 giipAgentLinux URL | giipAgentLinux clone 위치·출처 | 8 |
| `GIIP_DB_SERVER` / `_NAME` / `_LOGIN` / `_PASSWORD` | 없음 / `giipdb` | (선택) DB 직접 접속 정보. 단계 11 이 `giipdb/mgmt/dbconfig.json`(0600)을 만든다 | 11 |
| `GIIP_HUB_URL` / `GIIP_HUB_DIR` / `GIIP_SECRETS_DIR` | 공식 `giipprj-hub` URL / `/work/giipprj-hub` / `/work/.secrets` | 허브 저장소 위치와 비밀값 사본 보관 위치 | 11 |
| `GIIP_LSSN` | `0` | 양의 정수면 `giipAgent.cnf` 의 lssn 사전 배정(giip 2857). 아니면 0(첫 실행 시 자동 발급) | 8 |

## 4. 출력 — 만들어지는 것

| 종류 | 경로 | 만드는 단계 | 재기동 시 |
|---|---|---|---|
| CSN 매핑 SSOT | `scripts/gissue/csn-projects.json` | 4 | **있으면 유지**(`GIIP_FORCE_REGEN=true` 일 때만 재생성) |
| 계정 매핑 | `slack-bot/.secrets/giip-accounts.json` | 4 | 있으면 유지 |
| 스케줄러 heartbeat SK | `slack-bot/.secrets/gissue-heartbeat.cfg`(0600) + `csn-projects.json` 의 `heartbeat` 블록 | 4 | heartbeat.lssn 이 있으면 건너뜀 |
| giipAgent 설정 | `/work/giipAgent.cnf` (`giipAgent.cnf` 는 `GIIP_AGENT_DIR` 의 부모) | 8 | 있으면 **sk 줄만** SSOT 값으로 교체, lssn 등은 보존 |
| cron | `/etc/cron.d/gissue-scheduler`, `giip-agent`, `giip-cqe` | 7, 8 | **매 기동 때 덮어쓰기**(컨테이너 레이어라 재생성됨) |
| 프로세스 | pm2 `giipclaude-bot`, cron 데몬, 최종적으로 PID 1 = `tail -F` | 6, 9, 12 | — |
| 로그 | `scripts/gissue/logs/cron.log`(항상), `$GIIP_AGENT_DIR/log/cron.log`(**에이전트 블록이 실제로 돈 경우에만**, giip #2855), `/tmp/giip_cqe_logs/cqe_cron.log`, pm2 로그 | 7, 8, 12 | 누적 |

## 5. 단계별 동작과 실패 처리

| # | 단계 | 동작 | 실패 시 |
|---|---|---|---|
| 1 | 저장소 동기화 | `.git` 있으면 `fetch → checkout $REPO_BRANCH → merge --ff-only`, 없으면 `clone`. 짧은 커밋 해시를 로그 | **치명**(`set -e`): 네트워크 불가, 로컬 커밋으로 ff 불가 시 컨테이너가 종료되고 `restart: unless-stopped` 로 재시작 반복 |
| 2 | 인스턴스 env 주입 | stdout 만 캡처해 종료코드를 명시 검사(`if FETCH_ENV="$(/fetch-instance-env.sh)"; then … FETCH_RC`). 성공 시에만 `eval "$FETCH_ENV"`. `GIIP_INSTANCE_TOKEN` 이 없으면 fetch 가 exit 0 + 빈 출력이라 `fetch=unused`. 있고 성공이면 **비어 있는 키만** `export`(`fetch=ok`) | **경고 후 계속**(giip #2855): fetch 가 exit 1(curl 실패 / `RstVal!=200`)이면 `set -e` 로 죽지 않던 과거와 달리, 이제 종료코드를 검사해 `[entrypoint] WARN …` 을 남기고 요약 블록에 `fetch=failed (exit N)` 로 재알린다. `GIIP_STRICT_FETCH=true` 면 여기서 **중단**(exit 1) |
| 3 | 프로젝트 저장소 | `GIIP_PROJECT_REPO_URL` 이 있으면 `PROJECT_DIR`(=`GIIP_WORKDIR` 또는 `/work/<repo>`)에 pull/clone. 기본 경로면 `GIIP_WORKDIR` 를 export | **경고만**: 컨테이너는 계속 |
| 4 | 등록 파일 생성 | `node /setup-registration.js`. 위 §4 의 `csn-projects.json`, `giip-accounts.json`, heartbeat 블록 생성(없을 때만). `logs/` 디렉터리 생성 | 스크립트 오류는 **치명**. 단 heartbeat 등록 실패는 스크립트 안에서 삼키고 다음 기동 때 재시도 |
| 5 | SSOT CSN 결정 | `lib/ssot-csn.js` 로 `csn-projects.json` 의 **단일 csn 키** 확정 → `EFFECTIVE_CSN`. 확정 못 하면 `GIIP_CSN` 폴백. `GIIP_CSN` 과 SSOT 가 다르면 경고 | 경고. `GIIP_STRICT_CSN=true` 면 **중단** |
| 6 | slack-bot | 토큰 2개가 모두 있을 때만 `npm install --omit=dev` 후 `pm2 start index.js --name giipclaude-bot` | `npm`/`pm2` 실패는 **치명** |
| 7 | 이슈 스케줄러 cron | `GIIP_ENABLE_SCHEDULER=true` 일 때 `/etc/cron.d/gissue-scheduler` 작성: `7,27,47 * * * * <SCHED_USER> cd $REPO_DIR && <CRON_CMD>`(기본 `dev`, 아래 §5.1).  `-OnlyCsn <EFFECTIVE_CSN>`. 작성 후 cron 줄의 `-OnlyCsn` 이 SSOT 와 같은지 재확인 | 불일치는 경고, `STRICT` 면 중단 |
| 8 | giipAgentLinux + CQE | `GIIP_ENABLE_AGENT=true` 이고 SK 가 있을 때만. ① SK 결정: `lib/ssot-sk.js`(giip-accounts.json, EFFECTIVE_CSN)가 우선, 실패 시 `GIIP_SK` 폴백 ② giipAgentLinux 를 `main` 으로 pull/clone — **`.git` 이 없는데 디렉터리가 비어있지 않으면(이전 기동의 phantom 잔해 등) `${GIIP_AGENT_DIR}.bak-<타임스탬프>` 로 退避(rename) 후 clone**(giip #2855 T2: 조용히 삭제하지 않고, 무엇을 왜 했는지 로그) ③ agent log 디렉터리(`$GIIP_AGENT_DIR/log`)는 **이 블록 안에서만** 생성하고 그 cron.log 경로를 `AGENT_CRON_LOG` 로 반출(단계 12 tail 조건부 포함용) ④ `giipAgent.cnf` 작성/갱신(§4) ⑤ cron: `giip-agent`(매 1분 `giipAgent3.sh`), `giip-cqe`(매 5분 `cqe/giipCQE.sh`) | git 실패는 **치명**. cnf sk 가 SSOT 와 다르면 경고 후 갱신, `STRICT` 면 중단. SK 를 못 구하면 이 단계 전체를 **건너뜀**(요약 블록 `giip agent=off (사유)`; 웹에서 이 컨테이너 상태가 안 보임) |
| 9 | cron 데몬 | `/etc/cron.d/*` 가 하나라도 있으면 `cron` 을 **한 번만** 기동(중복 기동은 lock 오류) | — |
| 10 | 정합성 점검 | `scripts/gissue/check-csn-consistency.sh`(3개 cron 의 CSN 일치 확인) | **비차단**: 경고만 |
| 11 | 인스턴스 부트스트랩 | `scripts/bootstrap-instance.sh`(여러 번 실행해도 결과가 같음): root 소유 파일 회수, `powershell` 링크, `SqlServer` 모듈, 허브 저장소 clone(없을 때만), `giipdb/mgmt/dbconfig.json` 생성(없을 때만, `GIIP_DB_*` 또는 `/work/.secrets`), 환경 점검. 값은 출력하지 않는다 | 실패는 무시(경고) |
| 12 | 유지 | `ready.` **직전에 `[entrypoint] summary` 블록**(slack-bot / scheduler / giip agent(on\|off+사유) / fetch)을 출력(giip #2855 T4). 이어서 `scripts/gissue/logs/cron.log`(항상) + `AGENT_CRON_LOG`(세팅됐을 때만) + pm2 로그를 tail 대상으로 모아 `exec tail -F ...` — 이 프로세스가 PID 1. **블록 밖 무조건 `/work/giipAgentLinux/log` 생성은 제거**(에이전트 미사용 시 phantom 디렉터리 금지, giip #2855 T1). tail 인자가 0개가 되지 않도록 REPO 로그는 항상 포함하고, 어떤 파일이 잡혔는지(존재 여부) 로그 | — |

### 5.1 스케줄러 cron 명령(단계 7)

- 명령: `pwsh -NoProfile -NonInteractive -File .../run-gissue-claude.ps1 [-OnlyCsn <CSN>] >> .../cron.log 2>&1`.
  실행 이력(`tSchedulerAgentRun`)은 스크립트가 `lib/scheduler-state.ps1` 로 직접 기록한다(giip #3563). 한때(PR #107) 쓰던 bash 래퍼는 제거됐다.
- **스케줄러 cron 은 root 가 아니라 `dev` 로 돈다(giip #3535).** 엔진이 `claude -p --dangerously-skip-permissions` 를 호출하는데 claude 는 root/sudo 에서 이 옵션을 거부한다(`--dangerously-skip-permissions cannot be used with root/sudo privileges`).
  root 로 돌리면 로그에는 이슈가 "처리 시작"으로 찍히지만 모든 엔진 호출이 즉시 실패해 큐가 줄지 않는다(실측: `gissue_csn47.out.log` 에 788회). `dev` 에는 claude 로그인 정보(`~/.claude/.credentials.json`)가 있어야 하며 없으면 entrypoint 가 경고한다.
- **cron 은 컨테이너 env 를 상속하지 않는다**(코드에 env 전달이 없다). 스케줄러가 쓰는 값은 단계 4 가 만든 파일들(`csn-projects.json`, `giip-accounts.json`)과 `giipAgent.cnf` 에서 읽는다.
- 이전 실행이 아직 돌면 `run-gissue-claude.ps1` 의 CSN lock 이 SKIP 시켜 겹치지 않는다.
- **소프트 예산 기본값 주입(giip 3615)**: cron 명령 앞에 `GISSUE_SOFT_BUDGET_MIN=<분>` 을 붙인다(cron 은 컨테이너 env 를 상속하지 않으므로 명령에 직접 넣는다).
  값은 컨테이너 env `GISSUE_SOFT_BUDGET_MIN`, 없으면 **15**(20분 틱의 약 3/4), 숫자가 아니면 15. `0` 이면 비활성.
  의미는 `hourly-issue-scheduler.md` §8-1. 이미지 재빌드 없이 쓰려면 `scripts/gissue/csn-projects.json` 최상위 `softBudgetMin` 에 적는다(환경변수보다 우선, `0` 이면 끔).
  ⚠️ **entrypoint 변경(기본값 15 주입)은 이미지 재빌드가 필요하다**(위 단계 7 설명대로 cron 명령은 baked entrypoint 가 만든다). 재빌드 전에는 csn-projects.json 키만 효과가 있다.

## 6. 불변식(지켜져야 하는 것)

1. **1 인스턴스 = 1 CSN**. cron 의 `-OnlyCsn`, `giipAgent.cnf` 의 sk, `csn-projects.json` 의 csn 키는 같은 CSN 이어야 한다. SSOT 는 `csn-projects.json` 이고 `GIIP_CSN`/`GIIP_SK` 는 최초 seed 일 뿐이다.
2. **재기동해도 안전(여러 번 실행해도 결과가 같음)**: 이미 있는 파일은 덮어쓰지 않는다(`giipAgent.cnf` 는 sk 줄만 갱신, lssn 보존). cron 파일은 매번 같은 내용으로 다시 쓴다.
3. **비밀값은 로그에 찍지 않는다**: SK/토큰은 로그에 값이 아닌 출처만 남긴다(`giipAgent SK: ... 정본에서 파생`). 파일은 `slack-bot/.secrets/`(커밋 금지) 아래.
4. **선택 기능의 실패가 컨테이너를 죽이지 않는다**: 프로젝트 clone(3), 정합성 점검(10), root 파일 회수(11)는 경고만. 반대로 저장소 sync(1), 등록(4), slack-bot(6), giipAgentLinux git(8)은 치명이다.

## 7. 알려진 한계와 주의(2026-10-06 시점, 검증 상태 포함)

| # | 내용 | 상태 |
|---|---|---|
| L1 | 이미지에 구워진 entrypoint 라 repo 변경이 기존 컨테이너에 반영되지 않는다(§2) | 설계상 사실 |
| L2 | (해결됨) 래퍼의 `exec` 문제는 래퍼를 제거하고 근본 원인(호출 형식)을 고쳐 해소했다. 이력은 `gissue_csn<CSN>` 에이전트 아래에 기록된다 | giip #3563 |
| L3 | 단계 1 은 가드가 없어 일시적 네트워크 장애에도 컨테이너가 종료·재시작을 반복한다 | 관찰이 아닌 코드 읽기 결과. 재현 안 함 |
| L4 | (해결됨, giip #2855) 단계 2 의 `fetch` 실패를 이제 종료코드로 명시 검사한다 — `[entrypoint] WARN` + 요약 블록 `fetch=failed` 로 드러나고, `GIIP_STRICT_FETCH=true` 면 기동을 중단한다. 과거엔 `eval "$(...)"` 가 `set -e` 를 발동시키지 않아 조용히 지나갔다 | 코드 정적 확인 + `bash -n` |
| L5 | `eval` 로 원격 응답을 실행한다. `JSON.stringify` 로 값을 인용하지만, **GIIP 웹 응답을 신뢰하는 모델**이다 | 설계 판단 필요 |
| L6 | giip-agent/giip-cqe cron 은 여전히 root 로 돈다(이슈 스케줄러만 dev). root 로 만든 파일은 단계 11 이 회수한다 | 이슈 스케줄러는 dev 로 수정됨 |
| L8 | `dev` 의 claude 로그인은 인스턴스마다 한 번 수동으로 해야 한다(`docker exec -it -u dev <컨테이너> claude`). 로그인이 없으면 스케줄러가 이슈를 처리하지 못하고 entrypoint 는 경고만 한다 | 자동화 안 됨 |

## 8. 검증 방법

```bash
bash -n docker/entrypoint.sh                       # 구문
docker compose -p giip-fde-test up -d --build      # 새 컨테이너로 기동(이미지 재빌드 포함)
docker logs giip-fde-agent | grep '^\[entrypoint\]'   # 단계별 로그 확인
docker exec giip-fde-agent ls /etc/cron.d          # gissue-scheduler / giip-agent / giip-cqe
docker exec giip-fde-agent bash scripts/gissue/check-csn-consistency.sh   # 3개 cron 의 CSN 일치
```

기대 로그: `repo: ... pulled latest` → (`project repo ...`) → `SSOT CSN ... = <CSN>` → `registered issue-scheduler cron` → `registered giipAgentLinux cron` → `cron daemon started` → **`[entrypoint] summary:`**(`slack-bot` / `scheduler` / `giip agent: on|off (사유)` / `fetch`)(giip #2855) → `ready. tailing logs.` → `tail + <경로> (존재|아직 없음)` 줄들
**이 사양서 작성 시점에는 위 절차를 실제 컨테이너 기동으로 재검증하지 않았다**(코드 읽기와 `bash -n` 구문 검사, 일부 쉘 동작 실측만 했다. docker 미설치 환경이라 giip #2855 의 런타임 verify (6)(7)도 미실측).

## 9. 변경 이력(entrypoint.sh)

| 날짜 | 커밋 | 이슈 | 내용 |
|---|---|---|---|
| 2026-09-18 | `592ec89` | giip 2665 | 최초 생성: clone/pull, 등록, slack-bot, 스케줄러 cron |
| 2026-09-18 | `88251cc` | giip 2665 | `GIIP_INSTANCE_TOKEN` 으로 웹에서 env 수신 |
| 2026-09-21 | `677fd13` | giip 2665 | 컨테이너 안에서 giipAgentLinux 실행(웹에서 heartbeat 확인) |
| 2026-09-24 | `217f9b0` | giip #2949 | 프로젝트 저장소 자동 clone |
| 2026-09-25 | `4192d26` | — | 컨테이너마다 스케줄러 20분 주기 |
| 2026-09-30 | `058667f`, `f856ab7` | giip #3405 | CSN SSOT 일원화, 하드코딩 제거, gh 영속화 |
| 2026-10-04 | `ee43e5b` | giip #3405 | `giipAgent.cnf` SK 를 SSOT 에서 파생 |
| 2026-10-06 | PR #106 | giip #3535 | `fix-root-owned.sh` 호출 |
| 2026-10-06 | PR #107 | giip #3575 | cron 이 래퍼 호출 |
| 2026-10-06 | PR #110 | giip #3535 | 단계 11 을 `fix-root-owned.sh` 단독 호출에서 `bootstrap-instance.sh` 로 확장 |
| 2026-10-06 | PR #111 | giip #3535 | 스케줄러 cron 사용자를 root 에서 dev 로 변경(claude 가 root 에서 bypass 를 거부해 이슈가 처리되지 않았음) |
| 2026-10-06 | (이 변경) | giip #3563 | 래퍼 제거, 근본 원인(`Record-SchedulerState` 호출 형식) 수정으로 cron 은 pwsh 직접 호출 |
| 2026-10-07 | (giip 3615 PR) | giip 3615 | 스케줄러 cron 에 `GISSUE_SOFT_BUDGET_MIN`(기본 15) 주입 — 이미지 재빌드 필요 |
| 2026-11-04 | (이 변경) | giip #2855 | phantom `/work/giipAgentLinux` 생성 차단(블록 밖 무조건 mkdir 제거, tail 조건부·비하드코딩), clone 잔해 退避 후 자가회복, fetch 실패 종료코드 명시 검사(`GIIP_STRICT_FETCH`), `ready.` 직전 기동 요약 블록 추가 |

## 10. 저장소 갱신 실패 허용(`safe_update_repo`, 2026-11-11)

**배경(인시던트)**: `set -euo pipefail` 아래에서 `git fetch / checkout / merge --ff-only` 가 보호 없이 실행되어, 볼륨 repo 에 커밋 안 된 추적 파일 변경이 있고 들어오는 커밋이 같은 파일을 건드리면 `merge --ff-only` 가 "Your local changes ... would be overwritten by merge" 로 중단 → `set -e` 로 entrypoint 가 exit 1 → Docker 가 무한 재시작했다. 컨테이너 `dxsmo` 가 2026-11-11 에 217회 재시작했다. 앞서 `caci-aqchat` 은 remote-tracking ref 손상(`fatal: bad object refs/remotes/origin/...`)으로 같은 루프에 빠졌다.

**동작**: `docker/entrypoint.sh` 의 `safe_update_repo <dir> <branch> <label>`(`# >>> safe_update_repo` 마커 구간)이 fetch/checkout/merge 를 `if` 로 감싸 `set -e` 의 영향을 받지 않게 한다. 성공하면 기존과 같은 `[entrypoint] pulled latest (<sha>)` 를 출력한다. 실패하면 `[entrypoint] WARN:` 블록(label, 실패 단계, `git status --short` 앞 10줄, `continuing with the current checkout (HEAD=<sha>) — local changes were NOT touched`)을 stderr 로 출력하고 0 을 반환해 현재 체크아웃으로 계속한다. reset/clean/stash/`checkout -f`/삭제는 하지 않는다. 적용 대상은 fde repo(`REPO_DIR`)와 giipAgentLinux(`GIIP_AGENT_DIR`)의 갱신 블록이며, 프로젝트 repo(`PROJECT_DIR`)는 이미 같은 방식이었다.

**검증**: `bash docker/tests/test-safe-update-repo.sh` 로 (a) clean + 신규 커밋 → 갱신, (b) 같은 파일을 로컬이 수정 → rc 0·WARN 출력·로컬 수정 바이트 동일·HEAD 불변, (c) 0바이트 remote-tracking ref → rc 0 을 임시 repo 에서 확인했다. 실제 컨테이너 기동으로는 검증하지 않았다.

**적용 시점 주의**: entrypoint 는 이미지에 `/entrypoint.sh` 로 구워져 있으므로, 이 수정은 이미지를 재빌드하고 컨테이너를 재생성한 뒤에야 효력이 생긴다. 기존 컨테이너는 옛 entrypoint 를 계속 쓴다. WARN 이 뜬 repo 는 사람이 로컬 변경을 정리(커밋/폐기)해야 최신 코드로 올라온다.

### 10.1 giipAgentLinux cron 단일 인스턴스 가드(`agent_cron_line`, 2026-11-11)

**배경(인시던트)**: entrypoint 가 등록하는 `/etc/cron.d/giip-agent` 는 매분 `bash giipAgent3.sh` 를 실행한다. `lwweb02` 컨테이너에서 이 작업이 `/tmp` 읽기에서 막혀 끝나지 않았고, 매분 새 프로세스가 쌓여 D-state 프로세스가 2시간 45분 만에 6개에서 83개로 늘었으며 Docker VM 디스크가 포화되어 멈췄다. giipAgentLinux 저장소에는 스크립트 내부 단일 인스턴스 가드가 별도 변경으로 들어가지만, 컨테이너는 에이전트 저장소와 함께 재빌드되지 않으므로 cron 줄 자체도 안전해야 한다. 실행 중인 호스트에는 같은 줄을 임시로 직접 패치했고, entrypoint 가 매 기동마다 이 파일을 다시 쓰기 때문에 Windows 쪽 스크립트가 재적용하고 있다.

**동작**: `docker/entrypoint.sh` 의 `agent_cron_line <agent_dir>`(`# >>> agent-cron-line` 마커 구간)가 `command -v flock` 로 flock 유무를 판단한다. 있으면 `* * * * * root cd <dir> && flock -n /dev/shm/giipAgent3.lock bash giipAgent3.sh >> <dir>/log/cron.log 2>&1`, 없으면 기존 줄을 `/etc/cron.d/giip-agent` 에 쓴다(`chmod 0644` 유지). 잠금 파일은 막힌 디렉터리 스캔이 있는 `/tmp` 가 아니라 tmpfs 인 `/dev/shm` 에 둔다. 기동 로그에 `[entrypoint] giip-agent cron: single-instance guard (flock) on|off` 가 한 줄 남는다. `giip-cqe`(`*/5`) 줄은 변경하지 않았다.

**검증**: `bash docker/tests/test-agent-cron-line.sh` 가 flock 있음/없음(PATH 조작) 두 변형의 출력 줄을 단언한다. 실제 컨테이너 기동으로는 검증하지 않았다.

**적용 시점 주의**: 이미지에 구워진 `/entrypoint.sh` 가 바뀌므로 이미지 재빌드와 컨테이너 재생성 후에야 효력이 생긴다. 그 전까지는 호스트 쪽 재적용 스크립트가 유지한다.
