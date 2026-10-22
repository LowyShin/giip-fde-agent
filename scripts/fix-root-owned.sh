#!/usr/bin/env bash
# fix-root-owned.sh — /work 아래 root 소유 파일을 작업 사용자(기본 dev)로 되돌린다(giip #3535).
#
# 왜: docker 인스턴스는 root 로 기동하고 gissue 스케줄러 cron 도 root 로 돈다. 그 안의 git/claude/스크립트가 만든 파일이
#   root 소유로 남아, dev 로 접속한 세션이 AGENTS.md, README.md, INDEX.md 등을 편집할 때 Permission denied 가 났다.
# 언제 도나: (1) 컨테이너 기동 시 entrypoint.sh, (2) 스케줄러 회차 끝(run-gissue-claude.ps1) — 새로 생긴 root 파일을 즉시 회수.
# 안전: 멱등, 소유자만 바꾼다(내용/권한 불변). node_modules 와 다른 파일시스템(-xdev)은 건드리지 않는다. root 가 아니면 sudo -n 으로 시도하고 안 되면 조용히 종료.
# 사용: bash scripts/fix-root-owned.sh [기준디렉터리=/work] [사용자=dev]    (환경변수 GIIP_FIX_BASE / GIIP_FIX_USER 도 가능)
BASE="${1:-${GIIP_FIX_BASE:-/work}}"
USER_NAME="${2:-${GIIP_FIX_USER:-dev}}"

id "$USER_NAME" >/dev/null 2>&1 || { echo "[fix-root-owned] SKIP: 사용자 '$USER_NAME' 없음"; exit 0; }
[ -d "$BASE" ] || { echo "[fix-root-owned] SKIP: $BASE 없음"; exit 0; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && SUDO="sudo -n" || { echo "[fix-root-owned] SKIP: root 권한 없음"; exit 0; }
fi

GROUP_NAME="$(id -gn "$USER_NAME")"
COUNT="$($SUDO find "$BASE" -xdev -user root -not -path '*/node_modules/*' 2>/dev/null | wc -l)"
if [ "$COUNT" -gt 0 ]; then
  $SUDO find "$BASE" -xdev -user root -not -path '*/node_modules/*' -exec chown -h "$USER_NAME:$GROUP_NAME" {} + 2>/dev/null
fi
echo "[fix-root-owned] $BASE: root 소유 ${COUNT}개를 $USER_NAME:$GROUP_NAME 로 변경"
exit 0
