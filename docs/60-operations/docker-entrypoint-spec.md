# docker/entrypoint.sh 사양서

> **기준**: `main` @ `cb25db5`(2026-10-06). 코드: [`docker/entrypoint.sh`](../../docker/entrypoint.sh) 248줄.
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
| 실행 사용자 | **root** (Dockerfile 에 `USER` 없음). cron 작업도 root | `docker/Dockerfile`, 아래 cron 줄 |
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
| `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | 없음 | 둘 다 있을 때만 slack-bot 기동 | 6 |
| `GIIP_ENABLE_SCHEDULER` | `true` | `false` 면 이슈 스케줄러 cron 생략 | 7 |
| `GIIP_ENABLE_AGENT` | `true` | `false` 면 giipAgentLinux/CQE 생략 | 8 |
| `GIIP_AGENT_DIR` / `GIIP_AGENT_URL` | `/work/giipAgentLinux` / 공식 giipAgentLinux URL | giipAgentLinux clone 위치·출처 | 8 |
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
| 로그 | `scripts/gissue/logs/cron.log`, `/work/giipAgentLinux/log/cron.log`, `/tmp/giip_cqe_logs/cqe_cron.log`, pm2 로그 | 7, 8, 12 | 누적 |

## 5. 단계별 동작과 실패 처리

| # | 단계 | 동작 | 실패 시 |
|---|---|---|---|
| 1 | 저장소 동기화 | `.git` 있으면 `fetch → checkout $REPO_BRANCH → merge --ff-only`, 없으면 `clone`. 짧은 커밋 해시를 로그 | **치명**(`set -e`): 네트워크 불가, 로컬 커밋으로 ff 불가 시 컨테이너가 종료되고 `restart: unless-stopped` 로 재시작 반복 |
| 2 | 인스턴스 env 주입 | `eval "$(/fetch-instance-env.sh)"`. `GIIP_INSTANCE_TOKEN` 이 없으면 아무것도 안 함. 있으면 `dockerInstanceFetch` 응답의 env 중 **비어 있는 키만** `export` | **조용히 계속**: 응답 실패 시 스크립트는 stderr 에 `dockerInstanceFetch failed` 를 찍고 끝나지만 `eval "$(실패)"` 는 `set -e` 를 발동시키지 않는다(실측). 필요한 값이 비면 이후 단계가 알아서 건너뜀 |
| 3 | 프로젝트 저장소 | `GIIP_PROJECT_REPO_URL` 이 있으면 `PROJECT_DIR`(=`GIIP_WORKDIR` 또는 `/work/<repo>`)에 pull/clone. 기본 경로면 `GIIP_WORKDIR` 를 export | **경고만**: 컨테이너는 계속 |
| 4 | 등록 파일 생성 | `node /setup-registration.js`. 위 §4 의 `csn-projects.json`, `giip-accounts.json`, heartbeat 블록 생성(없을 때만). `logs/` 디렉터리 생성 | 스크립트 오류는 **치명**. 단 heartbeat 등록 실패는 스크립트 안에서 삼키고 다음 기동 때 재시도 |
| 5 | SSOT CSN 결정 | `lib/ssot-csn.js` 로 `csn-projects.json` 의 **단일 csn 키** 확정 → `EFFECTIVE_CSN`. 확정 못 하면 `GIIP_CSN` 폴백. `GIIP_CSN` 과 SSOT 가 다르면 경고 | 경고. `GIIP_STRICT_CSN=true` 면 **중단** |
| 6 | slack-bot | 토큰 2개가 모두 있을 때만 `npm install --omit=dev` 후 `pm2 start index.js --name giipclaude-bot` | `npm`/`pm2` 실패는 **치명** |
| 7 | 이슈 스케줄러 cron | `GIIP_ENABLE_SCHEDULER=true` 일 때 `/etc/cron.d/gissue-scheduler` 작성: `7,27,47 * * * * root cd $REPO_DIR && <CRON_CMD>`. `-OnlyCsn <EFFECTIVE_CSN>`. 작성 후 cron 줄의 `-OnlyCsn` 이 SSOT 와 같은지 재확인 | 불일치는 경고, `STRICT` 면 중단 |
| 8 | giipAgentLinux + CQE | `GIIP_ENABLE_AGENT=true` 이고 SK 가 있을 때만. ① SK 결정: `lib/ssot-sk.js`(giip-accounts.json, EFFECTIVE_CSN)가 우선, 실패 시 `GIIP_SK` 폴백 ② giipAgentLinux 를 `main` 으로 pull/clone ③ `giipAgent.cnf` 작성/갱신(§4) ④ cron: `giip-agent`(매 1분 `giipAgent3.sh`), `giip-cqe`(매 5분 `cqe/giipCQE.sh`) | git 실패는 **치명**. cnf sk 가 SSOT 와 다르면 경고 후 갱신, `STRICT` 면 중단. SK 를 못 구하면 이 단계 전체를 **건너뜀**(웹에서 이 컨테이너 상태가 안 보임) |
| 9 | cron 데몬 | `/etc/cron.d/*` 가 하나라도 있으면 `cron` 을 **한 번만** 기동(중복 기동은 lock 오류) | — |
| 10 | 정합성 점검 | `scripts/gissue/check-csn-consistency.sh`(3개 cron 의 CSN 일치 확인) | **비차단**: 경고만 |
| 11 | root 소유 파일 회수 | `scripts/fix-root-owned.sh`(`/work` 의 root 소유 파일을 dev 로 chown) | 실패는 무시 |
| 12 | 유지 | 로그 파일들을 만들고 `exec tail -F ...` — 이 프로세스가 PID 1 이 되어 컨테이너가 살아 있다 | — |

### 5.1 스케줄러 cron 명령(단계 7)

- 현재 `main`: `bash "$REPO_DIR/scripts/gissue/run-gissue-scheduler-wrapper.sh" [-OnlyCsn <CSN>] >> .../cron.log 2>&1` (giip #3575, PR #107).
  래퍼는 giipAgentLinux 의 `lib/scheduler_agent_run.sh` 를 source 해 `sar_run_start` 로 실행 이력을 `tSchedulerAgentRun` 에 남기고, 마지막에 `pwsh run-gissue-claude.ps1` 을 부른다.
  `giipAgent.cnf` 의 `sk`/`apiaddrv2` 가 없으면 이력 없이 pwsh 를 직접 호출한다.
- 이전: `pwsh -NoProfile -NonInteractive -File .../run-gissue-claude.ps1 [-OnlyCsn <CSN>]`.
- **cron 은 컨테이너 env 를 상속하지 않는다**(코드에 env 전달이 없다). 스케줄러가 쓰는 값은 단계 4 가 만든 파일들(`csn-projects.json`, `giip-accounts.json`)과 `giipAgent.cnf` 에서 읽는다.
- 이전 실행이 아직 돌면 `run-gissue-claude.ps1` 의 CSN lock 이 SKIP 시켜 겹치지 않는다.

## 6. 불변식(지켜져야 하는 것)

1. **1 인스턴스 = 1 CSN**. cron 의 `-OnlyCsn`, `giipAgent.cnf` 의 sk, `csn-projects.json` 의 csn 키는 같은 CSN 이어야 한다. SSOT 는 `csn-projects.json` 이고 `GIIP_CSN`/`GIIP_SK` 는 최초 seed 일 뿐이다.
2. **재기동해도 안전(여러 번 실행해도 결과가 같음)**: 이미 있는 파일은 덮어쓰지 않는다(`giipAgent.cnf` 는 sk 줄만 갱신, lssn 보존). cron 파일은 매번 같은 내용으로 다시 쓴다.
3. **비밀값은 로그에 찍지 않는다**: SK/토큰은 로그에 값이 아닌 출처만 남긴다(`giipAgent SK: ... 정본에서 파생`). 파일은 `slack-bot/.secrets/`(커밋 금지) 아래.
4. **선택 기능의 실패가 컨테이너를 죽이지 않는다**: 프로젝트 clone(3), 정합성 점검(10), root 파일 회수(11)는 경고만. 반대로 저장소 sync(1), 등록(4), slack-bot(6), giipAgentLinux git(8)은 치명이다.

## 7. 알려진 한계와 주의(2026-10-06 시점, 검증 상태 포함)

| # | 내용 | 상태 |
|---|---|---|
| L1 | 이미지에 구워진 entrypoint 라 repo 변경이 기존 컨테이너에 반영되지 않는다(§2) | 설계상 사실 |
| L2 | **래퍼의 `exec pwsh` 때문에 `trap 'sar_run_end_trap' EXIT` 가 실행되지 않는다**(`exec` 는 셸을 교체해 EXIT trap 이 발동하지 않음, 같은 구조로 실측 확인). 그 결과 실행 시작만 기록되고 종료가 기록되지 않아 이력이 RUNNING/STALE 로 남을 수 있다. 또 이력은 gissue 에이전트(`gissue_csn<CSN>`)가 아니라 박스 에이전트 키(`hostname-machine-id`) 아래에 쌓인다 | **미수정**, PR #107 로 `main` 에 병합됨. 근본 원인은 `run-gissue-claude.ps1` 의 `Record-SchedulerState` 가 디스패처 형식(`sk`/`proc`)을 잘못 쓰는 것(giip #3563) |
| L3 | 단계 1 은 가드가 없어 일시적 네트워크 장애에도 컨테이너가 종료·재시작을 반복한다 | 관찰이 아닌 코드 읽기 결과. 재현 안 함 |
| L4 | 단계 2 의 `fetch` 실패가 조용히 지나간다(`eval "$(...)"`). 토큰이 잘못돼도 컨테이너는 env 없이 계속 뜨고, 이후 단계가 값 부족으로 건너뛴다 | 실측(`set -e` 미발동) |
| L5 | `eval` 로 원격 응답을 실행한다. `JSON.stringify` 로 값을 인용하지만, **GIIP 웹 응답을 신뢰하는 모델**이다 | 설계 판단 필요 |
| L6 | 모든 cron 이 root 로 돈다. 그 안의 git/claude 가 root 소유 파일을 만든다(단계 11 이 회수) | 근본 수정(사용자 변경)은 미적용 |
| L7 | `bootstrap-instance.sh`(DB 접속 파일 생성, 허브 clone, 환경 점검)는 `main` 에 **아직 없다**. 단계 11 은 `fix-root-owned.sh` 만 부른다 | 별도 브랜치에만 있음 |

## 8. 검증 방법

```bash
bash -n docker/entrypoint.sh                       # 구문
docker compose -p giip-fde-test up -d --build      # 새 컨테이너로 기동(이미지 재빌드 포함)
docker logs giip-fde-agent | grep '^\[entrypoint\]'   # 단계별 로그 확인
docker exec giip-fde-agent ls /etc/cron.d          # gissue-scheduler / giip-agent / giip-cqe
docker exec giip-fde-agent bash scripts/gissue/check-csn-consistency.sh   # 3개 cron 의 CSN 일치
```

기대 로그: `repo: ... pulled latest` → (`project repo ...`) → `SSOT CSN ... = <CSN>` → `registered issue-scheduler cron` → `registered giipAgentLinux cron` → `cron daemon started` → `ready. tailing logs.`
**이 사양서 작성 시점에는 위 절차를 실제 컨테이너 기동으로 재검증하지 않았다**(코드 읽기와 일부 쉘 동작 실측만 했다).

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
| 2026-10-06 | PR #107 | giip #3575 | cron 이 래퍼 호출(§7 L2) |
