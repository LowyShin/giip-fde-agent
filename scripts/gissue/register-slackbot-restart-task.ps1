# register-slackbot-restart-task.ps1 — GIIP_SlackbotRestart_Hourly 작업 스케줄러 등록(멱등)
#
# giip #2148 오너 결정(옵션 b): "slack-bot 배포 커밋이 바뀌었으면, 유휴 판정을 통과할 때만 pm2 restart"를
# 매시 실행한다. 실제 판정·재시작은 run-slackbot-restart-check.ps1 이 수행한다(구현은 그쪽 파일 주석 참고).
# 원본: lowyworkenv, 이 레포로의 이식은 giip #2645.
#
# 트리거: 매시 :37 (1시간 반복). 메인 스케줄러(:07)가 pm2 워치독·CSN 처리로 레포를 만지므로,
# 그 실행과 겹치지 않도록 30분 오프셋을 둔다(유휴 판정 오탐/경합 최소화).
#
# 사용 (이 PC 에는 PowerShell 7(`pwsh`)이 없다 — 항상 `powershell` 로 부른다):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-slackbot-restart-task.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-slackbot-restart-task.ps1 -Unregister
param(
    [string]$TaskName = 'GIIP_SlackbotRestart_Hourly',
    # pm2 프로세스 이름 / 감시할 레포 하위 경로. 배포마다 다를 수 있어 인자로 뺀다.
    [string]$ProcessName = 'slack-bot',
    [string]$WatchPath = 'slack-bot',
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'run-slackbot-restart-check.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Unregistered: $TaskName"
    return
}

# 등록 전 3중 게이트 — giip #2431/#2591
. (Join-Path $ScriptDir 'task-target-guard.ps1')
Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName

# 엔진: Windows PowerShell 5.1 고정. pm2 CLI 호출·`pm2 describe` 텍스트 파싱이 그 환경에서
# 실측 검증된 조합이고, `pwsh` 는 이 PC 에 없다(giip #2559).
$engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -ProcessName `"$ProcessName`" -WatchPath `"$WatchPath`""
$action  = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# StartBoundary 는 오늘 00:37(이미 지난 시각이어도 무방 — 반복 트리거라 다음 :37 부터 돈다).
# 정상 형태 (A): Once + PT1H 반복, 기간 P3650D (giip #2480 / #1275).
$start   = (Get-Date -Hour 0 -Minute 37 -Second 0)
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# 등록 직전 주기 게이트 — giip #2480(회귀 방지용으로 함께 건다).
. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: slack-bot 배포 커밋 변경 감지 + 유휴 시에만 pm2 restart (giip #2148 옵션 b, 이식 #2645, 매시 :37)'

Write-Output "Registered: $TaskName (hourly at :37, engine=$engine)"
Write-Output "DryRun test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`" -DryRun"
