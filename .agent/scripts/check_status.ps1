
$dispatchDir = Join-Path "$PSScriptRoot\..\.." ".agent\dispatch"

if (-not (Test-Path $dispatchDir)) {
    Write-Error "Dispatch directory not found: $dispatchDir"
    exit 1
}

$tasks = @()
$files = Get-ChildItem -Path $dispatchDir -Filter "TASK_*.md" | Where-Object { $_.Name -ne "TASK_TEMPLATE.md" }

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    
    # Robust Regex implementation
    # Supports: **Status:**, Status:, **Status**: , - **Status:** etc.
    $status = if ($content -match "(?i)(?:-?\s*\*?\*?Status\*?\*?:?\s*)\*?\*?([^\r\n\*]*)") { $matches[1].Trim() } else { "Unknown" }
    $role = if ($content -match "(?i)(?:-?\s*\*?\*?(?:Target Role|Role|Agent)\*?\*?:?\s*)\*?\*?([^\r\n\*]*)") { $matches[1].Trim() } else { "Unknown" }
    $id = if ($content -match "(?i)(?:-?\s*\*?\*?Task ID\*?\*?:?\s*)\*?\*?([^\r\n\*]*)") { $matches[1].Trim() } else { "Unknown" }

    $objective = if ($content -match "(?s)## Objective\s*(.*?)(\r?\n#|$)") { $matches[1].Trim() -replace "\r?\n.*", "" } else { "Unknown" }

    # Show anything that is not Completed or Archived
    if ($status -ne "Completed" -and $status -ne "CompletedCompleted" -and $status -ne "Archived" -and $status -ne "Unknown" -and $status -ne "Success") {
        $tasks += [PSCustomObject]@{
            "Task ID"   = $id
            "Role"      = $role
            "Status"    = $status
            "Objective" = $objective
            "File"      = $file.Name
        }
    }
}

if ($tasks.Count -eq 0) {
    Write-Host "No Active Tasks." -ForegroundColor Green
}
else {
    Write-Host "=== ACTIVE TASKS (Logical Status) ===" -ForegroundColor Yellow
    $tasks | Select-Object "Task ID", "Role", "Status", "Objective" | Format-Table -AutoSize -Wrap
}

Write-Host "`n=== ACTIVE SUB-SESSIONS (Background Processes) ===" -ForegroundColor Cyan
# Improved detection using CIM to get CommandLines reliably on Windows
$processes = Get-CimInstance Win32_Process -Filter "Name = 'node.exe' OR Name = 'node'" | Where-Object { 
    $_.CommandLine -match "gemini" 
}
if ($processes) {
    $processes | Select-Object @{N = 'Id'; E = { $_.ProcessId } }, Name, @{N = 'StartTime'; E = { $_.CreationDate } }, CommandLine | Format-Table -AutoSize -Wrap
}
else {
    Write-Host "No active gemini-cli processes detected." -ForegroundColor Gray
}
