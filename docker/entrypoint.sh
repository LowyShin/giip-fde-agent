#!/usr/bin/env bash
# giip-fde-agent container entrypoint: auto clone/pull, register csn/sk/login_id,
# start slack-bot (pm2) and the hourly-issue-scheduler (cron + pwsh; cron runs as the non-root scheduler user, see below).
# See docker/README.md for the full env var contract.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/work/giip-fde-agent}"
REPO_URL="${REPO_URL:-https://github.com/LowyShin/giip-fde-agent.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

echo "[entrypoint] repo: $REPO_URL ($REPO_BRANCH) -> $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" fetch origin "$REPO_BRANCH"
  git -C "$REPO_DIR" checkout "$REPO_BRANCH"
  git -C "$REPO_DIR" merge --ff-only "origin/$REPO_BRANCH"
  echo "[entrypoint] pulled latest ($(git -C "$REPO_DIR" rev-parse --short HEAD))"
else
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
  echo "[entrypoint] cloned ($(git -C "$REPO_DIR" rev-parse --short HEAD))"
fi

# ── optional: pull env from GIIP web (giip 2665 "Docker 생성") instead of per-field env vars ──
eval "$(/fetch-instance-env.sh)"

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

# ── slack-bot (optional — only if Slack tokens are supplied) ──
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_APP_TOKEN:-}" ]; then
  echo "[entrypoint] starting slack-bot via pm2"
  (cd "$REPO_DIR/slack-bot" && npm install --omit=dev --no-audit --no-fund)
  (cd "$REPO_DIR/slack-bot" && pm2 start index.js --name giipclaude-bot --time)
else
  echo "[entrypoint] SLACK_BOT_TOKEN/SLACK_APP_TOKEN not set — skipping slack-bot"
fi

# ── hourly-issue-scheduler (optional — cron replaces Windows Task Scheduler) ──
if [ "${GIIP_ENABLE_SCHEDULER:-true}" = "true" ]; then
  ONLY_CSN_ARG=""
  if [ -n "${EFFECTIVE_CSN:-}" ]; then
    ONLY_CSN_ARG=" -OnlyCsn ${EFFECTIVE_CSN}"
  fi
  # 실행 이력(tSchedulerAgentRun)은 run-gissue-claude.ps1 이 직접 기록한다(giip #3563: lib/scheduler-state.ps1). 예전(giip #3575)에는 bash 래퍼로
  # 감싸 giipAgentLinux 의 sar_run_* 를 부르는 우회를 썼으나, 근본 원인은 PowerShell 이 bash 함수를 못 불러서가 아니라 호출 형식(sk/proc → token/text)
  # 오류였고, 래퍼는 `exec` 때문에 종료 trap 이 안 돌아 이력이 RUNNING 으로 남고 박스 에이전트 아래에 섞였다. 그래서 래퍼를 쓰지 않는다.
  CRON_CMD="pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/run-gissue-claude.ps1\"${ONLY_CSN_ARG} >> $REPO_DIR/scripts/gissue/logs/cron.log 2>&1"
  # giip #3535: 스케줄러 cron 은 root 가 아니라 일반 사용자(dev)로 돌려야 한다. 엔진이 `claude -p --dangerously-skip-permissions` 를
  # 부르는데 claude 는 root/sudo 에서 이 옵션을 거부한다("--dangerously-skip-permissions cannot be used with root/sudo privileges").
  # root 로 돌리면 이슈를 "집는" 것처럼 로그만 남고 모든 이슈가 즉시 실패해 큐가 영원히 줄지 않는다(out.log 에서 788회 실측).
  # 같은 이유로 docs/60-operations/docker-dev-user-and-sudo.md 도 인스턴스에서는 dev 로 claude 를 돌리라고 한다.
  SCHED_USER="${GIIP_SCHEDULER_USER:-dev}"
  if ! id "$SCHED_USER" >/dev/null 2>&1; then
    if useradd -m -s /bin/bash "$SCHED_USER" 2>/dev/null; then
      echo "[entrypoint] created scheduler user '$SCHED_USER'"
    else
      echo "[entrypoint] WARN: 사용자 '$SCHED_USER' 를 만들 수 없어 root 로 스케줄러를 등록합니다 — claude 가 root 에서 거부되어 이슈가 처리되지 않습니다"
      SCHED_USER="root"
    fi
  fi
  if [ "$SCHED_USER" != "root" ]; then
    SCHED_HOME="$(getent passwd "$SCHED_USER" | cut -d: -f6)"
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
  # giip #3405: 방금 쓴 cron 의 -OnlyCsn 이 SSOT 와 일치하는지 재검증(요구사항 2 — cron ↔ csn-projects.json 가드)
  if [ -n "$SSOT_CSN" ]; then
    CRON_CSN="$(grep -oE '\-OnlyCsn [0-9]+' /etc/cron.d/gissue-scheduler | grep -oE '[0-9]+' || true)"
    if [ "$CRON_CSN" != "$SSOT_CSN" ]; then
      echo "[entrypoint] WARN: gissue-scheduler cron -OnlyCsn=$CRON_CSN != csn-projects.json csn=$SSOT_CSN"
      [ "${GIIP_STRICT_CSN:-false}" = "true" ] && { echo "[entrypoint] GIIP_STRICT_CSN=true — cron/SSOT 불일치로 기동 중단"; exit 1; }
    fi
  fi
else
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
    git -C "$GIIP_AGENT_DIR" fetch origin main
    git -C "$GIIP_AGENT_DIR" checkout main
    git -C "$GIIP_AGENT_DIR" merge --ff-only origin/main
  else
    git clone --branch main "$GIIP_AGENT_URL" "$GIIP_AGENT_DIR"
  fi
  mkdir -p "$GIIP_AGENT_DIR/log"

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

  echo "* * * * * root cd $GIIP_AGENT_DIR && bash giipAgent3.sh >> $GIIP_AGENT_DIR/log/cron.log 2>&1" > /etc/cron.d/giip-agent
  chmod 0644 /etc/cron.d/giip-agent
  echo "[entrypoint] registered giipAgentLinux cron (every 1 min)"

  # giip #2949: CQE (Command Queue Engine) poller — 같은 giipAgent Linux 환경 사용
  # giipCQE.sh는 ../giipAgent.cnf (=$GIIP_AGENT_DIR의 부모 = /work/giipAgent.cnf)에서 설정 읽음
  mkdir -p /tmp/giip_cqe_logs
  echo "*/5 * * * * root cd $GIIP_AGENT_DIR && bash cqe/giipCQE.sh >> /tmp/giip_cqe_logs/cqe_cron.log 2>&1" > /etc/cron.d/giip-cqe
  chmod 0644 /etc/cron.d/giip-cqe
  echo "[entrypoint] registered giipCQE.sh cron (every 5 min)"
else
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

# root 로 기동해 만들어진 root 소유 파일을 작업 사용자(dev)로 되돌린다(dev 세션의 Permission denied 방지).
# 스케줄러 회차 끝에서도 같은 스크립트가 돌아 이후 생기는 root 파일을 회수한다. 실패해도 기동은 계속한다.
if [ -f "$REPO_DIR/scripts/fix-root-owned.sh" ]; then
  bash "$REPO_DIR/scripts/fix-root-owned.sh" || echo "[entrypoint] WARN: fix-root-owned.sh 실패(무시)"
fi

echo "[entrypoint] ready. tailing logs."
touch "$REPO_DIR/scripts/gissue/logs/cron.log"
mkdir -p /work/giipAgentLinux/log && touch /work/giipAgentLinux/log/cron.log
exec tail -F "$REPO_DIR/scripts/gissue/logs/cron.log" /work/giipAgentLinux/log/cron.log ~/.pm2/logs/giipclaude-bot-out.log ~/.pm2/logs/giipclaude-bot-error.log 2>/dev/null
