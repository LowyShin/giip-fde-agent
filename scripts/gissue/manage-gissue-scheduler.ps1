<#
GIIP gissue scheduler control helper. (ported from lowyworkenv, giip #2645)

Actions:
  Status  - show Windows Task status (main + aux), CSN map, recent locks/logs
  Request - ask Windows Task Scheduler to start the main task now
  DryRun  - run run-gissue-claude.ps1 -DryRun
  RunOnce - run run-gissue-claude.ps1 immediately in this console

Run it with Windows PowerShell 5.1 (`powershell.exe`). PowerShell 7 (`pwsh`) is NOT assumed to exist:
calling it by that name silently does nothing when it is absent (giip #2559).

  powershell -NoProfile -ExecutionPolicy Bypass -File .\manage-gissue-scheduler.ps1 -Action Status
  powershell -NoProfile -ExecutionPolicy Bypass -File .\manage-gissue-scheduler.ps1 -Action DryRun -OnlyCsn <csn>

Paths are resolved relative to this file, so a fresh clone works without editing anything.
Task names are deployment-specific: override -TaskName / -AuxTaskNames when one PC hosts more
than one deployment.

Log/lock locations (giip 5054): -Action Status reads the log/lock directory and the CSN map of
THIS deployment only, so "no locks / no CSN targets" can be false when the scheduler actually runs
from a different deployment directory. Point -LogDir / -ConfigPath at the runtime paths to see them:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\manage-gissue-scheduler.ps1 -Action Status -LogDir <runtime-log-dir> -ConfigPath <runtime-csn-projects.json>
#>
param(
    [ValidateSet('Status', 'Request', 'DryRun', 'RunOnce')]
    [string]$Action = 'Status',

    [string]$OnlyCsn = '',

    [string]$TaskName = 'GIIP_Gissue_Claude',

    # 로그·락 디렉터리. 비우면 이 스크립트 옆 기본값(<script-dir>\logs).
    # 배포마다 로그 위치가 다를 수 있으므로, 실제 런타임 경로를 지정할 수 있게 한다 (giip 5054).
    [string]$LogDir = '',

    # CSN 맵(csn-projects.json). 비우면 이 스크립트 옆 기본값(<script-dir>\csn-projects.json).
    [string]$ConfigPath = '',

    # 락이 이 시간(시) 이상 묵으면 멈춘 실행으로 본다(살아있는 PID 여도 진행 중으로 치지 않는다).
    # check-gissue-liveness.ps1 과 같은 기준값을 쓴다.
    [double]$StaleLockHours = 2,

    # Auxiliary hourly schedulers registered by register-*-task.ps1 (see docs/60-operations/
    # aux-hourly-schedulers.md). Status only — this helper never registers or starts them.
    [string[]]$AuxTaskNames = @(
        'GIIP_StalePending_Hourly',
        'GIIP_StaleReview_Hourly',
        'GIIP_AuditReviewPrs_Hourly',
        'GIIP_GateEscalation_Hourly',
        'GIIP_SlackbotRestart_Hourly',
        'GIIP_GissueLiveness_Hourly'
    ),

    [int]$Tail = 8
)

$ErrorActionPreference = 'Stop'
# 콘솔 출력 인코딩을 UTF-8 로 고정한다 — 이 PC 기본 코드페이지(cp932) 로는 아래 한글 라벨
# ("로그 디렉터리:" 등)이 깨져 사람도 기계도 못 읽는다 (같은 묶음 도구들의 공통 관례).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $Root 'run-gissue-claude.ps1'

# 경로 파라미터의 기본값(=이 저장소 기준). 지정값과 비교해 "이 저장소 기준이 아님" 을 표시한다 (giip 5054).
$DefaultLogDir = Join-Path $Root 'logs'
$DefaultConfigPath = Join-Path $Root 'csn-projects.json'
if (-not $LogDir)     { $LogDir = $DefaultLogDir }
if (-not $ConfigPath) { $ConfigPath = $DefaultConfigPath }

# 락 해석(PID·생존 판정)은 liveness 라이브러리를 재사용한다 — 같은 판정을 두 벌 만들지 않는다.
$LivenessLib = Join-Path (Join-Path $Root 'lib') 'gissue-liveness-lib.ps1'
if (Test-Path -LiteralPath $LivenessLib) { . $LivenessLib }

function Write-Section($title) {
    Write-Output ''
    Write-Output "## $title"
}

function Get-TaskInfoFor($name) {
    try {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
        # Repetition is what proves an "_Hourly" task actually runs hourly. LastTaskResult=0 does not
        # (a task whose trigger has no repetition ran once a day and still returned 0 — giip #2480).
        $rep = $null
        try { $rep = ($task.Triggers | ForEach-Object { $_.Repetition.Interval } | Where-Object { $_ }) -join ',' } catch { }
        [pscustomobject]@{
            TaskName       = $name
            State          = $task.State
            Enabled        = ($task.Settings.Enabled -ne $false)
            Repetition     = if ($rep) { $rep } else { '(none)' }
            LastRunTime    = $info.LastRunTime
            LastTaskResult = $info.LastTaskResult
            NextRunTime    = $info.NextRunTime
        }
    } catch {
        [pscustomobject]@{
            TaskName       = $name
            State          = 'NOT_FOUND'
            Enabled        = $false
            Repetition     = '(none)'
            LastRunTime    = $null
            LastTaskResult = $null
            NextRunTime    = $null
        }
    }
}

function Get-TaskInfo { Get-TaskInfoFor $TaskName }

function Get-CsnMap {
    if (-not (Test-Path $ConfigPath)) { return @() }
    $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $items = @()
    foreach ($prop in $json.csn.PSObject.Properties) {
        if ($OnlyCsn -and $prop.Name -ne $OnlyCsn) { continue }
        $entry = $prop.Value
        $items += [pscustomobject]@{
            Csn     = $prop.Name
            Project = $entry.project
            Enabled = ($entry.enabled -ne $false)
            Workdir = $entry.workdir
            Exists  = (Test-Path $entry.workdir)
        }
    }
    return $items
}

function Get-RecentLogLines($csn) {
    if (-not (Test-Path $LogDir)) { return @() }
    $files = @(
        (Join-Path $LogDir "gissue_csn$csn.log"),
        (Join-Path $LogDir "gissue_csn$csn.out.log")
    )
    $lines = @()
    foreach ($file in $files) {
        if (Test-Path $file) {
            $lines += Get-Content -LiteralPath $file -Tail $Tail | ForEach-Object {
                [pscustomobject]@{ File = (Split-Path -Leaf $file); Line = $_ }
            }
        }
    }
    return $lines
}

function Get-LockState {
    # 락 파일 1건의 PID·생존 상태. 판정 로직은 liveness 라이브러리를 재사용한다(두 벌 만들지 않는다).
    # 라이브러리가 없으면 판정 불가로 표시한다 — 조용히 "정상" 으로 보이면 안 된다.
    param([string]$LockPath, [datetime]$Now)
    if (Get-Command -Name Get-LivenessLock -CommandType Function -ErrorAction SilentlyContinue) {
        $lock = Get-LivenessLock -LockPath $LockPath -Now $Now -StaleLockHours $StaleLockHours
        return [pscustomobject]@{ Pid = $lock.Pid; State = $lock.State; AgeHours = $lock.AgeHours }
    }
    return [pscustomobject]@{ Pid = $null; State = 'UNKNOWN'; AgeHours = $null }
}

function Show-Status {
    # 조회 경로를 맨 위에 명시한다 — "락 0건 / CSN 0건" 이 실제 런타임과 반대일 수 있으므로 (giip 5054).
    $logNote = if ($LogDir -eq $DefaultLogDir) { '이 저장소 기준(기본값)' } else { '지정 경로(기본값 아님)' }
    $cfgNote = if ($ConfigPath -eq $DefaultConfigPath) { '이 저장소 기준(기본값)' } else { '지정 경로(기본값 아님)' }
    Write-Output "로그 디렉터리: $LogDir ($logNote)"
    Write-Output "CSN 맵: $ConfigPath ($cfgNote)"
    if ($LogDir -ne $DefaultLogDir -or $ConfigPath -ne $DefaultConfigPath) {
        Write-Output '※ 기본 경로가 아닌 디렉터리를 보고 있습니다 — 지정 경로에 로그·락·CSN 맵이 있어야 표시됩니다.'
    }
    Write-Output ''

    Write-Section 'Scheduled Task'
    Get-TaskInfo | Format-List

    Write-Section 'Auxiliary Hourly Schedulers'
    # NOT_FOUND here just means this deployment has not registered that aux task (register-*-task.ps1).
    @($AuxTaskNames | ForEach-Object { Get-TaskInfoFor $_ }) |
        Format-Table TaskName, State, Repetition, LastRunTime, LastTaskResult, NextRunTime -AutoSize

    Write-Section 'CSN Targets'
    $targets = @(Get-CsnMap)
    if ($targets.Count -eq 0) {
        Write-Output 'No CSN targets found.'
    } else {
        $targets | Format-Table -AutoSize
    }

    Write-Section 'Locks'
    if (Test-Path $LogDir) {
        $lockFiles = @(Get-ChildItem -LiteralPath $LogDir -Filter 'gissue_csn*.lock' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($lockFiles.Count -eq 0) {
            Write-Output 'No active lock files.'
        } else {
            # "락이 죽은 프로세스의 것인지"를 상태 조회만으로 판정할 수 있게 PID·상태를 함께 보여준다 (giip 5054).
            $lockNow = Get-Date
            $locks = @($lockFiles | ForEach-Object {
                $st = Get-LockState -LockPath $_.FullName -Now $lockNow
                [pscustomobject]@{
                    Name          = $_.Name
                    LastWriteTime = $_.LastWriteTime
                    Length        = $_.Length
                    Pid           = if ($null -ne $st.Pid) { $st.Pid } else { '' }
                    State         = $st.State
                }
            })
            $locks | Format-Table -AutoSize
        }
    } else {
        Write-Output 'Log directory does not exist.'
    }

    Write-Section 'Recent Logs'
    foreach ($target in $targets) {
        Write-Output "### CSN $($target.Csn) / $($target.Project)"
        $recent = @(Get-RecentLogLines $target.Csn)
        if ($recent.Count -eq 0) {
            Write-Output 'No recent log lines.'
        } else {
            $recent | ForEach-Object { Write-Output ("[{0}] {1}" -f $_.File, $_.Line) }
        }
    }
}

switch ($Action) {
    'Status' {
        Show-Status
    }
    'Request' {
        $taskInfo = Get-TaskInfo
        if ($taskInfo.State -eq 'NOT_FOUND') {
            throw "Scheduled task not found: $TaskName"
        }
        if ($OnlyCsn) {
            throw '-OnlyCsn cannot be used with Action=Request because Windows Task Scheduler starts the registered all-CSN task. Use Action=RunOnce or Action=DryRun for a single CSN.'
        }
        Start-ScheduledTask -TaskName $TaskName
        Write-Output "Requested scheduler run: $TaskName"
        Start-Sleep -Seconds 2
        Get-TaskInfo | Format-List
    }
    'DryRun' {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Runner, '-DryRun')
        if ($OnlyCsn) { $args += @('-OnlyCsn', $OnlyCsn) }
        & powershell.exe @args
    }
    'RunOnce' {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Runner)
        if ($OnlyCsn) { $args += @('-OnlyCsn', $OnlyCsn) }
        & powershell.exe @args
    }
}
