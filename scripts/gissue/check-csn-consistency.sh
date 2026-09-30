#!/usr/bin/env bash
###############################################################################
# check-csn-consistency.sh — giip #3405
#
# 새 머신에 이 환경(giip-fde-agent + giipAgentLinux)을 클론한 뒤, 이 머신의 CSN 하나로
# giip-agent / giip-cqe / gissue-scheduler 3개 스케줄이 정합성 있게 등록됐는지 한 번에
# 점검한다. SSOT 는 scripts/gissue/csn-projects.json 의 단일 csn 키다(정본 설명:
# docs/60-operations/csn-multi-machine-registration.md).
#
# 사용:
#   bash scripts/gissue/check-csn-consistency.sh            # 점검만(읽기 전용)
#   bash scripts/gissue/check-csn-consistency.sh --register # lssn 미등록 시 giipAgent3.sh 1회 실행
#
# 종료코드: 0 = 모든 필수 점검 통과, 1 = 하나 이상 실패(FAIL). 경고(WARN)만 있으면 0.
###############################################################################
set -uo pipefail

# 스크립트 위치(scripts/gissue/)에서 REPO_DIR 를 역산 — 하드코딩 회피.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CSN_MAP_FILE="$REPO_DIR/scripts/gissue/csn-projects.json"
SSOT_JS="$REPO_DIR/scripts/gissue/lib/ssot-csn.js"

GIIP_AGENT_DIR="${GIIP_AGENT_DIR:-/work/giipAgentLinux}"
GIIP_AGENT_CNF="$(dirname "$GIIP_AGENT_DIR")/giipAgent.cnf"
CRON_DIR="${CRON_DIR:-/etc/cron.d}"

DO_REGISTER=false
[ "${1:-}" = "--register" ] && DO_REGISTER=true

fail=0
pass()  { echo "  [PASS] $*"; }
warn()  { echo "  [WARN] $*"; }
faill() { echo "  [FAIL] $*"; fail=1; }

echo "=== giip #3405 CSN 정합성 점검 (REPO_DIR=$REPO_DIR) ==="

# 1) SSOT — csn-projects.json 의 단일 csn 키
echo "[1] SSOT (csn-projects.json 단일 csn 키)"
SSOT_CSN=""
if [ ! -f "$CSN_MAP_FILE" ]; then
  faill "csn-projects.json 없음: $CSN_MAP_FILE — 새 머신이면 GIIP_CSN 을 넣고 컨테이너를 (재)기동하거나 이 파일을 만드세요."
elif SSOT_CSN="$(node "$SSOT_JS" "$CSN_MAP_FILE" 2>/tmp/.ssot_err)"; then
  pass "SSOT CSN = $SSOT_CSN"
else
  faill "단일 CSN 확정 실패: $(cat /tmp/.ssot_err 2>/dev/null)"
fi

# 2) giipAgent.cnf — sk 존재 + lssn 등록
echo "[2] giipAgent.cnf (sk/lssn)"
if [ ! -f "$GIIP_AGENT_CNF" ]; then
  faill "giipAgent.cnf 없음: $GIIP_AGENT_CNF — GIIP_SK 를 넣고 컨테이너를 (재)기동하면 entrypoint 가 생성합니다."
else
  sk_val="$(grep -oE '^sk="?[^"]*"?' "$GIIP_AGENT_CNF" | head -1 | sed -E 's/^sk="?([^"]*)"?/\1/')"
  lssn_val="$(grep -oE '^lssn="?[^"]*"?' "$GIIP_AGENT_CNF" | head -1 | sed -E 's/^lssn="?([^"]*)"?/\1/')"
  if [ -n "$sk_val" ]; then pass "sk 설정됨"; else faill "sk 비어 있음 ($GIIP_AGENT_CNF)"; fi
  if [[ "$lssn_val" =~ ^[1-9][0-9]*$ ]]; then
    pass "lssn 등록됨 (lssn=$lssn_val)"
  else
    if $DO_REGISTER && [ -n "$sk_val" ] && [ -f "$GIIP_AGENT_DIR/giipAgent3.sh" ]; then
      warn "lssn 미등록(=$lssn_val) — giipAgent3.sh 1회 실행해 자기등록 시도"
      ( cd "$GIIP_AGENT_DIR" && bash giipAgent3.sh ) >/tmp/.giipagent_reg.log 2>&1 || true
      lssn_val="$(grep -oE '^lssn="?[^"]*"?' "$GIIP_AGENT_CNF" | head -1 | sed -E 's/^lssn="?([^"]*)"?/\1/')"
      if [[ "$lssn_val" =~ ^[1-9][0-9]*$ ]]; then pass "자기등록 완료 (lssn=$lssn_val)"; else faill "자기등록 후에도 lssn 미확정(로그: /tmp/.giipagent_reg.log)"; fi
    else
      warn "lssn 미등록(=$lssn_val). '$0 --register' 로 giipAgent3.sh 자기등록을 실행하거나, cd $GIIP_AGENT_DIR && bash giipAgent3.sh 를 1회 실행하세요."
    fi
  fi
fi

# 3) GIIP_CSN env ↔ SSOT
echo "[3] GIIP_CSN(env) ↔ SSOT"
if [ -z "${GIIP_CSN:-}" ]; then
  warn "GIIP_CSN env 미설정(정상 — 클론 후엔 SSOT 만 있으면 됨)"
elif [ -z "$SSOT_CSN" ]; then
  warn "SSOT 를 확정하지 못해 비교 생략"
elif [ "$GIIP_CSN" = "$SSOT_CSN" ]; then
  pass "일치 (GIIP_CSN=$GIIP_CSN)"
else
  faill "불일치: GIIP_CSN(env)=$GIIP_CSN != SSOT=$SSOT_CSN (클론 후 stale env — SSOT 가 정본)"
fi

# 4) gissue-scheduler cron 의 -OnlyCsn ↔ SSOT
echo "[4] gissue-scheduler cron -OnlyCsn ↔ SSOT"
SCHED_CRON="$CRON_DIR/gissue-scheduler"
if [ ! -f "$SCHED_CRON" ]; then
  faill "$SCHED_CRON 없음 — scheduler cron 미등록"
else
  cron_csn="$(grep -oE '\-OnlyCsn [0-9]+' "$SCHED_CRON" | grep -oE '[0-9]+' | head -1 || true)"
  if [ -z "$cron_csn" ]; then
    warn "cron 에 -OnlyCsn 인자가 없음(모든 CSN 처리 모드) — 단일 CSN 머신에서는 -OnlyCsn=$SSOT_CSN 를 기대"
  elif [ -z "$SSOT_CSN" ]; then
    warn "SSOT 를 확정하지 못해 비교 생략 (cron -OnlyCsn=$cron_csn)"
  elif [ "$cron_csn" = "$SSOT_CSN" ]; then
    pass "일치 (-OnlyCsn=$cron_csn)"
  else
    faill "불일치: cron -OnlyCsn=$cron_csn != SSOT=$SSOT_CSN (최초 기동 CSN 이 cron 에 박힌 stale 패턴 — 컨테이너 재기동으로 entrypoint 가 SSOT 기준으로 다시 생성)"
  fi
fi

# 5) 3개 cron 파일 로드 여부
echo "[5] cron 파일 존재 (giip-agent / giip-cqe / gissue-scheduler)"
for c in giip-agent giip-cqe gissue-scheduler; do
  if [ -f "$CRON_DIR/$c" ]; then pass "$CRON_DIR/$c"; else warn "$CRON_DIR/$c 없음 (해당 스케줄 비활성이면 정상 — GIIP_ENABLE_AGENT/GIIP_ENABLE_SCHEDULER 확인)"; fi
done

echo "=== 결과: $([ $fail -eq 0 ] && echo '통과(PASS)' || echo '실패(FAIL) — 위 [FAIL] 항목 조치 필요') ==="
exit $fail
