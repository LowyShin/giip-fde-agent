#!/bin/sh
# setup-dev-sudo.sh — 일반 사용자(기본 dev)에게 비밀번호 없는 전체 sudo 권한을 준다.
#
# 반드시 root 로 실행해야 한다 (WSL: `wsl -u root`, docker: 기본 root).
# 하는 일:
#   1. sudo 가 없으면 설치 (apt-get / apk / dnf / yum)
#   2. /etc/sudoers.d/<user> 에 `<user> ALL=(ALL) NOPASSWD:ALL` 기록 (440, visudo 검증)
#   3. sudo/wheel 그룹에 사용자 추가
#
# 사용:   sh scripts/setup-dev-sudo.sh
# 환경변수: FDE_USER  대상 사용자 (기본 dev)
#
# 주의: 사실상 root 권한을 주는 것이다. 신뢰할 수 있는 개인 개발/인스턴스 환경에서만 쓴다.

set -eu

FDE_USER="${FDE_USER:-dev}"

log() { echo "[setup-dev-sudo] $*"; }
die() { echo "[setup-dev-sudo] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "root 로 실행해야 합니다 (WSL: wsl -u root)"
id "$FDE_USER" >/dev/null 2>&1 || die "사용자 없음: $FDE_USER (먼저 scripts/docker-bypass.sh 또는 useradd 로 생성)"

# ---- 1) sudo 설치 ----
if ! command -v sudo >/dev/null 2>&1; then
  log "sudo 설치"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y sudo
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache sudo
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y sudo
  elif command -v yum >/dev/null 2>&1; then
    yum install -y sudo
  else
    die "지원하는 패키지 매니저가 없습니다. sudo 를 수동 설치하세요"
  fi
fi

# ---- 2) sudoers 드롭인 ----
mkdir -p /etc/sudoers.d
TMP="$(mktemp)"
echo "$FDE_USER ALL=(ALL) NOPASSWD:ALL" > "$TMP"
if command -v visudo >/dev/null 2>&1; then
  visudo -cf "$TMP" >/dev/null || { rm -f "$TMP"; die "sudoers 문법 검증 실패"; }
fi
install -m 440 -o root -g root "$TMP" "/etc/sudoers.d/$FDE_USER"
rm -f "$TMP"

# ---- 3) 그룹 추가 (있는 그룹만) ----
for g in sudo wheel; do
  if getent group "$g" >/dev/null 2>&1; then
    usermod -aG "$g" "$FDE_USER" 2>/dev/null || adduser "$FDE_USER" "$g" 2>/dev/null || true
    log "그룹 추가: $g"
  fi
done

log "완료: $FDE_USER 에 NOPASSWD sudo 부여. 새 셸/세션(Claude Code 재시작)부터 적용됩니다."
log "확인: su - $FDE_USER -c 'sudo -n true && echo OK'"
