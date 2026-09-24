#!/usr/bin/env bash
# giip-fde-agent container entrypoint: auto clone/pull, register csn/sk/login_id,
# start slack-bot (pm2) and the hourly-issue-scheduler (cron + pwsh).
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
  if [ -n "${GIIP_CSN:-}" ]; then
    ONLY_CSN_ARG=" -OnlyCsn ${GIIP_CSN}"
  fi
  CRON_CMD="pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/run-gissue-claude.ps1\"${ONLY_CSN_ARG} >> $REPO_DIR/scripts/gissue/logs/cron.log 2>&1"
  {
    echo "SHELL=/bin/bash"
    echo "7 * * * * root cd $REPO_DIR && $CRON_CMD"
  } > /etc/cron.d/gissue-scheduler
  chmod 0644 /etc/cron.d/gissue-scheduler
  echo "[entrypoint] registered hourly-issue-scheduler cron (:07, pwsh) via /etc/cron.d"
else
  echo "[entrypoint] GIIP_ENABLE_SCHEDULER=false — skipping scheduler cron"
fi

# ── giip agent (optional — makes this container a live, checkable lssn in GIIP web) ──
# "docker instance 생성" 시점까지는 GIIP web이 컨테이너 상태를 전혀 모른다(giip 2665 후속 요청:
# "giip는 어떤 인프라도 통신해서 체크할 수 있는 구조여야 해"). giipAgentLinux(별도 공식 레포)를
# 여기서 clone/구성해 매분 폴링시키면, 이 컨테이너가 자기 CSN 아래 lssn 하나로 등록되고,
# lsvrlist/lsvrdetail(giipv3)에서 heartbeat(tLSvr.lsChkdt)로 "지금 살아있는지"를 그대로 볼 수 있다
# — 새 상태 화면을 만든 게 아니라 이미 있는 서버 모니터링 화면을 그대로 재사용한다.
if [ "${GIIP_ENABLE_AGENT:-true}" = "true" ] && [ -n "${GIIP_SK:-}" ]; then
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
sk="$GIIP_SK"
lssn="$lssn_val"
giipagentdelay="60"
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddr="https://giipasp.azurewebsites.net"
CNFEOF
    echo "[entrypoint] wrote $GIIP_AGENT_CNF (lssn=$lssn_val)"
  else
    echo "[entrypoint] $GIIP_AGENT_CNF already exists — keeping it (may already hold an assigned lssn)"
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
  echo "[entrypoint] GIIP_ENABLE_AGENT=false or GIIP_SK not set — skipping giip agent (container state will not be visible in GIIP web)"
fi

# cron.d 파일이 하나라도 등록됐으면 cron 데몬을 한 번만 기동한다(중복 기동은 lock 에러).
if ls /etc/cron.d/* >/dev/null 2>&1; then
  cron
  echo "[entrypoint] cron daemon started"
fi

echo "[entrypoint] ready. tailing logs."
touch "$REPO_DIR/scripts/gissue/logs/cron.log"
mkdir -p /work/giipAgentLinux/log && touch /work/giipAgentLinux/log/cron.log
exec tail -F "$REPO_DIR/scripts/gissue/logs/cron.log" /work/giipAgentLinux/log/cron.log ~/.pm2/logs/giipclaude-bot-out.log ~/.pm2/logs/giipclaude-bot-error.log 2>/dev/null
