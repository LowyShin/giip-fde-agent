# check-gissue-liveness.ps1 — gissue 처리 "무소식" 점검 (giip 4411)
#
# 무엇을: CSN 별 처리 로그(gissue_csn<N>.log)의 최신 갱신 시각과 .lock 상태를 읽어, 이슈 처리 본체
#   (run-gissue-claude.ps1)가 최근에 실제로 돌았는지 판정한다. Task Scheduler 결과코드(LastTaskResult)는
#   보지 않는다 — 태스크가 엉뚱한 스크립트를 가리켜도 0 으로 끝나기 때문이다(실사고: 처리 본체가 6일 넘게
#   안 돌았는데 결과코드는 계속 0).
# 읽기 전용: 로그·락·설정을 쓰지 않는다. 파일을 쓰는 것은 -Notify 일 때의 쿨다운 상태 파일 하나뿐이다.
# 결과 저장·소비: 표준출력(요약 또는 -Json) + 종료코드. 종료코드는 이 점검을 매시 돌리는 독립 태스크의
#   LastTaskResult 로 남는다(register-gissue-liveness-task.ps1). -Notify 이면 [OPS] 이슈 1건(giip 이슈 DB)과
#   logs/gissue_liveness_state.json(쿨다운 서명)에 기록된다.
#
# 판정:
#   · CSN 별: OK(최근 -MaxSilentHours 이내 로그 갱신) / RUNNING(살아있는 락 = 처리 중, 오탐 방지) /
#             SILENT(로그가 기준보다 오래됨; 죽은 PID 락·-StaleLockHours 이상 묵은 락이면 사유에 표시) /
#             NO_LOG(로그 파일 없음)
#   · 전체: OK / PARTIAL_SILENT(일부 CSN 만 무소식) / ALL_SILENT(전부 무소식 = 스케줄러 자체 정지 의심) /
#           NO_TARGETS(점검 대상 없음 — 판정 불가, 정상으로 치지 않는다)
# 종료코드: 0 = 정상 / 1 = 무소식 또는 판정 불가
#
# 알림(-Notify, 기본 꺼짐 = 출력만): -OpsCsn(또는 환경변수 GISSUE_LIVENESS_OPS_CSN)로 지정한 CSN 에
#   "[OPS] gissue 처리 무소식 감지" 이슈를 1건 등록한다. 그 CSN 은 이 배포가 쓰기 권한을 가진 작업 CSN
#   이어야 한다(남의 CSN 에 쓰지 않는다). 이미 열린 같은 제목 이슈가 있으면 새로 만들지 않고, 상태 서명이
#   같으면 -CooldownHours 동안 재알림하지 않는다. -OpsCsn 이 없으면 알림 없이 로그만 남긴다.
#   (선례: run-gissue-claude.ps1 의 미매핑 CSN 가드 — GISSUE_CSNGUARD_OPS_CSN)
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1 -Json
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1 -Notify -OpsCsn <csn>

param(
    # 처리 로그가 이 시간(시) 넘게 갱신되지 않으면 무소식. 스케줄 주기 1h + 긴 실행(상한 105분)을 감안한 기본 3h.
    [double]$MaxSilentHours = 3,
    # 락이 이 시간(시) 이상 묵으면 멈춘 실행으로 본다(살아있는 PID 여도 진행 중으로 치지 않는다).
    [double]$StaleLockHours = 2,
    [string]$LogDir = '',
    [string]$ConfigPath = '',
    [switch]$Json,
    # 실알림 스위치. 없으면 "알릴 내용"만 출력한다.
    [switch]$Notify,
    [string]$OpsCsn = '',
    [double]$CooldownHours = 6
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $LogDir)     { $LogDir = Join-Path $ScriptDir 'logs' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptDir 'csn-projects.json' }
. (Join-Path $ScriptDir 'lib\gissue-liveness-lib.ps1')

# -Json 일 때 표준출력은 JSON 한 덩어리여야 하므로 부가 안내는 표준오류로 보낸다.
function Say($m) { if ($Json) { [Console]::Error.WriteLine($m) } else { Write-Output $m } }

$result = Get-GissueLiveness -LogDir $LogDir -ConfigPath $ConfigPath -MaxSilentHours $MaxSilentHours -StaleLockHours $StaleLockHours

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Output "[gissue-liveness] $($result.Overall) — $($result.Summary)"
    foreach ($r in $result.Csns) {
        $line = "  CSN $($r.Csn): $($r.Status)"
        if ($r.LastLog) { $line += " (마지막 로그 $($r.LastLog), $($r.SilentHours)h 전)" }
        if ($r.Reason)  { $line += " — $($r.Reason)" }
        Write-Output $line
    }
}

if (-not $result.Healthy) {
    $ops = if ($OpsCsn) { $OpsCsn } else { "$($env:GISSUE_LIVENESS_OPS_CSN)".Trim() }
    $stateFile = Join-Path $LogDir 'gissue_liveness_state.json'
    $state = $null
    if (Test-Path -LiteralPath $stateFile) { try { $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $state = $null } }
    $due = Test-LivenessNotifyDue -Result $result -State $state -CooldownHours $CooldownHours
    $title = '[OPS] gissue 처리 무소식 감지'
    if (-not $ops -or $ops -notmatch '^\d+$') {
        Say "[gissue-liveness] 알림 대상 CSN 없음(-OpsCsn / GISSUE_LIVENESS_OPS_CSN 미지정) — 출력만"
    } elseif (-not $Notify) {
        Say "[gissue-liveness] DRYRUN: -Notify 없음 — 알림 안 함(쿨다운 판정: Due=$($due.Due), $($due.Why)); 대상 CSN=$ops 제목=$title"
    } elseif (-not $due.Due) {
        Say "[gissue-liveness] 알림 생략: $($due.Why)"
    } else {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
        $listJs = Join-Path $ScriptDir 'list-issues.js'
        $regJs  = Join-Path $ScriptDir 'register-issue.js'
        try {
            # list-issues.js 가 없는 배포(일부 사본)에서는 중복 조회를 건너뛰고 쿨다운 서명만으로 막는다.
            $dup = @()
            if (Test-Path -LiteralPath $listJs) {
                $existing = & node $listJs --csn $ops --status 'PENDING,READY,IN_PROGRESS,REVIEW' --json 2>&1 | Out-String | ConvertFrom-Json
                $dup = @($existing | Where-Object { $_.title -like "$($title.Replace('[','[[]'))*" })
            }
            if ($dup.Count -gt 0) {
                Say "[gissue-liveness] 알림 생략: 열린 [OPS] 이슈가 이미 있음(isn=$($dup[0].isn))"
            } else {
                $body = @(
                    "gissue 처리 로그가 기준(${MaxSilentHours}h) 넘게 갱신되지 않았습니다. (auto-detected: check-gissue-liveness.ps1, giip 4411)",
                    '',
                    $result.Summary,
                    ''
                ) + @($result.Csns | Where-Object { $_.Status -in @('SILENT', 'NO_LOG') } | ForEach-Object { "- CSN $($_.Csn): $($_.Status) — $($_.Reason)" }) + @(
                    '',
                    '먼저 확인: 스케줄 태스크가 run-gissue-claude.ps1 를 가리키는지(`manage-gissue-scheduler.ps1 -Action Status`), 락 파일이 죽은 프로세스의 것은 아닌지.'
                )
                $regOut = & node $regJs --title $title --content ($body -join "`n") --csn $ops 2>&1 | Out-String
                Say "[gissue-liveness] POSTED: 운영 이슈 등록. 출력: $($regOut.Trim())"
                @{ lastNotifiedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); signature = $due.Signature } | ConvertTo-Json | Out-File -FilePath $stateFile -Encoding UTF8
            }
        } catch {
            Say "[gissue-liveness] POST-FAIL: 알림 실패: $($_.Exception.Message)"
        }
    }
}

if ($result.Healthy) { exit 0 } else { exit 1 }
