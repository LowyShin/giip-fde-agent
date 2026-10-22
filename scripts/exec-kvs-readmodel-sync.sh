#!/bin/bash
# exec-kvs-readmodel-sync.sh (giip 3659)
# 목적: tKVS → 읽기모델(tKVSLatest, tKVSRecent) 증분 이관 SP(pApiKVSReadModelSyncbySk)를 ≤1분
#       주기로 호출한다. 이 인스턴스에 이미 있는 "cron → giipfaw 디스패처 SP 호출" 패턴
#       (page-feedback-analyze / CQE / scheduler-state)과 동일한 방식이며 새 메커니즘이 아니다.
# 호출 계약(scheduler-state.ps1, giip #3563 와 동일): giipApiSk2 디스패처는 SK 를 token, 실행 SP 를
#   text 로 읽어 EXEC pApi<이름>bySk @p0(=SK) 를 호출한다. 여기선 text='KVSReadModelSync'(인자 없음),
#   token=<SK>, jsondata 는 빈 값.
# SK/엔드포인트는 giipAgentLinux 와 같은 giipAgent.cnf(=$GIIP_AGENT_DIR 의 부모)에서 읽는다(CQE 와 동일).
# 실패가 본 컨테이너 기동/다른 cron 에 영향을 주면 안 되므로 항상 exit 0 으로 끝낸다(로그만 남김).
set -u

LOG_PREFIX="[exec-kvs-readmodel-sync]"
GIIP_AGENT_DIR="${GIIP_AGENT_DIR:-/work/giipAgentLinux}"
CNF_FILE="$(dirname "$GIIP_AGENT_DIR")/giipAgent.cnf"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $LOG_PREFIX $*"; }

if [ ! -f "$CNF_FILE" ]; then
    log "WARN: $CNF_FILE 없음 — giipAgent 미구성. 스킵."
    exit 0
fi

SK="$(grep -E '^sk=' "$CNF_FILE" 2>/dev/null | head -1 | cut -d'"' -f2)"
APIADDRV2="$(grep -E '^apiaddrv2=' "$CNF_FILE" 2>/dev/null | head -1 | cut -d'"' -f2)"

if [ -z "$SK" ] || [ -z "$APIADDRV2" ]; then
    log "WARN: cnf 에서 sk/apiaddrv2 를 못 읽음 — 스킵."
    exit 0
fi

# 디스패처 호출: token=SK, text='KVSReadModelSync' → EXEC pApiKVSReadModelSyncbySk @p0(=SK)
resp="$(curl -sS -X POST "$APIADDRV2" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "token=$SK" \
    --data-urlencode 'text=KVSReadModelSync' \
    --data-urlencode 'jsondata=' \
    2>&1)"

log "resp: $(printf '%s' "$resp" | tr '\r\n' '  ' | cut -c1-500)"
exit 0
