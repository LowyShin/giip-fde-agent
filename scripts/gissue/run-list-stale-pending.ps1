# run-list-stale-pending.ps1 — PENDING 상태로 장기 방치된 이슈 탐지 실행기
# Windows Task Scheduler `GIIP_StalePending_Hourly`(매시 :07)에서 실행한다.
#
# 원본: lowyworkenv `scripts/gissue/run-list-stale-pending.ps1` (giip #2410 Phase 2 Rule #1,
#       주기 결함 수정 #2480). 이 레포로의 이식은 giip #2645.
#
# ── 이식 시 바뀐 것 ────────────────────────────────────────────────────────────
#   원본은 `giipdb/mgmt/execSQLFile.ps1` + `dbconfig.json` 으로 DB 에 직접 INSERT 했다.
#   `giip-fde-agent` 에는 DB 직접접속 수단이 없으므로, 정본 문서
#   `docs/60-operations/hourly-issue-scheduler.md` §4 의 "혼용 이식 금지" 규정에 따라 이 레포에 실제로
#   있는 API 도구(`scripts/gissue/list-issues.js`)로 교체했다. 판정 기준의 미세한 차이와
#   결과물이 저장되는 곳/소비처는 `stale-issue-scan-lib.ps1` 상단에 전부 적어 두었다.
#
# ── 완료 판정 주의 (원본 주석 보존) ─────────────────────────────────────────────
#   태스크 정상 동작을 `LastTaskResult=0` 으로 판단하지 말 것. 이 태스크는 대상 파일이 아예 없는
#   상태에서도 0 을 돌려주고 있었고(giip #2431), 반복이 빠져 하루 1회만 도는 상태에서도 0 이었다(#2480).
#   반드시 아래 직접 실행 출력과 `audit-results/*.log` tail 로 확인한다.
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-list-stale-pending.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-list-stale-pending.ps1 -Csn 47 -DaysThreshold 7
param(
    # 대상 CSN. 0 이면 csn-projects.json 의 enabled CSN 전체.
    [int]$Csn = 0,
    # 방치 기준 일수(기본 7일).
    [int]$DaysThreshold = 7,
    # SK 저장소 경로(미지정 시 <RepoRoot>/slack-bot/.secrets/giip-accounts.json).
    [string]$AccountsFile = ''
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ResultDir = Join-Path $ScriptDir 'audit-results'
if (-not (Test-Path $ResultDir)) { New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }
$LogFile = Join-Path $ResultDir "stale-pending-csn${Csn}.log"

function Write-RunLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    # Write-Output 이 아니라 Write-Host 다. 이 함수는 스크립트블록으로 라이브러리에 넘겨져
    # 함수 안에서 호출되므로, 출력 스트림에 쓰면 로그 줄이 **호출자의 반환값에 섞여** 조용히
    # 삼켜진다(실측 2026-09-17: 실패 사유 줄이 한 줄도 안 보였다). 원본 lowyworkenv 판도 Write-Host 다.
    Write-Host $line
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

. (Join-Path $ScriptDir 'stale-issue-scan-lib.ps1')

$targets = @(Get-StaleScanTargetCsn -ScriptDir $ScriptDir -Csn $Csn)
if ($targets.Count -eq 0) {
    Write-RunLog "SKIP: 대상 CSN 이 없습니다 — -Csn <번호> 로 지정하거나 csn-projects.json 을 채우세요(csn-projects.json.example 참고)."
    exit 0
}

Write-RunLog "Starting stale-PENDING detection (대상 CSN: $($targets -join ', '), 기준 $DaysThreshold 일)"

$failed = 0
$totalStale = 0
$totalUnknown = 0
foreach ($c in $targets) {
    $r = Invoke-StaleIssueScan -ScriptDir $ScriptDir -Csn $c -Status 'PENDING' -Label 'stale-pending' `
        -DaysThreshold $DaysThreshold -AccountsFile $AccountsFile -Logger ${function:Write-RunLog}
    if ($r.ExitCode -ne 0) { $failed++; continue }
    $totalStale += $r.Stale
    $totalUnknown += $r.Undetermined
}

if ($failed -gt 0) {
    Write-RunLog "FAILED: $failed 개 CSN 조회 실패 (성공분 방치 $totalStale 건 / 판정불가 $totalUnknown 건)"
    exit 1
}

Write-RunLog "SUCCESS: 방치 $totalStale 건 / 판정불가 $totalUnknown 건 (CSN $($targets.Count) 개)"
exit 0
