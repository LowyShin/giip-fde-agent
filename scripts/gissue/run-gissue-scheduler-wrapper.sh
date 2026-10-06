#!/bin/bash
#
# scripts/gissue/run-gissue-scheduler-wrapper.sh — giip #3575
#
# 목적:
#   gissue scheduler cron이 호출하는 run-gissue-claude.ps1을 래퍼하여
#   tSchedulerAgentRun 테이블에 실행 이력을 기록한다.
#   admin/catquest/schedulers 페이지의 "Run History"에 gissue 스케쥴러 실행이력이
#   표시되도록 하는 것이 이 래퍼의 유일한 목적이다.
#
# 원리:
#   giipAgentLinux (컨테이너 내 /work/giipAgentLinux/)의 lib/scheduler_agent_run.sh가
#   제공하는 sar_run_start / sar_run_end_trap 함수를 사용한다.
#   이 함수는 pApiSchedulerAgentRunStartBySK / pApiSchedulerAgentRunEndBySK SP를 호출하여
#   tSchedulerAgentRun에 실행 시작/종료를 기록한다.
#   cron이 pwsh를 직접 호출하면(run-gissue-claude.ps1) 이 이력이 남지 않는다.
#
# 사용법:
#   entrypoint.sh의 cron登録에서 pwsh ... run-gissue-claude.ps1 대신 이 래퍼를 호출한다.
#   예: bash /work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh -OnlyCsn 47
#
#   이 래퍼는 giipAgentLinux가 /work/giipAgentLinux에 clone된 후 실행되어야 한다.
#   giipAgentLinux가 아직 clone되지 않았으면(sk/apiaddrv2 미설정) 조용히 pwsh를 직접 호출한다.
#   이 경우 이력은 기록되지 않지만 스케쥴러 자체는 정상 동작한다.
#
# 의존성:
#   - /work/giipAgentLinux/lib/scheduler_agent_run.sh (giipAgentLinux clone 필요)
#   - /work/giipAgentLinux/giipAgent.cnf (sk, apiaddrv2 설정값)
#   - sar_run_start / sar_run_end_trap 함수는 API 호출 실패 시에도 본 실행에 영향을
#     주지 않고 WARN만 남기므로 스케쥴러 동작 자체는 항상 보장된다.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
AGENT_DIR="${GIIP_AGENT_DIR:-/work/giipAgentLinux}"
SAR_LIB="${AGENT_DIR}/lib/scheduler_agent_run.sh"
AGENT_CNF="$(dirname "$AGENT_DIR")/giipAgent.cnf"

# giipAgentLinux/lib/scheduler_agent_run.sh에서 제공하는 함수 로드.
# 파일이 없으면 이력 기록 없이 pwsh를 직접 호출한다(기존 동작 유지).
if [ -f "$SAR_LIB" ]; then
    # shellcheck disable=SC1091
    . "$SAR_LIB"
else
    sar_run_start() { return 0; }
    sar_run_end_trap() { return 0; }
fi

# giipAgent.cnf에서 sk와 apiaddrv2를 읽는다.
# 이 값들이 없으면 이력 기록 없이 pwsh를 직접 호출한다.
if [ -f "$AGENT_CNF" ]; then
    # shellcheck disable=SC1090
    while IFS='=' read -r key value; do
        case "$key" in
            sk)       sk="${value#\"}"; sk="${sk%\"}" ;;
            apiaddrv2) apiaddrv2="${value#\"}"; apiaddrv2="${apiaddrv2%\"}" ;;
        esac
    done < "$AGENT_CNF"
fi

# sar_run_start이 요구하는 sk/apiaddrv2가 없으면 이력 기록 없이pwsh를 직접 호출.
if [ -z "${sk:-}" ] || [ -z "${apiaddrv2:-}" ]; then
    echo "[run-gissue-scheduler-wrapper] sk or apiaddrv2 not set — falling back to direct pwsh call (no run history will be recorded)"
    exec pwsh -NoProfile -NonInteractive -File "$SCRIPT_DIR/run-gissue-claude.ps1" "$@"
fi

# sar_run_start: 실행 시작 이력 기록. 실패해도 계속 진행(WARN만 남김).
sar_run_start "scheduled"

# EXIT 시 sar_run_end_trap 자동 호출 (성공/실패 모두).
trap 'sar_run_end_trap' EXIT

# 실제 gissue 스케쥴러 실행.
exec pwsh -NoProfile -NonInteractive -File "$SCRIPT_DIR/run-gissue-claude.ps1" "$@"
