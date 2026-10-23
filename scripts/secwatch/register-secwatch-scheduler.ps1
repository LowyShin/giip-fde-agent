<#
register-secwatch-scheduler.ps1
secwatch 보안점검 스윕(secevt_run.py)을 Windows 작업스케줄러에 N분 주기로 등록/해제/확인한다.
표준 관례: scripts/register-hourly-issue-scheduler.ps1 과 동일한 register-*.ps1 패턴.
운영 정본: docs/60-operations/secwatch-agent.md.

리눅스는 cron 을 쓴다(작업스케줄러 cmdlet 없음). ops 문서 §리눅스 참고:
  */5 * * * *  /usr/bin/python3 /path/giip-fde-agent/scripts/secwatch/secevt_run.py --config /etc/giip/secwatch.sources.json

사용 예:
  # 5분 주기로 등록(기본)
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-secwatch-scheduler.ps1 `
    -Action Register -Config "C:\giip\secwatch.sources.json"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-secwatch-scheduler.ps1 -Action Status
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-secwatch-scheduler.ps1 -Action Unregister
#>
param(
    [ValidateSet('Register', 'Unregister', 'Status')]
    [string]$Action = 'Status',
    [string]$Config = '',
    [int]$IntervalMinutes = 5,
    [string]$TaskName = 'giip-secwatch-sweep',
    [string]$Python = ''
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'secevt_run.py'

function Resolve-Python {
    if ($Python) { return $Python }
    foreach ($c in @('python', 'python3', 'py')) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "python 실행기를 찾지 못했습니다. -Python 으로 경로를 지정하세요."
}

switch ($Action) {
    'Status' {
        $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($t) { Write-Host "[secwatch] 등록됨: $TaskName ($($t.State))"; $t | Get-ScheduledTaskInfo | Format-List LastRunTime, NextRunTime, LastTaskResult }
        else { Write-Host "[secwatch] 미등록: $TaskName" }
    }
    'Unregister' {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "[secwatch] 등록 해제: $TaskName"
        } else { Write-Host "[secwatch] 이미 미등록: $TaskName" }
    }
    'Register' {
        if (-not (Test-Path $runner)) { throw "secevt_run.py 없음: $runner" }
        $py = Resolve-Python
        $argLine = "`"$runner`""
        if ($Config) {
            if (-not (Test-Path $Config)) { Write-Warning "Config 경로가 아직 없습니다: $Config (등록은 진행; 스윕 시 필요)" }
            $argLine += " --config `"$Config`""
        }
        $action = New-ScheduledTaskAction -Execute $py -Argument $argLine -WorkingDirectory $PSScriptRoot
        # N분마다 무기한 반복
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration ([TimeSpan]::MaxValue)
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "giip secwatch 보안점검 스윕(secevt_run.py), ${IntervalMinutes}분 주기 (giip #3833)" -Force | Out-Null
        Write-Host "[secwatch] 등록 완료: $TaskName ($IntervalMinutes 분 주기) → $py $argLine"
    }
}
