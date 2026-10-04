#!/bin/sh
# docker-bypass.sh — 새 docker 인스턴스에서 giip-fde-agent 를 clone 한 뒤 실행하는 기동 스크립트.
#
# 하는 일:
#   1. root 로 실행되면 일반 사용자(기본 dev)를 만들고 이 저장소 소유권을 넘긴다.
#      (claude 는 root 에서 --dangerously-skip-permissions 를 거부한다)
#   2. 그 사용자로 전환해서 claude 를 bypass + remote-control 옵션으로 실행한다.
#
# 사용:
#   git clone <giip-fde-agent> && cd giip-fde-agent && sh docker-bypass.sh
#
# 환경변수:
#   FDE_USER            전환할 일반 사용자 이름 (기본 dev)
#   FDE_REMOTE_CONTROL  1(기본)=remote-control 사용, 0=끔
#   FDE_MODE            interactive(기본) | server
#                         interactive: claude --dangerously-skip-permissions --remote-control
#                         server     : claude remote-control --permission-mode bypassPermissions
#   FDE_RC_NAME         remote-control 세션 이름 (기본 giip-fde-agent-<hostname>)
#
# 주의: remote-control 은 claude.ai 계정 로그인(claude auth login)이 필요하다.
#       API key / setup-token 은 지원되지 않는다. 로그인은 이 스크립트가 전환한 사용자의 홈에 저장된다.

set -eu

FDE_USER="${FDE_USER:-dev}"
FDE_REMOTE_CONTROL="${FDE_REMOTE_CONTROL:-1}"
FDE_MODE="${FDE_MODE:-interactive}"
FDE_RC_NAME="${FDE_RC_NAME:-giip-fde-agent-$(hostname)}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[docker-bypass] $*"; }
die() { echo "[docker-bypass] ERROR: $*" >&2; exit 1; }

build_cmd() {
  if [ "$FDE_MODE" = "server" ]; then
    if [ "$FDE_REMOTE_CONTROL" = "1" ]; then
      echo "claude remote-control --name \"$FDE_RC_NAME\" --permission-mode bypassPermissions"
    else
      die "FDE_MODE=server 는 remote-control 이 필수입니다 (FDE_REMOTE_CONTROL=1)"
    fi
  else
    if [ "$FDE_REMOTE_CONTROL" = "1" ]; then
      echo "claude --dangerously-skip-permissions --remote-control \"$FDE_RC_NAME\""
    else
      echo "claude --dangerously-skip-permissions"
    fi
  fi
}

# ---- 1) root 가 아니면 이미 일반 사용자: 바로 실행 ----
if [ "$(id -u)" != "0" ]; then
  command -v claude >/dev/null 2>&1 || die "claude 를 찾을 수 없습니다 (PATH 확인 / 설치 필요)"
  cd "$SELF_DIR"
  eval "exec $(build_cmd)"
fi

# ---- 2) root: 일반 사용자 생성 ----
if ! id "$FDE_USER" >/dev/null 2>&1; then
  log "사용자 생성: $FDE_USER"
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/sh "$FDE_USER"
  elif command -v adduser >/dev/null 2>&1; then
    # Alpine(busybox) 은 -D, Debian 은 --disabled-password
    if adduser --help 2>&1 | grep -q -- '--disabled-password'; then
      adduser --disabled-password --gecos "" "$FDE_USER"
    else
      adduser -D "$FDE_USER"
    fi
  else
    die "useradd/adduser 가 없습니다. shadow/adduser 패키지를 먼저 설치하세요"
  fi
fi

# ---- 3) claude 설치 확인 (없으면 npm 으로 시도) ----
if ! command -v claude >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    log "claude 미설치 → npm i -g @anthropic-ai/claude-code"
    npm i -g @anthropic-ai/claude-code
  else
    die "claude 와 npm 이 모두 없습니다. node/npm 또는 claude 를 먼저 설치하세요"
  fi
fi

# ---- 4) 저장소 소유권 이전 ----
log "소유권 이전: $SELF_DIR → $FDE_USER"
chown -R "$FDE_USER" "$SELF_DIR"

# ---- 5) 일반 사용자로 전환해 실행 ----
CMD="$(build_cmd)"
log "실행(${FDE_USER}): $CMD"
HOME_DIR="$(getent passwd "$FDE_USER" 2>/dev/null | cut -d: -f6 || true)"
HOME_DIR="${HOME_DIR:-/home/$FDE_USER}"

if command -v runuser >/dev/null 2>&1; then
  exec runuser -u "$FDE_USER" -- env HOME="$HOME_DIR" sh -c "cd '$SELF_DIR' && exec $CMD"
elif command -v su >/dev/null 2>&1; then
  exec su "$FDE_USER" -s /bin/sh -c "HOME='$HOME_DIR'; cd '$SELF_DIR' && exec $CMD"
else
  die "runuser/su 가 없어 사용자 전환이 불가능합니다"
fi
