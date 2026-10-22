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
#>
param(
    [ValidateSet('Status', 'Request', 'DryRun', 'RunOnce')]
    [string]$Action = 'Status',

    [string]$OnlyCsn = '',

    [string]$TaskName = 'GIIP_Gissue_Claude',

    # Auxiliary hourly schedulers registered by register-*-task.ps1 (see docs/60-operations/
    # aux-hourly-schedulers.md). Status only — this helper never registers or starts them.
    [string[]]$AuxTaskNames = @(
        'GIIP_StalePending_Hourly',
        'GIIP_StaleReview_Hourly',
        'GIIP_AuditReviewPrs_Hourly',
        'GIIP_GateEscalation_Hourly',
        'GIIP_SlackbotRestart_Hourly'
    ),

    [int]$Tail = 8
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $Root 'run-gissue-claude.ps1'
$MapFile = Join-Path $Root 'csn-projects.json'
$LogDir = Join-Path $Root 'logs'

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
    if (-not (Test-Path $MapFile)) { return @() }
    $json = Get-Content -LiteralPath $MapFile -Raw | ConvertFrom-Json
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

function Show-Status {
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
        $locks = @(Get-ChildItem -LiteralPath $LogDir -Filter 'gissue_csn*.lock' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object Name, LastWriteTime, Length)
        if ($locks.Count -eq 0) { Write-Output 'No active lock files.' } else { $locks | Format-Table -AutoSize }
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
