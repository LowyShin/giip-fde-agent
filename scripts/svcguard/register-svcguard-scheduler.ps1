<#
register-svcguard-scheduler.ps1 — svcguard 측정/조건부 재기동 러너를 Windows 작업 스케줄러에 등록한다.

#>
# 목적
#   `restart-service-on-memory.ps1` 를 **SYSTEM 계정** 예약 태스크로 주기 실행시킨다.
#   SYSTEM 이 아닌 계정으로는 서비스 재기동이 "Cannot open <서비스>" 로 실패한다(권한 부족).
#   측정은 어느 계정에서도 되지만 재기동까지 하려면 SYSTEM(또는 관리자) 권한이 필요하다.
#
# 등록은 **사람이 관리자 권한으로 1회** 실행한다(무인 자동 등록 아님).
#   - 관리자 권한 Powershell 을 열고 아래 명령을 1번 실행하면 끝이다.
#   - 예약 태스크는 정상 체크아웃(임시 worktree 아님)에서 등록해야 한다 —
#     task-target-guard.ps1 가 임시 worktree 경로의 등록을 거부한다(giip #2431).
#
# 사용 예
#   # 등록 미리보기(아무것도 등록하지 않고 태스크 정의를 출력)
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Register -WhatIf
#   # 실제 등록(관리자 권한 Powershell 에서 1회)
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Register -SampleIntervalMinutes 10
#   # 상태 조회 / 해제
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Status
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Unregister
#
# 파라미터
#   -ServiceName              대상 서비스 이름(러너에 그대로 전달)
#   -ThresholdMB              재기동 기준 PrivateBytes(MB)(러너에 그대로 전달)
#   -MinRestartIntervalMinutes 재기동 최소 간격(분)(러너에 그대로 전달)
#   -SampleIntervalMinutes    예약 태스크 실행 주기(분). 기본 10분.
#   -BaselineSampleCount      기준선 계산용 최근 샘플 개수(러너에 그대로 전달)
#   -TaskName                 예약 태스크 이름. 기본 "giip-svcguard-<서비스>"
#   -WhatIf                   등록하지 않고 만들 태스크 정의만 출력한다(Register 한정)
#>
param(
    [ValidateSet('Register', 'Unregister', 'Status')]
    [string]$Action = 'Status',
    [string]$ServiceName = 'PcaSvc',
    [int]$ThresholdMB = 1024,
    [int]$MinRestartIntervalMinutes = 60,
    [int]$SampleIntervalMinutes = 10,
    [int]$BaselineSampleCount = 24,
    [string]$TaskName = '',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Runner = Join-Path $ScriptDir 'restart-service-on-memory.ps1'
if (-not $TaskName) { $TaskName = "giip-svcguard-{0}" -f $ServiceName }

if ($SampleIntervalMinutes -lt 1) { throw "-SampleIntervalMinutes 는 1 이상이어야 합니다: $SampleIntervalMinutes" }
if ($ThresholdMB -lt 0) { throw "-ThresholdMB 는 0 이상이어야 합니다: $ThresholdMB" }
if ($MinRestartIntervalMinutes -lt 0) { throw "-MinRestartIntervalMinutes 는 0 이상이어야 합니다: $MinRestartIntervalMinutes" }

function Test-SvcGuardAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

switch ($Action) {
    'Status' {
        $task = $null
        try { $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
        if (-not $task) {
            Write-Output "[svcguard] 미등록: $TaskName"
            exit 0
        }
        Write-Output "[svcguard] 등록됨: $TaskName (상태: $($task.State))"
        try {
            $info = $task | Get-ScheduledTaskInfo
            Write-Output ("  마지막 실행: {0} | 다음 실행: {1} | 마지막 결과: {2}" -f $info.LastRunTime, $info.NextRunTime, $info.LastTaskResult)
        } catch {
            Write-Output "  (실행 정보 조회 실패: $($_.Exception.Message))"
        }
        exit 0
    }

    'Unregister' {
        $existing = $null
        try { $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
        if (-not $existing) {
            Write-Output "[svcguard] 이미 미등록: $TaskName"
            exit 0
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Output "[svcguard] 등록 해제: $TaskName"
        exit 0
    }

    'Register' {
        $engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
        if (-not $engine) { throw 'powershell.exe 를 찾을 수 없습니다(Windows PowerShell 5.1 필요).' }

        $runnerArgs = "-NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$Runner`" -ServiceName `"$ServiceName`" -ThresholdMB $ThresholdMB -MinRestartIntervalMinutes $MinRestartIntervalMinutes -BaselineSampleCount $BaselineSampleCount"
        $taskAction = New-ScheduledTaskAction -Execute $engine -Argument $runnerArgs -WorkingDirectory $ScriptDir
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $SampleIntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

        if ($WhatIf) {
            Write-Output "[svcguard] 등록 미리보기(아무것도 등록하지 않습니다)"
            Write-Output "  태스크 이름 : $TaskName"
            Write-Output "  실행       : $engine $runnerArgs"
            Write-Output "  주기       : $SampleIntervalMinutes 분 (RepetitionDuration 3650일)"
            Write-Output "  계정       : SYSTEM (ServiceAccount, RunLevel Highest)"
            Write-Output "  작업 폴더  : $ScriptDir"
            Write-Output "  참고       : 실제 등록은 관리자 권한이 필요하고, 임시 worktree 경로에서는 거부됩니다."
            exit 0
        }

        if (-not (Test-SvcGuardAdministrator)) {
            throw 'SYSTEM 계정 예약 태스크를 등록하려면 관리자 권한 Powershell 로 실행해야 합니다.'
        }

        # ── 등록 전 게이트 ────────────────────────────────────────────────────────
        # (1) 대상 .ps1 존재 / 파싱 / 임시 worktree 아님  → scripts/gissue/task-target-guard.ps1
        # (2) 태스크 이름이 약속한 주기와 실제 반복 설정이 일치하는지 → scripts/gissue/task-cadence-guard.ps1
        #     + 아래 자체 반복 간격 검사(태스크 이름이 주기를 약속하지 않아 cadence-guard 는 SKIP 하므로)
        $guardDir = Join-Path (Split-Path -Parent $ScriptDir) 'gissue'
        . (Join-Path $guardDir 'task-target-guard.ps1')
        . (Join-Path $guardDir 'task-cadence-guard.ps1')

        Assert-ScheduledTaskTarget -Target $Runner -TaskName $TaskName
        Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger

        $expectedInterval = New-TimeSpan -Minutes $SampleIntervalMinutes
        $actualInterval = $null
        if ($trigger -and $trigger.Repetition -and $trigger.Repetition.Interval) {
            try { $actualInterval = [System.Xml.XmlConvert]::ToTimeSpan([string]$trigger.Repetition.Interval) } catch { $actualInterval = $null }
        }
        if ($null -eq $actualInterval -or $actualInterval -ne $expectedInterval) {
            Write-Output ("[svcguard][BLOCKED] 반복 간격 불일치: 기대 {0}, 실제 {1} — 등록 중단" -f $expectedInterval, $actualInterval)
            exit 1
        }
        Write-Output ("[svcguard] 반복 간격 검사 통과: {0}" -f $expectedInterval)

        Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $trigger -Settings $settings -Principal $principal `
            -Description "svcguard: 서비스 상주 메모리 측정 + 임계 초과 시 조건부 재기동 ($ServiceName, ${ThresholdMB}MB, ${SampleIntervalMinutes}분 주기)" -Force | Out-Null

        Write-Output "[svcguard] 등록 완료: $TaskName ($SampleIntervalMinutes 분 주기, SYSTEM 계정)"
        Write-Output "  상태 조회: powershell -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Action Status -ServiceName `"$ServiceName`""
        Write-Output "  로그      : $(Join-Path $ScriptDir ("logs\svcguard-{0}.jsonl" -f $ServiceName))"
        exit 0
    }
}
