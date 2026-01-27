$dispatchDir = Resolve-Path "..\dispatch"
if (-not (Test-Path $dispatchDir)) {
    Write-Host "Dispatch directory not found: $dispatchDir"
    exit
}

# Keep track of last write times for files
$fileStates = @{}

Write-Host "Monitoring $dispatchDir for new or updated tasks..."
Write-Host "Press Ctrl+C to stop."

while ($true) {
    $files = Get-ChildItem -Path $dispatchDir -Filter "*.md"
    
    foreach ($file in $files) {
        $path = $file.FullName
        $lastWriteTime = $file.LastWriteTime.Ticks

        # Check if file is new or modified
        if (-not $fileStates.ContainsKey($path) -or $fileStates[$path] -ne $lastWriteTime) {
            $fileStates[$path] = $lastWriteTime
            
            # Read logic
            try {
                $content = Get-Content $path -Raw
                if ($content -match "\*\*Status:\*\* Pending" -and $content -match "\*\*Target Role:\*\* (.*)") {
                    $role = $matches[1].Trim()
                    $taskId = "Unknown"
                    if ($content -match "\*\*Task ID:\*\* (.*)") {
                        $taskId = $matches[1].Trim()
                    }

                    Write-Host "`n[TRIGGER DETECTED] Task Updated: $($file.Name)" -ForegroundColor Green
                    Write-Host "Task ID: $taskId" -ForegroundColor White
                    Write-Host "Target Role: $role" -ForegroundColor Yellow
                    Write-Host "Action: Please start a new session with the '$role' role." -ForegroundColor Cyan
                    
                    [System.Console]::Beep(800, 500)
                }
            }
            catch {
                # Ignore read errors (file might be locked)
            }
        }
    }
    Start-Sleep -Seconds 2
}
