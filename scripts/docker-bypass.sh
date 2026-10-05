#!/bin/sh
# docker-bypass.sh — 새 docker 인스턴스에서 giip-fde-agent 를 clone 한 뒤 실행하는 기동 스크립트.
#
# 하는 일:
#   1. root 로 실행되면 일반 사용자(기본 dev)를 만들고 이 저장소 소유권을 넘긴다.
#      (claude 는 root 에서 --dangerously-skip-permissions 를 거부한다)
#      root 소유인 /work 전체와 시작 디렉토리(FDE_GRANT_DIRS)는 소유자를 바꾸지 않고, 그 사용자를
#      root 그룹에 넣은 뒤 그룹 읽기/쓰기 권한을 부여해서 읽고 쓸 수 있게 한다.
#   2. 그 사용자로 전환해서, remote-control 을 쓰는 경우 claude.ai 로그인 여부를 먼저 확인한다.
#      (미로그인이면 claude auth login 을 먼저 실행)
#   3. claude 를 bypass + remote-control 옵션으로 실행한다.
#
# 사용:
#   git clone <giip-fde-agent> && cd giip-fde-agent && sh scripts/docker-bypass.sh
#   claude 의 시작 디렉토리는 스크립트를 기동한 현재 위치(pwd)다. 다른 폴더에서 시작하려면:
#   cd /work/giipprj-hub && sh /work/giip-fde-agent/scripts/docker-bypass.sh
#
# 환경변수:
#   FDE_USER            전환할 일반 사용자 이름 (기본 dev)
#   FDE_REMOTE_CONTROL  1(기본)=remote-control 사용, 0=끔
#   FDE_MODE            interactive(기본) | server
#                         interactive: claude --dangerously-skip-permissions --remote-control
#                         server     : claude remote-control --permission-mode bypassPermissions
#   FDE_RC_NAME         remote-control 세션 이름 (기본 giip-fde-agent-<hostname>)
#   FDE_GRANT_DIRS      일반 사용자에게 읽기/쓰기 권한을 줄 디렉토리 목록, 공백 구분
#                       기본: /work (있으면) + 시작 디렉토리(/work 밖일 때)
#                       예) FDE_GRANT_DIRS="/work /data/repos"
#
# 주의: remote-control 은 claude.ai 계정 로그인(claude auth login)이 필요하다.
#       API key / setup-token 은 지원되지 않는다. 로그인은 이 스크립트가 전환한 사용자의 홈에 저장된다.
#       (root 의 로그인은 쓰이지 않는다.) 미로그인 상태로 claude 가 기동되면 /remote-control 명령이
#       등록되지 않아 "Unknown command" 가 되므로, 기동 전에 로그인을 확인한다.

set -eu

FDE_USER="${FDE_USER:-dev}"
FDE_REMOTE_CONTROL="${FDE_REMOTE_CONTROL:-1}"
FDE_MODE="${FDE_MODE:-interactive}"
FDE_RC_NAME="${FDE_RC_NAME:-giip-fde-agent-$(hostname)}"
SELF_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # scripts/ 의 상위 = 저장소 루트
SELF_PATH="$SELF_DIR/scripts/$(basename "$0")"
WORK_DIR="$(pwd)"                              # 스크립트를 기동한 위치 = claude 시작 디렉토리
if [ -z "${FDE_GRANT_DIRS:-}" ]; then
  # 인스턴스의 작업 루트(/work) 하위는 모두 root 소유이므로 통째로 대상에 넣는다
  FDE_GRANT_DIRS="$WORK_DIR"
  if [ -d /work ]; then
    case "$WORK_DIR/" in
      /work/*) FDE_GRANT_DIRS="/work" ;;
      *)       FDE_GRANT_DIRS="/work $WORK_DIR" ;;
    esac
  fi
fi

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

# remote-control 은 claude.ai 로그인 상태로 기동해야 한다. 현재 사용자의 로그인을 확인하고 없으면 로그인시킨다.
ensure_login() {
  [ "$FDE_REMOTE_CONTROL" = "1" ] || return 0
  if claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"'; then
    return 0
  fi
  log "$(id -un) 사용자가 claude.ai 에 로그인되어 있지 않습니다 → claude auth login"
  claude auth login || die "claude.ai 로그인 실패 (remote-control 에 필요)"
  claude auth status 2>/dev/null | grep -q '"authMethod": *"claude.ai"' \
    || die "claude.ai 로그인이 확인되지 않습니다 (API key / setup-token 은 remote-control 미지원)"
}

# ---- 1) root 가 아니면 이미 일반 사용자: 로그인 확인 후 실행 ----
if [ "$(id -u)" != "0" ]; then
  command -v claude >/dev/null 2>&1 || die "claude 를 찾을 수 없습니다 (PATH 확인 / 설치 필요)"
  cd "$WORK_DIR"
  ensure_login
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

HOME_DIR="$(getent passwd "$FDE_USER" 2>/dev/null | cut -d: -f6 || true)"
HOME_DIR="${HOME_DIR:-/home/$FDE_USER}"

# 일반 사용자 권한으로 셸 명령 한 줄 실행
run_as() {
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$FDE_USER" -- env HOME="$HOME_DIR" sh -c "$1"
  else
    su "$FDE_USER" -s /bin/sh -c "HOME='$HOME_DIR'; export HOME; $1"
  fi
}

# ---- 5) root 소유 디렉토리 읽기/쓰기 권한 부여 (소유자는 유지) ----
# 소유자를 바꾸면 root 쪽 git 이 "dubious ownership" 으로 막히므로, root 그룹 + 그룹 rw 로 처리한다.
ROOT_GROUP="$(getent group 0 2>/dev/null | cut -d: -f1 || true)"
ROOT_GROUP="${ROOT_GROUP:-root}"
if ! id -Gn "$FDE_USER" | tr ' ' '\n' | grep -qx "$ROOT_GROUP"; then
  log "그룹 추가: $FDE_USER → $ROOT_GROUP"
  if command -v usermod >/dev/null 2>&1; then
    usermod -aG "$ROOT_GROUP" "$FDE_USER"
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup "$FDE_USER" "$ROOT_GROUP"
  else
    die "usermod/addgroup 가 없어 $FDE_USER 를 $ROOT_GROUP 그룹에 넣을 수 없습니다"
  fi
fi
for d in $FDE_GRANT_DIRS; do
  [ -d "$d" ] || { log "권한 부여 건너뜀(디렉토리 아님): $d"; continue; }
  d="$(cd "$d" && pwd)"
  case "$d" in
    /|/root|/etc|/usr|/bin|/sbin|/lib|/var|/home) die "시스템 디렉토리에는 권한을 부여하지 않습니다: $d" ;;
  esac
  [ "$d" = "$SELF_DIR" ] && continue          # 4) 에서 이미 소유권 이전됨
  [ "$d" = "$HOME_DIR" ] && continue          # 사용자 홈은 원래 본인 소유
  log "읽기/쓰기 권한 부여: $d (그룹 $ROOT_GROUP, 소유자 유지)"
  chgrp -R "$ROOT_GROUP" "$d"
  chmod -R g+rwX "$d"
  # 소유자가 다른 저장소에서도 일반 사용자의 git 이 동작하도록 등록
  # (대상 디렉토리 자체와, 그 바로 아래의 저장소들)
  if command -v git >/dev/null 2>&1; then
    for r in "$d" "$d"/*; do
      [ -e "$r/.git" ] || continue
      run_as "git config --global --get-all safe.directory | grep -qxF '$r' || git config --global --add safe.directory '$r'"
    done
  fi
done

# ---- 6) 일반 사용자로 전환해 이 스크립트를 다시 실행 (1) 의 경로로 로그인 확인 → claude 기동) ----
CMD="$(build_cmd)"
log "실행(${FDE_USER}): $CMD"
export FDE_USER FDE_REMOTE_CONTROL FDE_MODE FDE_RC_NAME

if command -v runuser >/dev/null 2>&1; then
  exec runuser -u "$FDE_USER" -- env HOME="$HOME_DIR" sh -c "cd '$WORK_DIR' && exec sh '$SELF_PATH'"
elif command -v su >/dev/null 2>&1; then
  exec su "$FDE_USER" -s /bin/sh -c "HOME='$HOME_DIR'; export HOME; cd '$WORK_DIR' && exec sh '$SELF_PATH'"
else
  die "runuser/su 가 없어 사용자 전환이 불가능합니다"
fi
