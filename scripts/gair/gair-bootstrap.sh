#!/bin/bash
###############################################################################
# gair-bootstrap.sh — 이 PC의 Claude를 gair(giip ai api router) 경유로 붙인다.
#
# 정본 절차: docs/60-operations/gair-bootstrap.md
# 워크플로우: .agent/workflows/gair-bootstrap.md ("gair 붙여" / /gair-bootstrap)
# 근거: CSN 47 #5671 lowy-dp01 시험 + 라이브 slack-bot/gair-accounts.js (#5858)
#
# 하는 일 (멱등):
#   1) 전제 확인: 이 csn 계정의 SK 유무 / GAIR_FUNCTION_KEY 유무 / claude CLI
#   2) AK 파생: scripts/gissue/get-ak.sh <csn> --json (SK 는 출력 안 됨)
#   3) 별도 설정 디렉터리 준비: $HOME/.claude-gair-<csn> (기존 세션 불간섭)
#   4) 스모크 테스트: gair /v1/messages 직접 POST 1건 → 상태코드로 판정
#
# 하드 규칙: SK/AK/함수 키 값을 화면·파일·로그 어디에도 출력하지 않는다. 값은 변수로만.
#            이 스크립트는 상태코드·유무·마스킹된 요약만 찍는다.
#
# 사용:
#   scripts/gair/gair-bootstrap.sh <csn>
#   scripts/gair/gair-bootstrap.sh <csn> --config-only   # 설정 디렉터리까지만(스모크 생략)
#
# 종료코드: 0=스모크 성공(HTTP 200) / 2=전제 불충족 / 1=스모크 실패(401/503/기타)
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ACCOUNTS_FILE="${REPO_ROOT}/slack-bot/.secrets/giip-accounts.json"
GAIR_BASE_URL="https://giipfaw.azurewebsites.net/api/gair"
GAIR_MESSAGES_URL="${GAIR_BASE_URL}/v1/messages"

CSN="${1:-}"
MODE="${2:-}"
if [ -z "${CSN}" ]; then
  echo "사용법: $0 <csn> [--config-only]" >&2
  exit 2
fi

fail_prereq() { echo "❌ 전제 불충족: $1" >&2; echo "   조치: docs/60-operations/gair-bootstrap.md §3 참조" >&2; exit 2; }

echo "== gair bootstrap — CSN ${CSN} =="

# --- 1) 전제 확인 ---------------------------------------------------------
if [ ! -f "${ACCOUNTS_FILE}" ]; then
  fail_prereq "계정 파일 없음: slack-bot/.secrets/giip-accounts.json"
fi
# SK 유무만 확인(값은 읽지 않는다).
HAS_SK="$(node -e "
const fs=require('fs');
const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const csn=Number(process.argv[2]);
const ch=Object.values(j.channels||j).find(a=>Number(a.csn)===csn);
process.stdout.write(ch && ch.sk ? 'yes' : 'no');
" "${ACCOUNTS_FILE}" "${CSN}")"
[ "${HAS_SK}" = "yes" ] || fail_prereq "csn ${CSN} 계정의 SK 없음 (giip-accounts.json .channels[*])"
echo "[ok] SK 존재: yes (값 미출력)"

if [ -z "${GAIR_FUNCTION_KEY:-}" ]; then
  fail_prereq "GAIR_FUNCTION_KEY env 미주입 — gair 라우트는 authLevel=function 이라 함수 키 없이는 401(빈 본문). 운영자에게 발급 요청."
fi
echo "[ok] GAIR_FUNCTION_KEY 주입: yes (값 미출력)"

if ! command -v claude >/dev/null 2>&1; then
  echo "[warn] claude CLI 미설치 — 직접 POST 스모크는 진행하되 Claude Code 왕복은 생략됨" >&2
fi

# --- 2) AK 파생 (SK → AdminGetAK) — 기존 스크립트 재사용 ------------------
echo "[..] AK 파생 중 (scripts/gissue/get-ak.sh ${CSN} --json)"
AK_JSON="$(bash "${REPO_ROOT}/scripts/gissue/get-ak.sh" "${CSN}" --json 2>/dev/null || true)"
AK="$(node -e "
let d; try { d=JSON.parse(process.argv[1]); } catch(e){ process.exit(1); }
if (Array.isArray(d)) d=d[0];
if (!d || Number(d.RstVal)!==200 || !d.ak) process.exit(1);
process.stdout.write(d.ak);
" "${AK_JSON}" 2>/dev/null || true)"
if [ -z "${AK}" ]; then
  echo "❌ AK 파생 실패 — SK/계정/네트워크 확인 (get-ak.sh 재실행)" >&2
  exit 1
fi
echo "[ok] AK 파생 성공 (값 미출력, 길이 ${#AK})"

# --- 3) 별도 설정 디렉터리 (기존 세션 불간섭) ----------------------------
GAIR_CONFIG_DIR="${HOME}/.claude-gair-${CSN}"
mkdir -p "${GAIR_CONFIG_DIR}"
echo "[ok] CLAUDE_CONFIG_DIR=${GAIR_CONFIG_DIR}"
echo ""
echo "이 PC에서 gair 경유로 claude 를 띄우려면(기존 세션 영향 없음):"
echo "  export CLAUDE_CONFIG_DIR=\"${GAIR_CONFIG_DIR}\""
echo "  export ANTHROPIC_BASE_URL=\"${GAIR_BASE_URL}\""
echo "  export ANTHROPIC_AUTH_TOKEN=\"<파생 AK — get-ak.sh ${CSN}>\""
echo "  export ANTHROPIC_CUSTOM_HEADERS=\"x-functions-key: \$GAIR_FUNCTION_KEY\""
echo "  unset ANTHROPIC_API_KEY ANTHROPIC_MODEL"
echo "  claude -p 'ping이라고만 답해줘' --output-format json"
echo ""

if [ "${MODE}" = "--config-only" ]; then
  echo "[done] --config-only: 스모크 생략."
  exit 0
fi

# --- 4) 스모크 테스트 (직접 POST, 상태코드만) ----------------------------
echo "[..] 스모크: POST ${GAIR_MESSAGES_URL}"
HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "${GAIR_MESSAGES_URL}" \
  -H "Authorization: Bearer ${AK}" \
  -H "x-functions-key: ${GAIR_FUNCTION_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  --data '{"model":"claude-sonnet-5-5","max_tokens":16,"messages":[{"role":"user","content":"ping이라고만 답해줘"}]}' \
  || echo "000")"

echo "[smoke] HTTP ${HTTP_CODE}"
case "${HTTP_CODE}" in
  2??)
    echo "✅ gair 스모크 성공 (HTTP ${HTTP_CODE}). 토큰 소비가 gair 를 거친다."
    exit 0 ;;
  401)
    echo "❌ HTTP 401 — 함수 키(x-functions-key) 또는 AK 인증 실패. docs/60-operations/gair-bootstrap.md §6 형식으로 보고." >&2
    exit 1 ;;
  503)
    echo "❌ HTTP 503 — 웹콘솔 category=gair upstream key 미등록(전제 §3-1). 그 CSN 운영자에게 보고." >&2
    exit 1 ;;
  000)
    echo "❌ 네트워크 오류/타임아웃 — 엔드포인트 접근 확인." >&2
    exit 1 ;;
  *)
    echo "❌ 예기치 않은 HTTP ${HTTP_CODE} — 오류 전문을 §6 형식으로 보고(값 마스킹)." >&2
    exit 1 ;;
esac
