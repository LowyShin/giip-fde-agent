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
  cron
else
  echo "[entrypoint] GIIP_ENABLE_SCHEDULER=false — skipping scheduler cron"
fi

echo "[entrypoint] ready. tailing logs."
touch "$REPO_DIR/scripts/gissue/logs/cron.log"
exec tail -F "$REPO_DIR/scripts/gissue/logs/cron.log" ~/.pm2/logs/giipclaude-bot-out.log ~/.pm2/logs/giipclaude-bot-error.log 2>/dev/null
