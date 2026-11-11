#!/usr/bin/env bash
# agent_cron_line 단위 테스트: entrypoint.sh 의 마커 구간만 source 한다. flock 유무는 PATH 조작으로 흉내낸다.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENTRY="$HERE/../entrypoint.sh"
FN="$(mktemp)"; T="$(mktemp -d)"; trap 'rm -rf "$FN" "$T"' EXIT
sed -n '/^# >>> agent-cron-line/,/^# <<< agent-cron-line/p' "$ENTRY" | tr -d '\r' > "$FN"
[ -s "$FN" ] || { echo "FAIL: marker block not found"; exit 1; }
# shellcheck disable=SC1090
source "$FN"
FAILS=0
ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; FAILS=$((FAILS+1)); }
D=/work/giipAgentLinux
OLD="* * * * * root cd $D && bash giipAgent3.sh >> $D/log/cron.log 2>&1"
NEW="* * * * * root cd $D && flock -n /dev/shm/giipAgent3.lock bash giipAgent3.sh >> $D/log/cron.log 2>&1"

# flock 있음: 가짜 flock 을 PATH 맨 앞에 둔다
mkdir -p "$T/with"; printf '#!/bin/sh\nexit 0\n' > "$T/with/flock"; chmod +x "$T/with/flock"
got="$(PATH="$T/with:$PATH" agent_cron_line "$D")"
[ "$got" = "$NEW" ] && ok "flock present -> guarded line" || bad "flock present: $got"
case "$got" in *"/tmp/"*) bad "lock must not be in /tmp";; *) ok "lock not in /tmp";; esac

# flock 없음: bash 가 있는 디렉터리만 PATH 로 쓰되 flock 은 링크하지 않는다
mkdir -p "$T/without"; ln -s "$(command -v bash)" "$T/without/bash"
got="$(PATH="$T/without" agent_cron_line "$D")"
[ "$got" = "$OLD" ] && ok "flock absent -> old line" || bad "flock absent: $got"

[ "$FAILS" = 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "$FAILS FAILED"; exit 1; }
