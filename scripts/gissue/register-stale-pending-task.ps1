# register-stale-pending-task.ps1 — GIIP_StalePending_Hourly 작업 스케줄러 등록(멱등)
#
# 매시 :07 에 `run-list-stale-pending.ps1` 을 실행해 PENDING 상태로 장기 방치된 이슈를 탐지한다.
# 재실행하면 기존 태스크를 갱신한다(중복 생성 없음). 원본: lowyworkenv (giip #2410, 주기 수정 #2480),
# 이 레포로의 이식은 giip #2645.
#
# 사용 (이 PC 에는 PowerShell 7(`pwsh`)이 없다 — 항상 `powershell` 로 부른다):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-pending-task.ps1 -Csn 47
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-pending-task.ps1 -Unregister
#
# ※ 등록은 반드시 **정상 체크아웃**에서 실행한다. worktree 안에서 실행하면 게이트 3(task-target-guard.ps1)이
#   임시 경로가 태스크에 박히는 것을 막고 종료코드 1 로 끝난다 — 정상 동작이다.
param(
    # 태스크 이름. 한 PC 에 여러 배포를 등록한다면 배포마다 고유하게 바꾼다.
    [string]$TaskName = 'GIIP_StalePending_Hourly',
    # 대상 CSN. 0 이면 러너가 csn-projects.json 의 enabled CSN 전체를 돈다.
    [int]$Csn = 0,
    # 비활성 기준 일수(러너에 그대로 전달).
    [int]$DaysThreshold = 7,
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

# 자기 위치 기준 상대경로. 이 PC 전용 절대경로를 박지 않는다 — 다른 PC 에 clone 만 해도 동작해야 한다.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'run-list-stale-pending.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Unregistered: $TaskName"
    return
}

# 등록 전 3중 게이트: (1) 대상 존재 (2) 파싱+BOM 통과 (3) 임시 worktree 경로 아님 — giip #2431/#2591
. (Join-Path $ScriptDir 'task-target-guard.ps1')
Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName

# 엔진은 Windows PowerShell 5.1 고정. `pwsh`(PowerShell 7)는 이 PC 에 설치돼 있지 않고,
# 이름으로 부르면 command not found 로 **아무 일도 하지 않고** 끝난다(giip #2559 실사고).
$engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn -DaysThreshold $DaysThreshold"
$action  = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# 매시 :07 (다른 gissue 스윕과 동일 슬롯).
# giip #2480: 예전에는 `-Weekly -DaysOfWeek <7일> -At 00:07` 이라 **이름은 _Hourly 인데 실제로는
#   하루 1회만** 돌았다(트리거에 반복이 아예 없었다 — 등록은 성공하고 LastTaskResult 도 0 이라
#   아무도 눈치채지 못했다). 정상 형태(Once + PT1H 반복, 기간 P3650D)로 맞춘다.
#   RepetitionDuration 에 [TimeSpan]::MaxValue 를 쓰면 Task Scheduler XML 상한 초과로 등록이
#   거부된다(HRESULT 0x80041318, giip #1275) → 3650일(약 10년).
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 7 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# 등록 직전 주기 게이트: 이름(_Hourly)과 실제 반복 간격이 어긋나면 거부 — giip #2480
. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: PENDING 장기방치 이슈 탐지 (giip #2410, 이식 #2645, 매시 :07)'

Write-Output "Registered: $TaskName (hourly at :07, engine=$engine)"
Write-Output "Test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`" -Csn $Csn"
