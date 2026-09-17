# register-audit-review-prs-task.ps1 — GIIP_AuditReviewPrs_Hourly 작업 스케줄러 등록(멱등)
#
# 매시 :07 에 `run-audit-review-prs.ps1` 을 실행해 "REVIEW 인데 PR 이 0 건"인 이슈를 감사한다.
# 원본: lowyworkenv (giip #2395/#2431), 이 레포로의 이식은 giip #2645.
#
# 배경(원본 주석 보존, giip #2431): 이 태스크는 작업 스케줄러에 등록돼 있었지만 **등록 스크립트 자체가
#   레포에 없었다**(러너도 미커밋 상태였다). 태스크를 재현·복구할 수단이 git 밖에만 있던 셈이라
#   등록기를 정본으로 둔다.
#
# 사용 (이 PC 에는 PowerShell 7(`pwsh`)이 없다 — 항상 `powershell` 로 부른다):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-audit-review-prs-task.ps1 -Csn 47
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-audit-review-prs-task.ps1 -Unregister
param(
    [string]$TaskName = 'GIIP_AuditReviewPrs_Hourly',
    # 감사 대상 CSN. 0 이면 러너가 giip-accounts.json 에 등록된 전체 CSN 을 대상으로 한다.
    [int]$Csn = 0,
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'run-audit-review-prs.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Unregistered: $TaskName"
    return
}

# 등록 전 3중 게이트 — giip #2431/#2591
. (Join-Path $ScriptDir 'task-target-guard.ps1')
Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName

# 엔진은 Windows PowerShell 5.1 고정(`pwsh` 미설치 — giip #2559).
$engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

# 매시 콘솔 창이 뜨지 않도록 Hidden/NonInteractive 를 유지한다(원본 등록본과 동일).
$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn"
$action = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# 매시 :07. 정상 형태(Once + PT1H / P3650D) — giip #2480 / #1275.
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 7 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# 등록 직전 주기 게이트 — giip #2480.
# (이 파일은 처음부터 PT1H/P3650D 라 통과한다. 나중에 트리거를 손댔을 때 조용히 하루 1회로 떨어지는
#  것을 막는 회귀 방지용으로 함께 건다.)
. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: REVIEW 인데 PR 0 인 이슈 감사 (giip #2395/#2431, 이식 #2645, 매시 :07)'

Write-Output "Registered: $TaskName (hourly at :07, engine=$engine)"
Write-Output "Test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn"
