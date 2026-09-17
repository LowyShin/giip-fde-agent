# register-gate-escalation-task.ps1 — GIIP_GateEscalation_Hourly 작업 스케줄러 등록(멱등)
#
# 매시 :07 에 `run-gate-escalation-recheck.ps1` 을 실행해, 게이트 3회 캡(`*-GATE-HUMAN-REVIEW`)으로
# 종착해 아무도 읽지 않게 된 이슈를 자동 재판정 큐에 올린다.
# 원본: lowyworkenv (giip #2428), 이 레포로의 이식은 giip #2645.
#
# 사용 (이 PC 에는 PowerShell 7(`pwsh`)이 없다 — 항상 `powershell` 로 부른다):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gate-escalation-task.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gate-escalation-task.ps1 -Unregister
param(
    [string]$TaskName = 'GIIP_GateEscalation_Hourly',
    # 0 이면 응답에 들어 있는 모든 CSN 이 대상(러너가 클라이언트 측에서 필터링한다).
    [int]$Csn = 0,
    # 한 회차에 큐에 올릴 최대 건수(폭주 방지) — 러너에 그대로 전달.
    [int]$MaxPerRun = 5,
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'run-gate-escalation-recheck.ps1'

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

$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn -MaxPerRun $MaxPerRun"
$action = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# 매시 :07 — 정상 형태 (B): Daily 트리거로 매일 재무장 + 24시간 동안 매시 반복.
# (형태 A 와 달리 매일 00:07 에 트리거가 다시 시작되므로 P1D 로 충분하다.)
$trigger = New-ScheduledTaskTrigger -Daily -At 00:07
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 00:07 -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# 등록 직전 주기 게이트 — giip #2480.
# (Daily 트리거 위에 Repetition PT1H/P1D 를 얹은 형태라 실제로 매시 돈다 → 통과한다.)
. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: 게이트 3회 캡(*-GATE-HUMAN-REVIEW) 에스컬레이션 이슈 자동 재판정 큐 등록 (giip #2428, 이식 #2645, 매시 :07)'

Write-Output "Registered: $TaskName (hourly at :07, engine=$engine)"
Write-Output "DryRun test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn -DryRun"
