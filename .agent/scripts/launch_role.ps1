param (
    [string]$Role = "auto",
    [string]$TaskFile = "auto"
)

$rootDir = Resolve-Path "$PSScriptRoot\..\.."
$dispatchDir = Join-Path $rootDir ".agent\dispatch"

$targetPath = $null
$detectedRole = $null

# 1. Find a pending task if auto
if ($TaskFile -eq "auto") {
    if (Test-Path $dispatchDir) {
        $files = Get-ChildItem -Path $dispatchDir -Filter "*.md" | Where-Object { $_.Name -ne "TASK_TEMPLATE.md" } | Sort-Object LastWriteTime
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            
            # Support both **Status:** and **Status**: formatting, case-insensitive
            $status = if ($content -match "\*\*Status\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Status:\*\*\s*([^\r\n]*)") { $matches[1].Trim() } else { "Unknown" }
            $isPending = ($status -eq "Pending")

            if ($isPending) {
                if ($Role -eq "auto") {
                    if ($content -match "\*\*Target Role\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Target Role:\*\*\s*([^\r\n]*)" -or $content -match "\*\*Role\*\*:\s*([^\r\n]*)") {
                        $detectedRole = $matches[1].Trim()
                        $targetPath = $file.FullName
                        break
                    }
                }
                else {
                    # If role is specified, look for task for that role
                    if ($content -match "\*\*Target Role\*\*:\s*$Role" -or $content -match "\*\*Target Role:\*\*\s*$Role" -or $content -match "\*\*Role\*\*:\s*$Role") {
                        $detectedRole = $Role
                        $targetPath = $file.FullName
                        break
                    }
                }
            }
        }
    }
}
else {
    $targetPath = Join-Path $dispatchDir $TaskFile
    if (Test-Path $targetPath) {
        # Try to detect role from file
        $content = Get-Content $targetPath -Raw -Encoding UTF8
        if ($content -match "\*\*Target Role\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Target Role:\*\*\s*([^\r\n]*)" -or $content -match "\*\*Role\*\*:\s*([^\r\n]*)") {
            $detectedRole = $matches[1].Trim()
        }
    }
}

if (-not $targetPath) {
    Write-Host "No Pending tasks found in $dispatchDir. Nothing to do." -ForegroundColor Green
    exit 0
}

# AUTO-LOCK: Update status to 'In Progress' immediately to prevent race conditions/duplicates
$taskContent = Get-Content $targetPath -Raw -Encoding UTF8
$statusMatch = $taskContent -match "\*\*Status\*\*:\s*Pending" -or $taskContent -match "\*\*Status:\*\*\s*Pending"
if ($statusMatch) {
    $taskContent = $taskContent -replace "\*\*Status\*\*:\s*Pending", "**Status:** In Progress"
    $taskContent = $taskContent -replace "\*\*Status:\*\*\s*Pending", "**Status:** In Progress"
    Set-Content -Path $targetPath -Value $taskContent -Encoding UTF8
    Write-Host "Locked Task: Status updated to 'In Progress'" -ForegroundColor Magenta
}

if ($Role -eq "auto") { $Role = $detectedRole }

Write-Host "Found Task: $(Split-Path $targetPath -Leaf)" -ForegroundColor Cyan
Write-Host "Target Role: $Role" -ForegroundColor Green

# 2. Map Role to File (English Only)
# NOTE: Ensure 'Target Role' in dispatch files is written in English.
$roleMap = @{
    "Developer"           = "developer.md"
    "Tester"              = "tester.md"
    "Error Analyst"       = "error_analyst.md"
    "Proposal Expert"     = "proposal_expert.md"
    "Orchestrator"        = "orchestrator.md"
    "Security Specialist" = "security_specialist.md"
    "Code Auditor"        = "code_auditor.md"
    "User Guide Writer"   = "user_guide_writer.md"
}

$roleFile = $roleMap[$Role]
if (-not $roleFile) {
    # Fallback to lowercase check if direct match fails
    foreach ($key in $roleMap.Keys) {
        if ($key.ToLower() -eq $Role.ToLower()) {
            $roleFile = $roleMap[$key]
            break
        }
    }
    
    # If still not found, try using role name as filename
    if (-not $roleFile) {
        $roleFile = "$($Role.ToLower()).md"
    }
}

$rolePath = Join-Path $rootDir ".agent\roles\$roleFile"

if (-not (Test-Path $rolePath)) {
    Write-Error "Role definition file not found: $rolePath"
    Write-Error "Please ensure .agent/roles/ contains the definition file."
    exit 1
}

# 3. Construct Context Prompt (Bootstrap Mode)
# We do NOT load the full content into the clipboard to avoid encoding/size issues.
# Instead, we give the Agent the paths and tell it to read them.

$prompt = @"
=== SYSTEM BOOTSTRAP ===
You are the '$Role'.

1. **LOAD ROLE DEFINITION**:
   - Please read your role definition file at:
   - File: "$rolePath"

2. **LOAD TASK ASSIGNMENT**:
   - Please read your task dispatch file at:
   - File: "$targetPath"

3. **EXECUTE**:
   - Adopt your role.
   - **FIRST ACTION**: Update the Task File Status from 'Pending' to 'In Progress' (if not already done).
   - Follow the instructions in the task file.
   - Use `task_boundary` to start the task.
"@

# 4. Copy to Clipboard
# Ensure we have consistent CRLF newlines for Windows
$prompt = $prompt -replace "\r?\n", "`r`n"
Set-Clipboard -Value $prompt
Write-Host "OK Role Context copied to clipboard!" -ForegroundColor Green

# 5. Launch New Window (Optional) - DISABLED
# Write-Host "Opening new VS Code window..."
# code -n "$rootDir"

Write-Host "Action Required: Open your AI Chat and PASTE (Ctrl+V) to start." -ForegroundColor Yellow
