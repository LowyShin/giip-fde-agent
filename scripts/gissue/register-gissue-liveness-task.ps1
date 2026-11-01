# register-gissue-liveness-task.ps1 — GIIP_GissueLiveness_Hourly 작업 스케줄러 등록(멱등) (giip 4411)
#
# 매시 :37 에 check-gissue-liveness.ps1 을 실행한다(처리 본체가 :07 에 돌므로 30분 어긋나게 둔다).
# 재실행하면 기존 태스크를 갱신한다. 해제: -Unregister.
#
# ★ 설계 원칙(사양서 hourly-issue-scheduler.md §16): 이 감시자는 **감시 대상과 다른 독립 태스크**여야 한다.
#   감시자가 처리 본체와 같은 경로(같은 태스크·같은 러너·run-gissue-claude.ps1 안)로 돌면 같은 장애에 같이
#   죽어서 아무도 알리지 못한다. 그래서 GIIP_Gissue_Claude 에 끼워 넣지 않고 별도 태스크로 등록한다.
#
# 사용 (사람이 정상 체크아웃에서 실행. 이 PC 에는 pwsh 가 없으므로 항상 powershell):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gissue-liveness-task.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gissue-liveness-task.ps1 -OpsCsn <csn>
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gissue-liveness-task.ps1 -Unregister
# -OpsCsn 을 주면 무소식 시 그 CSN 에 [OPS] 이슈를 등록한다(-Notify 전달). 안 주면 점검 결과가 태스크의
# LastTaskResult(1 = 무소식)로만 남는다.
param(
    [string]$TaskName = 'GIIP_GissueLiveness_Hourly',
    [string]$OpsCsn = '',
    [double]$MaxSilentHours = 3,
    [switch]$Unregister
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Target    = Join-Path $ScriptDir 'check-gissue-liveness.ps1'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Unregistered: $TaskName"
    return
}

# 등록 전 게이트: 대상 존재·파싱·BOM·임시 worktree 경로 아님 (giip #2431/#2591)
. (Join-Path $ScriptDir 'task-target-guard.ps1')
Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName

$engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

$runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Target`" -MaxSilentHours $MaxSilentHours"
if ($OpsCsn) {
    if ($OpsCsn -notmatch '^\d+$') { throw "-OpsCsn 은 숫자여야 합니다: $OpsCsn" }
    $runnerArgs += " -Notify -OpsCsn $OpsCsn"
}
$action = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir

# 매시 :37. RepetitionDuration 은 [TimeSpan]::MaxValue 금지(0x80041318, giip #1275) → 3650일.
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 37 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

. (Join-Path $ScriptDir 'task-cadence-guard.ps1')
Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -Description 'GIIP: gissue 처리 무소식 점검 (giip 4411, 처리 본체와 독립 태스크, 매시 :37)'

Write-Output "Registered: $TaskName (hourly at :37, engine=$engine)"
Write-Output "Test: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Target`""
