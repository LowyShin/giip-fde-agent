#!/usr/bin/env bash
# giip-fde-agent container entrypoint: auto clone/pull, register csn/sk/login_id,
# start slack-bot (pm2) and the hourly-issue-scheduler (cron + pwsh; cron runs as the non-root scheduler user, see below).
# See docker/README.md for the full env var contract.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/work/giip-fde-agent}"
REPO_URL="${REPO_URL:-https://github.com/LowyShin/giip-fde-agent.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

# 볼륨의 repo 는 스케줄러 사용자(dev) 소유로 회수되므로(fix-root-owned.sh) root 로 도는 entrypoint 의 git 이 재기동 때
# "detected dubious ownership" 으로 실패해 컨테이너가 Restarting(128) 루프에 빠진다. root 전용 전역 설정이다.
git config --global --add safe.directory '*' || true

# >>> safe_update_repo
# safe_update_repo <dir> <branch> <label>
# fetch/checkout/merge --ff-only 를 set -e 로부터 보호한다. 볼륨 repo 에 커밋 안 된 추적 파일 변경이 있어
# merge 가 중단되거나(dxsmo 217회 재시작) remote-tracking ref 가 깨져 있어도(caci-aqchat) entrypoint 가
# 죽지 않고 현재 체크아웃으로 계속한다. reset/clean/stash/checkout -f/삭제는 절대 하지 않는다(로컬 작업 보존).
safe_update_repo() {
  local dir="$1" branch="$2" label="$3" step=""
  if   ! git -C "$dir" fetch origin "$branch";          then step="fetch"
  elif ! git -C "$dir" checkout "$branch";              then step="checkout"
  elif ! git -C "$dir" merge --ff-only "origin/$branch"; then step="merge --ff-only"
  fi
  if [ -z "$step" ]; then
    echo "[entrypoint] pulled latest ($(git -C "$dir" rev-parse --short HEAD))"
  else
    {
      echo "[entrypoint] WARN: $label update failed at step '$step' ($dir, branch $branch)"
      echo "[entrypoint] WARN: git status --short (first 10 lines):"
      git -C "$dir" status --short 2>&1 | head -n 10 || true
      echo "[entrypoint] WARN: continuing with the current checkout (HEAD=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)) — local changes were NOT touched"
    } >&2
  fi
  return 0
}
# <<< safe_update_repo
# >>> agent-cron-line
# agent_cron_line <agent_dir>: giipAgentLinux cron 한 줄을 stdout 으로 낸다.
# flock 이 있으면 /dev/shm(tmpfs) 잠금으로 단일 인스턴스 보장 — 이전 실행이 안 끝났으면 새 실행은 즉시 건너뛴다.
# 잠금 파일은 /tmp 가 아니라 /dev/shm 이어야 한다(/tmp 디렉터리 스캔에서 막히는 사고 대응).
agent_cron_line() {
  if command -v flock >/dev/null 2>&1; then
    echo "* * * * * root cd $1 && flock -n /dev/shm/giipAgent3.lock bash giipAgent3.sh >> $1/log/cron.log 2>&1"
  else
    echo "* * * * * root cd $1 && bash giipAgent3.sh >> $1/log/cron.log 2>&1"
  fi
}
# <<< agent-cron-line
echo "[entrypoint] repo: $REPO_URL ($REPO_BRANCH) -> $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
  safe_update_repo "$REPO_DIR" "$REPO_BRANCH" "fde repo"
else
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
  echo "[entrypoint] cloned ($(git -C "$REPO_DIR" rev-parse --short HEAD))"
fi

# giip #2855 T4: 기동 요약 블록용 상태 변수. 각 단계에서 갱신하고, 마지막에 'ready.' 직전 한 블록으로
# 출력한다(개별 skip 메시지는 위에 흩어져 tail -F 출력에 묻히므로, 사용자가 "왜 안 뜨나" 를 이 한
# 블록만 보고 판정할 수 있게 한다). set -u 때문에 읽기 전에 반드시 초기화한다.
FETCH_STATUS="unused (GIIP_INSTANCE_TOKEN 미설정)"
SLACK_STATUS="off"
SCHED_STATUS="off"
AGENT_STATUS="off"
AGENT_CRON_LOG=""   # 에이전트 블록이 실제로 돌면 그 cron.log 경로가 들어간다(tail 대상 조건부 포함용)

# ── optional: pull env from GIIP web (giip 2665 "Docker 생성") instead of per-field env vars ──
# giip #2855 T3: fetch 실패를 삼키지 않는다. 명령치환을 바로 eval 하면 fetch-instance-env.sh 가
# exit 1(curl 실패 / RstVal!=200)로 끝나도 `eval ""` 의 종료코드가 0 이라 set -e 가 발동하지 않아,
# env 를 하나도 못 받은 채 기동이 계속되고 GIIP_SK 가 비어 phantom clone 경로로 들어갔다(이 이슈의
# 2차 원인). stdout(=export 줄)만 캡처하고 종료코드를 명시적으로 검사한다(진행 메시지는 stderr).
FETCH_ENV=""
FETCH_RC=0
if FETCH_ENV="$(/fetch-instance-env.sh)"; then
  FETCH_RC=0
else
  FETCH_RC=$?
fi
if [ "$FETCH_RC" -eq 0 ]; then
  eval "$FETCH_ENV"
  if [ -n "${GIIP_INSTANCE_TOKEN:-}" ]; then
    FETCH_STATUS="ok (dockerInstanceFetch 적용됨)"
  fi
else
  FETCH_STATUS="failed (fetch-instance-env.sh exit $FETCH_RC) — env 미수신, 이후 단계가 값 부족으로 건너뜀"
  echo "[entrypoint] WARN: 인스턴스 env fetch 실패(exit $FETCH_RC) — GIIP_INSTANCE_TOKEN 이 설정됐는데 dockerInstanceFetch 가 실패했습니다. GIIP_SK 등이 비어 giip agent 가 건너뛰어질 수 있습니다(요약 블록에서 다시 알립니다)." >&2
  if [ "${GIIP_STRICT_FETCH:-false}" = "true" ]; then
    echo "[entrypoint] GIIP_STRICT_FETCH=true — 인스턴스 env fetch 실패로 기동 중단"; exit 1
  fi
fi

# ── giip #2949: optional target project repo clone (zero-touch remote clone) ──
# GIIP web의 docker-instances 생성 폼에 프로젝트 레포 URL을 넣으면 dockerInstanceFetch env로
# GIIP_PROJECT_REPO_URL / GIIP_PROJECT_REPO_BRANCH 가 내려온다. 사람이 대상 PC에 접속하거나 CQE를 수동
# 등록할 필요 없이, 컨테이너가 최초 기동 시 여기서 직접 clone한다(위에서 giip-fde-agent/giipAgentLinux를
# clone하는 것과 동일한 방식·신뢰모델). GIIP_WORKDIR을 안 주면 레포명 기반 기본 경로에 clone하고 그 경로를
# GIIP_WORKDIR로 export해 아래 setup-registration.js가 scheduler workdir로 등록하게 한다. clone 실패가
# 컨테이너 전체를 죽이지 않도록 방어한다(set -e).
if [ -n "${GIIP_PROJECT_REPO_URL:-}" ]; then
  PROJECT_REPO_BRANCH="${GIIP_PROJECT_REPO_BRANCH:-main}"
  if [ -n "${GIIP_WORKDIR:-}" ]; then
    PROJECT_DIR="$GIIP_WORKDIR"
  else
    _repo_base="$(basename "$GIIP_PROJECT_REPO_URL")"
    _repo_base="${_repo_base%.git}"
    PROJECT_DIR="/work/${_repo_base:-project}"
    export GIIP_WORKDIR="$PROJECT_DIR"
  fi
  echo "[entrypoint] project repo: $GIIP_PROJECT_REPO_URL ($PROJECT_REPO_BRANCH) -> $PROJECT_DIR"
  if [ -d "$PROJECT_DIR/.git" ]; then
    if git -C "$PROJECT_DIR" fetch origin "$PROJECT_REPO_BRANCH" \
       && git -C "$PROJECT_DIR" checkout "$PROJECT_REPO_BRANCH" \
       && git -C "$PROJECT_DIR" merge --ff-only "origin/$PROJECT_REPO_BRANCH"; then
      echo "[entrypoint] project repo pulled ($(git -C "$PROJECT_DIR" rev-parse --short HEAD))"
    else
      echo "[entrypoint] WARN: project repo pull failed — continuing with existing checkout"
    fi
  else
    if git clone --branch "$PROJECT_REPO_BRANCH" "$GIIP_PROJECT_REPO_URL" "$PROJECT_DIR"; then
      echo "[entrypoint] project repo cloned ($(git -C "$PROJECT_DIR" rev-parse --short HEAD))"
    else
      echo "[entrypoint] WARN: project repo clone failed ($GIIP_PROJECT_REPO_URL) — container continues without it"
    fi
  fi
fi

REPO_DIR="$REPO_DIR" node /setup-registration.js

mkdir -p "$REPO_DIR/scripts/gissue/logs"

# ── giip #3405: resolve this machine's CSN from the single source of truth (SSOT) ──
# SSOT = scripts/gissue/csn-projects.json 의 단일 csn 키. GIIP_CSN 환경변수는 최초 기동 때 이 파일을
# 만드는 입력일 뿐이라, 클론 후 csn-projects.json 만 새 CSN 으로 바꾸고 컨테이너를 재기동하면(env 는 옛
# 값 유지) 둘이 어긋난다(최초 기동 CSN 이 cron 에 박힌 채 매핑만 새 CSN 으로 바뀌어 조용히 어긋남).
# 그래서 아래 스케줄러 cron 의 -OnlyCsn 은 env 가 아니라 이 SSOT 에서 파생하고, env 와 SSOT 가 다르면 경고한다.
CSN_MAP_FILE="$REPO_DIR/scripts/gissue/csn-projects.json"
SSOT_CSN=""
if [ -f "$CSN_MAP_FILE" ]; then
  if SSOT_CSN="$(node "$REPO_DIR/scripts/gissue/lib/ssot-csn.js" "$CSN_MAP_FILE")"; then
    echo "[entrypoint] SSOT CSN (csn-projects.json) = $SSOT_CSN"
  else
    SSOT_CSN=""
    echo "[entrypoint] WARN: csn-projects.json 에서 단일 CSN 을 확정하지 못함 — GIIP_CSN 폴백"
    if [ "${GIIP_STRICT_CSN:-false}" = "true" ]; then
      echo "[entrypoint] GIIP_STRICT_CSN=true — CSN 정합성 확정 실패로 기동 중단"; exit 1
    fi
  fi
fi
# guard: env(GIIP_CSN) 와 SSOT 가 다르면 clone+swap 후 stale env 다 (giip #3405)
if [ -n "${GIIP_CSN:-}" ] && [ -n "$SSOT_CSN" ] && [ "$GIIP_CSN" != "$SSOT_CSN" ]; then
  echo "[entrypoint] WARN: GIIP_CSN(env)=$GIIP_CSN != csn-projects.json csn=$SSOT_CSN — 클론 후 env 가 stale 합니다. csn-projects.json(SSOT) 값을 사용합니다."
  if [ "${GIIP_STRICT_CSN:-false}" = "true" ]; then
    echo "[entrypoint] GIIP_STRICT_CSN=true — CSN 불일치로 기동 중단"; exit 1
  fi
fi
# 최종 사용할 CSN: SSOT 우선, 없으면(csn-projects.json 이 아직 없는 최초 기동 등) GIIP_CSN 폴백
EFFECTIVE_CSN="${SSOT_CSN:-${GIIP_CSN:-}}"

# giip #4231: slack-bot 도 scheduler 와 동일한 비-root 사용자로 돌려야 한다 — claude-cli.js 가
# `claude -p --dangerously-skip-permissions` 로 호출하는데 claude 는 root/sudo 에서 이 옵션을
# 거부하고, root 의 HOME 에는 그 사용자의 OAuth 인증 정보도 없다(실측: root 로 pm2 start 한
# slack-bot 이 모든 Slack 응답에서 "claude(default) 인증 재시도 실패"로 실패, 2026-10-29).
# scheduler 블록과 사용자를 공유해 한 곳에서만 만들고 재사용한다(중복 생성 로직 제거).
GIIP_RUNTIME_USER="${GIIP_SCHEDULER_USER:-dev}"
if ! id "$GIIP_RUNTIME_USER" >/dev/null 2>&1; then
  if useradd -m -s /bin/bash "$GIIP_RUNTIME_USER" 2>/dev/null; then
    echo "[entrypoint] created runtime user '$GIIP_RUNTIME_USER'"
  else
    echo "[entrypoint] WARN: 사용자 '$GIIP_RUNTIME_USER' 를 만들 수 없어 root 로 돌립니다 — claude 가 root 에서 거부되어 slack-bot/scheduler 가 실패합니다"
    GIIP_RUNTIME_USER="root"
  fi
fi
if [ "$GIIP_RUNTIME_USER" = "root" ]; then
  GIIP_RUNTIME_HOME="/root"
else
  GIIP_RUNTIME_HOME="$(getent passwd "$GIIP_RUNTIME_USER" | cut -d: -f6)"
fi

# ── slack-bot (optional — only if Slack tokens are supplied) ──
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_APP_TOKEN:-}" ]; then
  SLACK_STATUS="on (pm2 giipclaude-bot, user: $GIIP_RUNTIME_USER)"
  echo "[entrypoint] starting slack-bot via pm2 (user: $GIIP_RUNTIME_USER)"
  if [ "$GIIP_RUNTIME_USER" = "root" ]; then
    (cd "$REPO_DIR/slack-bot" && npm install --omit=dev --no-audit --no-fund)
    (cd "$REPO_DIR/slack-bot" && pm2 start index.js --name giipclaude-bot --time)
  else
    [ -f "$GIIP_RUNTIME_HOME/.claude/.credentials.json" ] || echo "[entrypoint] WARN: $GIIP_RUNTIME_USER 의 claude 로그인 정보($GIIP_RUNTIME_HOME/.claude/.credentials.json)가 없습니다 — 'docker exec -it -u $GIIP_RUNTIME_USER <컨테이너> claude' 로 한 번 로그인해야 slack-bot 이 답변을 생성할 수 있습니다"
    # 최초 기동 시 repo 는 root 로 clone 되어 slack-bot/ 이 root 소유일 수 있다 — 스케줄러 블록
    # 끝의 fix-root-owned.sh(전체 /work)는 이 블록보다 뒤에 돌므로, slack-bot 디렉터리만 선제
    # 회수한다(그래야 아래 npm install 이 이 사용자 권한으로 쓸 수 있다).
    [ -f "$REPO_DIR/scripts/fix-root-owned.sh" ] && bash "$REPO_DIR/scripts/fix-root-owned.sh" "$REPO_DIR/slack-bot" "$GIIP_RUNTIME_USER" >/dev/null 2>&1 || true
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$GIIP_RUNTIME_USER" -- env HOME="$GIIP_RUNTIME_HOME" sh -c "cd '$REPO_DIR/slack-bot' && npm install --omit=dev --no-audit --no-fund && pm2 start index.js --name giipclaude-bot --time"
    else
      su -s /bin/sh "$GIIP_RUNTIME_USER" -c "cd '$REPO_DIR/slack-bot' && npm install --omit=dev --no-audit --no-fund && pm2 start index.js --name giipclaude-bot --time"
    fi
  fi
else
  SLACK_STATUS="off (SLACK_BOT_TOKEN/SLACK_APP_TOKEN 미설정)"
  echo "[entrypoint] SLACK_BOT_TOKEN/SLACK_APP_TOKEN not set — skipping slack-bot"
fi

# ── hourly-issue-scheduler (optional — cron replaces Windows Task Scheduler) ──
if [ "${GIIP_ENABLE_SCHEDULER:-true}" = "true" ]; then
  SCHED_STATUS="on (:07/:27/:47, pwsh)"
  ONLY_CSN_ARG=""
  if [ -n "${EFFECTIVE_CSN:-}" ]; then
    ONLY_CSN_ARG=" -OnlyCsn ${EFFECTIVE_CSN}"
  fi
  # 실행 이력(tSchedulerAgentRun)은 run-gissue-claude.ps1 이 직접 기록한다(giip #3563: lib/scheduler-state.ps1). 예전(giip #3575)에는 bash 래퍼로
  # 감싸 giipAgentLinux 의 sar_run_* 를 부르는 우회를 썼으나, 근본 원인은 PowerShell 이 bash 함수를 못 불러서가 아니라 호출 형식(sk/proc → token/text)
  # 오류였고, 래퍼는 `exec` 때문에 종료 trap 이 안 돌아 이력이 RUNNING 으로 남고 박스 에이전트 아래에 섞였다. 그래서 래퍼를 쓰지 않는다.
  # giip 3615: 소프트 예산 — "새 이슈를 시작해도 되는 시간(분)". cron 이 20분 주기라서, 큐가 빌 때까지 90분+ 도는 실행 하나가 락을 쥐고 있으면
  # 그동안의 틱이 전부 "SKIP: 실행 중"으로 버려진다. 15분이 지나면 새 이슈를 집지 않고(진행 중 이슈는 끝까지), 다음 틱이 이어받는다.
  # 기본 15분(20분 주기의 약 3/4). 컨테이너 환경변수 GISSUE_SOFT_BUDGET_MIN 으로 바꾸고 0 이면 끈다. 숫자가 아니면 15.
  # 이미지 재빌드 없이 쓰려면 scripts/gissue/csn-projects.json 최상위 "softBudgetMin" 에 적는다(이 값이 환경변수보다 우선, 0 이면 끔).
  # ⚠️ 이 entrypoint 변경(기본값 15 주입)은 이미지 재빌드가 필요하다. 재빌드 전에는 csn-projects.json 키만 효과가 있다.
  SOFT_BUDGET_MIN="${GISSUE_SOFT_BUDGET_MIN:-15}"
  [[ "$SOFT_BUDGET_MIN" =~ ^[0-9]+$ ]] || SOFT_BUDGET_MIN=15
  CRON_CMD="GISSUE_SOFT_BUDGET_MIN=${SOFT_BUDGET_MIN} pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/run-gissue-claude.ps1\"${ONLY_CSN_ARG} >> $REPO_DIR/scripts/gissue/logs/cron.log 2>&1"
  # giip #3535: 스케줄러 cron 은 root 가 아니라 일반 사용자로 돌려야 한다. 엔진이 `claude -p --dangerously-skip-permissions` 를
  # 부르는데 claude 는 root/sudo 에서 이 옵션을 거부한다("--dangerously-skip-permissions cannot be used with root/sudo privileges").
  # root 로 돌리면 이슈를 "집는" 것처럼 로그만 남고 모든 이슈가 즉시 실패해 큐가 영원히 줄지 않는다(out.log 에서 788회 실측).
  # 같은 이유로 docs/60-operations/docker-dev-user-and-sudo.md 도 인스턴스에서는 dev 로 claude 를 돌리라고 한다.
  # giip #4231: slack-bot 블록에서 이미 만든 사용자를 그대로 재사용한다 — 두 곳이 서로 다른 사용자를
  # 만들면 claude 로그인 정보가 흩어져 한쪽은 항상 미인증 상태가 된다.
  SCHED_USER="$GIIP_RUNTIME_USER"
  if [ "$SCHED_USER" != "root" ]; then
    SCHED_HOME="$GIIP_RUNTIME_HOME"
    [ -f "$SCHED_HOME/.claude/.credentials.json" ] || echo "[entrypoint] WARN: $SCHED_USER 의 claude 로그인 정보($SCHED_HOME/.claude/.credentials.json)가 없습니다 — 'docker exec -it -u $SCHED_USER <컨테이너> claude' 로 한 번 로그인해야 스케줄러가 이슈를 처리합니다"
    # 이 사용자가 저장소/로그/lock 에 쓸 수 있어야 한다(root 로 만든 파일 회수).
    [ -f "$REPO_DIR/scripts/fix-root-owned.sh" ] && bash "$REPO_DIR/scripts/fix-root-owned.sh" >/dev/null 2>&1 || true
  fi
  {
    echo "SHELL=/bin/bash"
    # docker 는 프로젝트(CSN)마다 컨테이너를 따로 띄우므로 컨테이너당 스케줄러를 20분마다(:07/:27/:47) 돌린다.
    # 이전 실행이 아직 돌고 있으면 CSN lock 으로 SKIP 되어 겹치지 않는다(run-gissue-claude.ps1 Phase 1).
    echo "7,27,47 * * * * $SCHED_USER cd $REPO_DIR && $CRON_CMD"
  } > /etc/cron.d/gissue-scheduler
  chmod 0644 /etc/cron.d/gissue-scheduler
  echo "[entrypoint] registered issue-scheduler cron (every 20 min: :07/:27/:47, pwsh) via /etc/cron.d"
  # giip 3617: admin/feedback AI 판정 cron(20분, :12/:32/:52 — 스케줄러 틱과 겹치지 않게). 스크립트는 csn-projects.json 의
  # pageFeedbackAnalyze.enabled 가 true 일 때만 동작하고(기본 비활성: "[SKIP] 비활성" 한 줄 후 종료), 켜기 전에는 DB 호출이 없다.
  # 스케줄러와 같은 사용자(GIIP_SCHEDULER_USER, 기본 dev)로 돈다. ⚠️ 이 변경은 이미지 재빌드가 필요하다.
  {
    echo "SHELL=/bin/bash"
    echo "12,32,52 * * * * $SCHED_USER cd $REPO_DIR && [ -f scripts/gissue/page-feedback-analyze.ps1 ] && pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/page-feedback-analyze.ps1\" >> $REPO_DIR/scripts/gissue/logs/feedback-analyze.log 2>&1"
  } > /etc/cron.d/gissue-feedback-analyzer
  chmod 0644 /etc/cron.d/gissue-feedback-analyzer
  echo "[entrypoint] registered feedback-analyzer cron (every 20 min: :12/:32/:52, pwsh) via /etc/cron.d"
  # giip 3659: tKVS 읽기모델 증분 이관 cron — giipAgent(* * * * *)·CQE(*/5)·page-feedback-analyze(:12/:32/:52)와
  # 동일한 HTTP POST giipApiSk2 디스패처 호출 방식. SK/엔드포인트는 giipAgent.cnf 에서 해석(exec-kvs-readmodel-sync.sh).
  # exec-kvs-readmodel-sync.sh 가 exit 0 으로 항상 끝나므로 cron 오류가 다른 작업에 영향 안 함.
  {
    echo "SHELL=/bin/bash"
    echo "* * * * * $SCHED_USER cd $REPO_DIR && [ -f scripts/exec-kvs-readmodel-sync.sh ] && bash scripts/exec-kvs-readmodel-sync.sh >> $REPO_DIR/scripts/gissue/logs/kvs-sync.log 2>&1"
  } > /etc/cron.d/giip-kvs-readmodel-sync
  chmod 0644 /etc/cron.d/giip-kvs-readmodel-sync
  echo "[entrypoint] registered KVS-readmodel-sync cron (every 1 min) via /etc/cron.d"
  # giip #3405: 방금 쓴 cron 의 -OnlyCsn 이 SSOT 와 일치하는지 재검증(요구사항 2 — cron ↔ csn-projects.json 가드)
  if [ -n "$SSOT_CSN" ]; then
    CRON_CSN="$(grep -oE '\-OnlyCsn [0-9]+' /etc/cron.d/gissue-scheduler | grep -oE '[0-9]+' || true)"
    if [ "$CRON_CSN" != "$SSOT_CSN" ]; then
      echo "[entrypoint] WARN: gissue-scheduler cron -OnlyCsn=$CRON_CSN != csn-projects.json csn=$SSOT_CSN"
      [ "${GIIP_STRICT_CSN:-false}" = "true" ] && { echo "[entrypoint] GIIP_STRICT_CSN=true — cron/SSOT 불일치로 기동 중단"; exit 1; }
    fi
  fi
else
  SCHED_STATUS="off (GIIP_ENABLE_SCHEDULER=false)"
  echo "[entrypoint] GIIP_ENABLE_SCHEDULER=false — skipping scheduler cron"
fi

# ── giip agent (optional — makes this container a live, checkable lssn in GIIP web) ──
# "docker instance 생성" 시점까지는 GIIP web이 컨테이너 상태를 전혀 모른다(giip 2665 후속 요청:
# "giip는 어떤 인프라도 통신해서 체크할 수 있는 구조여야 해"). giipAgentLinux(별도 공식 레포)를
# 여기서 clone/구성해 매분 폴링시키면, 이 컨테이너가 자기 CSN 아래 lssn 하나로 등록되고,
# lsvrlist/lsvrdetail(giipv3)에서 heartbeat(tLSvr.lsChkdt)로 "지금 살아있는지"를 그대로 볼 수 있다
# — 새 상태 화면을 만든 게 아니라 이미 있는 서버 모니터링 화면을 그대로 재사용한다.
#
# giipAgent.cnf 의 SK 는 giip-fde-agent 가 먼저 설치되며 materialize 한 정본
# (slack-bot/.secrets/giip-accounts.json)에서 SSOT CSN(EFFECTIVE_CSN)으로 파생한다(lib/ssot-sk.js).
# GIIP_SK 환경변수는 최초 부팅 seed 일 뿐이라 클론+CSN 교체 후 stale 될 수 있으므로, 정본에서
# 끌어오는 쪽을 우선하고 못 구하면 GIIP_SK 로 폴백한다 — ssot-csn.js 가 CSN 에 대해 하는 역할의 SK 판.
# CSN 은 코드에 박지 않고 EFFECTIVE_CSN(=SSOT) 을 그대로 넘긴다.
AGENT_SK=""
GIIP_ACCOUNTS_FILE="$REPO_DIR/slack-bot/.secrets/giip-accounts.json"
if [ -n "${EFFECTIVE_CSN:-}" ] && [ -f "$GIIP_ACCOUNTS_FILE" ]; then
  AGENT_SK="$(node "$REPO_DIR/scripts/gissue/lib/ssot-sk.js" "$GIIP_ACCOUNTS_FILE" "$EFFECTIVE_CSN" 2>/dev/null || true)"
fi
if [ -n "$AGENT_SK" ]; then
  echo "[entrypoint] giipAgent SK: giip-fde-agent 정본에서 파생(giip-accounts.json, csn=$EFFECTIVE_CSN)"
else
  AGENT_SK="${GIIP_SK:-}"
  [ -n "$AGENT_SK" ] && echo "[entrypoint] giipAgent SK: SSOT 미해결 — GIIP_SK(env) 폴백 사용"
fi

if [ "${GIIP_ENABLE_AGENT:-true}" = "true" ] && [ -n "$AGENT_SK" ]; then
  GIIP_AGENT_DIR="${GIIP_AGENT_DIR:-/work/giipAgentLinux}"
  GIIP_AGENT_URL="${GIIP_AGENT_URL:-https://github.com/LowyShin/giipAgentLinux.git}"
  GIIP_AGENT_CNF="$(dirname "$GIIP_AGENT_DIR")/giipAgent.cnf"

  echo "[entrypoint] giip agent: $GIIP_AGENT_URL -> $GIIP_AGENT_DIR"
  if [ -d "$GIIP_AGENT_DIR/.git" ]; then
    safe_update_repo "$GIIP_AGENT_DIR" main "giipAgentLinux"
  else
    # giip #2855 T2: .git 이 없는데 디렉터리가 비어있지 않게 남아 있으면 `git clone` 이
    # "destination path ... already exists and is not an empty directory" 로 거부하고, 5행
    # set -euo pipefail 때문에 entrypoint 가 그 자리에서 종료한다 → 한 번 이 상태(예: 과거의
    # phantom log/ 잔해)에 빠지면 원인을 고쳐 재기동해도 스스로 회복하지 못했다(이 이슈의 핵심).
    # 사용자 데이터일 수 있으므로 조용히 지우지 않고, 타임스탬프 백업으로 退避(rename)한 뒤 clone
    # 한다 — 무엇을 왜 했는지 로그에 남긴다(ls -A 로 비어있는지 판정).
    if [ -d "$GIIP_AGENT_DIR" ] && [ -n "$(ls -A "$GIIP_AGENT_DIR" 2>/dev/null)" ]; then
      GIIP_AGENT_BAK="${GIIP_AGENT_DIR}.bak-$(date +%Y%m%d%H%M%S)"
      echo "[entrypoint] WARN: $GIIP_AGENT_DIR 에 .git 이 없는데 비어있지 않습니다(이전 기동의 잔해로 추정). clone 이 'not an empty directory' 로 거부되어 기동이 멈추는 것을 막기 위해 $GIIP_AGENT_BAK 로 退避(rename)합니다 — 데이터는 지우지 않았습니다. 불필요하면 사람이 그 백업 경로를 삭제하십시오."
      mv "$GIIP_AGENT_DIR" "$GIIP_AGENT_BAK"
    fi
    git clone --branch main "$GIIP_AGENT_URL" "$GIIP_AGENT_DIR"
  fi
  mkdir -p "$GIIP_AGENT_DIR/log"
  AGENT_CRON_LOG="$GIIP_AGENT_DIR/log/cron.log"   # giip #2855 T1: tail 대상에 조건부로 넣는다(하드코딩 금지)

  if [ ! -f "$GIIP_AGENT_CNF" ]; then
    # lssn=0 → giipAgent3.sh 첫 실행 시 자기 CSN 아래 새 lssn으로 자동 등록되고, 발급받은 lssn을
    # 이 파일에 다시 써서 재기동해도 같은 lssn을 재사용한다 — 그래서 이 파일이 /work(영속 볼륨)
    # 밑에 있어야 한다(docker-compose.yml의 볼륨이 /work 전체를 덮는 이유).
    # GIIP_LSSN이 있으면 우선 사용 (giip 2857): 양의 정수면 그 값, 아니면 0 (하위호환)
    lssn_val="0"
    if [ -n "${GIIP_LSSN:-}" ]; then
      if [[ "$GIIP_LSSN" =~ ^[1-9][0-9]*$ ]]; then
        lssn_val="$GIIP_LSSN"
        echo "[entrypoint] GIIP_LSSN=$GIIP_LSSN is valid — using it"
      else
        echo "[entrypoint] GIIP_LSSN=$GIIP_LSSN is invalid (not a positive integer) — using default lssn=0"
      fi
    fi
    cat > "$GIIP_AGENT_CNF" <<CNFEOF
sk="$AGENT_SK"
lssn="$lssn_val"
giipagentdelay="60"
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddr="https://giipasp.azurewebsites.net"
CNFEOF
    echo "[entrypoint] wrote $GIIP_AGENT_CNF (lssn=$lssn_val)"
  else
    # 이미 있는 cnf 의 sk 가 SSOT 정본과 어긋나면(클론+CSN/SK 교체 후 stale) SSOT 값으로 갱신한다.
    # lssn 등 다른 줄은 보존하고 sk= 줄만 교체하며, 내용만 덮어써 inode 를 유지한다
    # (giipAgent.cnf 를 단일 파일 bind mount 해도 깨지지 않게 — persist_lssn 과 같은 이유).
    cur_sk="$(grep -oE '^sk="?[^"]*"?' "$GIIP_AGENT_CNF" | head -1 | sed -E 's/^sk="?([^"]*)"?/\1/')"
    if [ -n "$AGENT_SK" ] && [ "$cur_sk" != "$AGENT_SK" ]; then
      echo "[entrypoint] WARN: $GIIP_AGENT_CNF 의 sk 가 SSOT(csn=$EFFECTIVE_CSN) 와 다릅니다"
      if [ "${GIIP_STRICT_CSN:-false}" = "true" ]; then
        echo "[entrypoint] GIIP_STRICT_CSN=true — giipAgent.cnf sk/SSOT 불일치로 기동 중단"; exit 1
      fi
      tmp_cnf="$(mktemp)"
      sed -E "s|^sk=.*|sk=\"$AGENT_SK\"|" "$GIIP_AGENT_CNF" > "$tmp_cnf"
      cat "$tmp_cnf" > "$GIIP_AGENT_CNF"
      rm -f "$tmp_cnf"
      echo "[entrypoint] $GIIP_AGENT_CNF sk 를 SSOT 정본 값으로 갱신(lssn 등 보존)"
    else
      echo "[entrypoint] $GIIP_AGENT_CNF already exists — sk 가 SSOT 와 일치(또는 SSOT 미해결) — 그대로 둠"
    fi
  fi

  agent_cron_line "$GIIP_AGENT_DIR" > /etc/cron.d/giip-agent
  chmod 0644 /etc/cron.d/giip-agent
  if command -v flock >/dev/null 2>&1; then
    echo "[entrypoint] giip-agent cron: single-instance guard (flock) on"
  else
    echo "[entrypoint] giip-agent cron: single-instance guard (flock) off"
  fi
  echo "[entrypoint] registered giipAgentLinux cron (every 1 min)"

  # giip #2949: CQE (Command Queue Engine) poller — 같은 giipAgent Linux 환경 사용
  # giipCQE.sh는 ../giipAgent.cnf (=$GIIP_AGENT_DIR의 부모 = /work/giipAgent.cnf)에서 설정 읽음
  mkdir -p /tmp/giip_cqe_logs
  echo "*/5 * * * * root cd $GIIP_AGENT_DIR && bash cqe/giipCQE.sh >> /tmp/giip_cqe_logs/cqe_cron.log 2>&1" > /etc/cron.d/giip-cqe
  chmod 0644 /etc/cron.d/giip-cqe
  echo "[entrypoint] registered giipCQE.sh cron (every 5 min)"
  AGENT_STATUS="on (giipAgentLinux + CQE, csn=$EFFECTIVE_CSN)"
else
  # giip #2855 T4: 건너뛴 사유를 요약 블록에서 구분해 보여준다(SK 미해결 vs. 명시적 비활성).
  if [ "${GIIP_ENABLE_AGENT:-true}" != "true" ]; then
    AGENT_STATUS="off (GIIP_ENABLE_AGENT=false)"
  else
    AGENT_STATUS="off (SK 미해결 — SSOT giip-accounts.json / GIIP_SK 모두 없음)"
  fi
  echo "[entrypoint] GIIP_ENABLE_AGENT=false or no SK resolvable (SSOT giip-accounts.json / GIIP_SK) — skipping giip agent (container state will not be visible in GIIP web)"
fi

# cron.d 파일이 하나라도 등록됐으면 cron 데몬을 한 번만 기동한다(중복 기동은 lock 에러).
if ls /etc/cron.d/* >/dev/null 2>&1; then
  cron
  echo "[entrypoint] cron daemon started"
fi

# giip #3405: 최종 3개 스케줄(giip-agent/giip-cqe/gissue-scheduler)의 CSN 정합성 자기점검(비차단).
# 경고만 출력하고 컨테이너는 계속 뜬다 — GIIP_STRICT_CSN=true 면 위 개별 가드에서 이미 기동을 막는다.
if [ -f "$REPO_DIR/scripts/gissue/check-csn-consistency.sh" ]; then
  bash "$REPO_DIR/scripts/gissue/check-csn-consistency.sh" || echo "[entrypoint] WARN: CSN 정합성 점검에서 경고가 있습니다(위 로그 확인)."
fi

# 인스턴스 부트스트랩(멱등): root 소유 파일 회수, powershell 링크, SqlServer 모듈, 허브 저장소, dbconfig.json, 환경 점검.
# 인스턴스를 어디서 새로 띄워도 같은 상태가 되게 한다(docs/60-operations/docker-instance-setup-rules.md §인스턴스 부트스트랩).
# 스케줄러 회차 끝에서는 그중 root 파일 회수(fix-root-owned.sh)만 돈다. 실패해도 기동은 계속한다.
if [ -f "$REPO_DIR/scripts/bootstrap-instance.sh" ]; then
  bash "$REPO_DIR/scripts/bootstrap-instance.sh" || echo "[entrypoint] WARN: bootstrap-instance.sh 실패(무시)"
fi

# giip #2855 T4: 기동 요약 — 이번 기동에서 무엇이 켜졌는지 한 블록으로. "giip agent: on|off + 사유"
# 를 포함해, 사용자가 "왜 lsvrlist 에 안 뜨나" 를 이 블록만 보고 판정할 수 있게 한다.
echo "[entrypoint] summary:"
echo "[entrypoint]   slack-bot: $SLACK_STATUS"
echo "[entrypoint]   scheduler: $SCHED_STATUS"
echo "[entrypoint]   giip agent: $AGENT_STATUS"
echo "[entrypoint]   fetch: $FETCH_STATUS"

echo "[entrypoint] ready. tailing logs."
touch "$REPO_DIR/scripts/gissue/logs/cron.log"
# giip #2855 T1: 블록 밖에서 /work/giipAgentLinux/log 를 무조건 만들던 줄을 제거했다(에이전트를 안
# 쓰는 구성에서 "빈 껍데기" 디렉터리가 생겨 다음 clone 을 막던 원인). agent log 는 에이전트 블록이
# 실제로 돌아 AGENT_CRON_LOG 이 세팅됐을 때만 tail 대상에 넣는다. REPO 로그는 바로 위 touch 로 존재가
# 보장되므로 tail 인자가 0개가 되는 일은 없다(인자 0개면 tail 이 usage 오류로 죽는다).
TAIL_TARGETS=("$REPO_DIR/scripts/gissue/logs/cron.log")
if [ -n "$AGENT_CRON_LOG" ]; then
  TAIL_TARGETS+=("$AGENT_CRON_LOG")
fi
TAIL_TARGETS+=("$GIIP_RUNTIME_HOME/.pm2/logs/giipclaude-bot-out.log" "$GIIP_RUNTIME_HOME/.pm2/logs/giipclaude-bot-error.log")
# 어떤 파일이 tail 대상인지(존재 여부 포함) 남긴다 — tail -F 는 없는 파일도 받지만 2>/dev/null 이 경고를 숨기므로.
for _t in "${TAIL_TARGETS[@]}"; do
  if [ -f "$_t" ]; then echo "[entrypoint]   tail + $_t (존재)"; else echo "[entrypoint]   tail + $_t (아직 없음 — tail -F 가 생성되면 따라감)"; fi
done
exec tail -F "${TAIL_TARGETS[@]}" 2>/dev/null
