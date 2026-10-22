# register-stale-review-task.ps1 — GIIP_StaleReview_Hourly 작업 스케줄러 등록(멱등)
#
# 매시 :07 에 `run-list-stale-review.ps1` 을 실행해 REVIEW 상태로 장기 방치된 이슈를 탐지한다.
# 재실행하면 기존 태스크를 갱신한다(중복 생성 없음). 원본: lowyworkenv (giip #2420, 주기 수정 #2480),
# 이 레포로의 이식은 giip #2645.
#
# 사용 (이 PC 에는 PowerShell 7(`pwsh`)이 없다 — 항상 `powershell` 로 부른다):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-review-task.ps1 -Csn 47
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-review-task.ps1 -Unregister
#
# ※ 등록은 반드시 **정상 체크아웃**에서 실행한다(worktree 안이면 게이트 3 이 막는다 — 정상 동작).
param(
    [string]$TaskName = 'GIIP_StaleReview_Hourly',
    [int]$Csn = 0,
    [int]$DaysThreshold = 7,
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'run-list-stale-review.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Unregistered: $TaskName"
    return
}

# 등록 전 3중 게이트: (1) 대상 존재 (2) 파싱+BOM 통과 (3) 임시 worktree 경로 아님 — giip #2431/#2591
. (Join-Path $ScriptDir 'task-target-guard.ps1')
Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName

# 엔진은 Windows PowerShell 5.1 고정(`pwsh` 미설치 — giip #2559).
$engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn -DaysThreshold $DaysThreshold"
$action  = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# 매시 :07. giip #2480 의 "이름은 Hourly 인데 하루 1회" 결함을 피한 정상 형태(Once + PT1H / P3650D).
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 7 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# 등록 직전 주기 게이트 — giip #2480
. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: REVIEW 장기방치 이슈 탐지 (giip #2420, 이식 #2645, 매시 :07)'

Write-Output "Registered: $TaskName (hourly at :07, engine=$engine)"
Write-Output "Test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn"
