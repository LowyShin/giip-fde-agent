param(
    [string]$DispatchDir = ".agent\dispatch",
    [bool]$Watch = $false
)

$rootDir = Resolve-Path "$PSScriptRoot\..\.."
$fullDispatchDir = Join-Path $rootDir $DispatchDir

function Check-PendingTasks {
    Write-Host "Checking for Pending tasks in $fullDispatchDir..." -ForegroundColor Gray
    
    if (-not (Test-Path $fullDispatchDir)) {
        Write-Error "Dispatch directory not found: $fullDispatchDir"
        return
    }

    $files = Get-ChildItem -Path $fullDispatchDir -Filter "TASK_*.md" | Where-Object { $_.Name -ne "TASK_TEMPLATE.md" }
    
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        if ($content -match "\*\*Status\*\*:\s*Pending" -or $content -match "\*\*Status:\*\*\s*Pending") {
            $role = if ($content -match "\*\*Target Role\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Target Role:\*\*\s*([^\r\n]*)" -or $content -match "\*\*Role\*\*:\s*([^\r\n]*)") { $matches[1].Trim() } else { "Unknown" }
            $id = if ($content -match "\*\*Task ID\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Task ID:\*\*\s*([^\r\n]*)") { $matches[1].Trim() } else { "Unknown" }
            
            Write-Host "[SYNC] Found Pending Task: $id ($role)" -ForegroundColor Cyan
            
            # Since this script runs locally, we can't 'force' Antigravity to start a task,
            # but we can notify the user or prepare a consolidated context.
            # In Agentic Mode, the Orchestrator (Antigravity) will BE the one creating these files.
        }
    }
}

Check-PendingTasks

if ($Watch) {
    Write-Host "Monitoring for new tasks... (Press Ctrl+C to stop)"
    while ($true) {
        Start-Sleep -Seconds 5
        Check-PendingTasks
    }
}
