#!/usr/bin/env sh
# pre-push-pure-source-guard.sh
#
# 고객 웹 레포(vgt-smart-order-system 등 Django 앱)를 push 하기 "전에" 실행하는
# 순수 소스 가드 테스트 러너. FAIL 이면 non-zero 로 종료해 호출부가 push 를 중단하게 한다.
#
# 배경(giip-3773 / giip-3748): tests_template_comment_syntax 같은 가드 테스트는
# 레포에 존재했지만 push 전에 자동 실행·차단되지 않아, 복수행 {# #} 코멘트 누출이
# FAIL 인 채 push/deploy 까지 통과해 4회 재발했다. 서버사이드 CI(.github/workflows)가
# 가장 강력하지만 토큰 workflow scope 가 필요하다. 이 스크립트는 그와 보완적으로,
# 에이전트가 push 하기 전에 반드시 통과시켜야 하는 클라이언트사이드 가드다.
# 정본 규칙: .agent/rules/53_pre_push_pure_source_guard.md
#
# 사용법:
#   sh pre-push-pure-source-guard.sh [REPO_PATH]
#     REPO_PATH 생략 시 현재 디렉터리를 레포 루트로 본다.
#   GUARD_MODULES 환경변수로 검사 모듈 목록(공백 구분)을 덮어쓸 수 있다.
#
# 종료코드: 0=통과 또는 가드 모듈 없음(스킵), 1=가드 FAIL, 2=python 미발견.

set -eu

REPO_PATH="${1:-.}"

# 이 레포 유형에서 push 전에 반드시 통과시킬 순수 소스(Django setup/DB 불요) 가드 모듈.
# 필요 시 호출부가 GUARD_MODULES 로 재정의한다.
GUARD_MODULES="${GUARD_MODULES:-app.main_system.tests_template_comment_syntax app.main_system.tests_fc_token_route_order}"

cd "$REPO_PATH"

PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "[pre-push-guard] python 미발견 — 가드를 실행할 수 없음" >&2
  exit 2
fi

# 모듈명(점 구분)을 파일 경로로 바꿔 실제 존재하는 것만 검사 대상으로 모은다.
# 가드 모듈이 하나도 없는 레포(비대상)는 조용히 스킵(exit 0)한다.
present=""
for m in $GUARD_MODULES; do
  f="$(printf '%s' "$m" | tr '.' '/').py"
  if [ -f "$f" ]; then
    present="$present $m"
  fi
done

if [ -z "$present" ]; then
  echo "[pre-push-guard] 가드 모듈 없음(비대상 레포) — 스킵"
  exit 0
fi

echo "[pre-push-guard] 실행:$present"
# shellcheck disable=SC2086
"$PY" -m unittest $present
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[pre-push-guard] FAIL(rc=$rc) — push 를 중단하라" >&2
  exit 1
fi
echo "[pre-push-guard] OK — push 진행 가능"
exit 0
