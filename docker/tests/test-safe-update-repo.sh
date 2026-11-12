#!/usr/bin/env bash
# safe_update_repo 단위 테스트: entrypoint.sh 의 마커 구간만 source 한다(entrypoint 전체는 실행 안 함).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENTRY="$HERE/../entrypoint.sh"
FN="$(mktemp)"
sed -n '/^# >>> safe_update_repo/,/^# <<< safe_update_repo/p' "$ENTRY" | tr -d '\r' > "$FN"
[ -s "$FN" ] || { echo "FAIL: marker block not found"; exit 1; }
# shellcheck disable=SC1090
source "$FN"

T="$(mktemp -d)"; trap 'rm -rf "$T" "$FN"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
FAILS=0
ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; FAILS=$((FAILS+1)); }

setup() { # $1 name -> creates $T/$1.git, $T/$1 (clone), $T/$1-w (pusher)
  git init -q --bare -b main "$T/$1.git"
  git clone -q "$T/$1.git" "$T/$1-w" 2>/dev/null
  git -C "$T/$1-w" checkout -q -b main 2>/dev/null || true
  printf 'base\n' > "$T/$1-w/f.txt"
  git -C "$T/$1-w" add f.txt; git -C "$T/$1-w" commit -q -m base
  git -C "$T/$1-w" push -q origin main
  git clone -q "$T/$1.git" "$T/$1" 2>/dev/null
}
upstream_commit() { printf 'upstream\n' > "$T/$1-w/f.txt"; git -C "$T/$1-w" commit -q -am up; git -C "$T/$1-w" push -q origin main; }

# (a) clean + new upstream commit
setup a; upstream_commit a
rc=0; out="$(safe_update_repo "$T/a" main t-a 2>&1)" || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$T/a/f.txt")" = "upstream" ] && echo "$out" | grep -q 'pulled latest' && ok "(a) clean repo updated, rc=0" || bad "(a) rc=$rc out=$out"

# (b) dirty tracked file also changed upstream
setup b; upstream_commit b
printf 'LOCAL EDIT\n' > "$T/b/f.txt"; cp "$T/b/f.txt" "$T/b.expect"
head_before="$(git -C "$T/b" rev-parse HEAD)"
rc=0; out="$(safe_update_repo "$T/b" main t-b 2>&1)" || rc=$?
echo "$out"
[ "$rc" = 0 ] && ok "(b) rc=0" || bad "(b) rc=$rc"
echo "$out" | grep -q '^\[entrypoint\] WARN:' && ok "(b) WARN printed" || bad "(b) no WARN"
echo "$out" | grep -q 'local changes were NOT touched' && ok "(b) NOT touched line" || bad "(b) no NOT touched line"
cmp -s "$T/b/f.txt" "$T/b.expect" && ok "(b) local edit byte-identical" || bad "(b) local edit changed"
[ "$(git -C "$T/b" rev-parse HEAD)" = "$head_before" ] && ok "(b) HEAD unchanged" || bad "(b) HEAD moved"

# (c) corrupt remote-tracking ref (0-byte file)
setup c; upstream_commit c
mkdir -p "$T/c/.git/refs/remotes/origin"; : > "$T/c/.git/refs/remotes/origin/x"
rc=0; out="$(safe_update_repo "$T/c" main t-c 2>&1)" || rc=$?
echo "$out"
[ "$rc" = 0 ] && ok "(c) corrupt ref, rc=0" || bad "(c) rc=$rc"

[ "$FAILS" = 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "$FAILS FAILED"; exit 1; }
