param (
    [string]$Role = "auto",
    [string]$TaskFile = "auto",
    [switch]$Headless = $false
)

$rootDir = Resolve-Path "$PSScriptRoot\..\.."
$dispatchDir = Join-Path $rootDir ".agent\dispatch"

# 1. Identify Task and Role (Logic similar to launch_role.ps1)
if ($TaskFile -eq "auto") {
    if (Test-Path $dispatchDir) {
        $files = Get-ChildItem -Path $dispatchDir -Filter "*.md" | Where-Object { $_.Name -ne "TASK_TEMPLATE.md" } | Sort-Object LastWriteTime
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $status = if ($content -match "\*\*Status\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Status:\*\*\s*([^\r\n]*)") { $matches[1].Trim() } else { "Unknown" }
            if ($status -eq "Pending") {
                if ($Role -eq "auto") {
                    if ($content -match "\*\*Target Role\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Target Role:\*\*\s*([^\r\n]*)" -or $content -match "\*\*Role\*\*:\s*([^\r\n]*)") {
                        $detectedRole = $matches[1].Trim()
                        $targetPath = $file.FullName
                        break
                    }
                }
                else {
                    if ($content -match "\*\*Target Role\*\*:\s*$Role" -or $content -match "\*\*Role\*\*:\s*$Role") {
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
        $content = Get-Content $targetPath -Raw -Encoding UTF8
        if ($content -match "\*\*Target Role\*\*:\s*([^\r\n]*)" -or $content -match "\*\*Role\*\*:\s*([^\r\n]*)") {
            $detectedRole = $matches[1].Trim()
        }
    }
}

if (-not $targetPath) {
    Write-Host "No Pending tasks found. Exit." -ForegroundColor Green
    exit 0
}

if ($Role -eq "auto") { $Role = $detectedRole }

# 1.1 Update Task Status to In Progress
if ($targetPath) {
    $taskContent = Get-Content $targetPath -Raw -Encoding UTF8
    if ($taskContent -match "\*\*Status\*\*:\s*Pending") {
        $taskContent = $taskContent -replace "\*\*Status\*\*:\s*Pending", "**Status**: In Progress"
        $taskContent | Set-Content $targetPath -Encoding UTF8
        Write-Host "Updated status to 'In Progress' for $(Split-Path $targetPath -Leaf)" -ForegroundColor Green
    }
}

# 2. Get Role Definition
$roleMap = @{
    "Developer"     = "developer.md"
    "Error Analyst" = "error_analyst.md"
    "Orchestrator"  = "orchestrator.md"
    "Code Reviewer" = "code_reviewer.md"
}

# Normalize role name for mapping and file check
$cleanRole = $Role.Trim()
$roleFile = if ($roleMap[$cleanRole]) { $roleMap[$cleanRole] } else { "$($cleanRole.ToLower().Replace(' ', '_')).md" }
$rolePath = Join-Path $rootDir ".agent\roles\$roleFile"

# 3. Construct Bootstrap Prompt
$prompt = @"
=== SYSTEM BOOTSTRAP (SUB-SESSION) ===
You are the '$Role'.
Please read:
- Role Definition: "$rolePath"
- Task Dispatch: "$targetPath"

Execute the task following all project standards in GEMINI.md.
"@

# 4. Launch Gemini CLI
Write-Host "Launching Gemini CLI for Role: $Role, Task: $(Split-Path $targetPath -Leaf)" -ForegroundColor Cyan

$geminiExe = "gemini"
if (-not (Get-Command $geminiExe -ErrorAction SilentlyContinue)) {
    $candidatePaths = @("$env:ProgramFiles\nodejs\gemini.cmd", "$env:AppData\npm\gemini.cmd")
    foreach ($path in $candidatePaths) { if (Test-Path $path) { $geminiExe = $path; break } }
}

# Ensure API Key is available in the environment for this session
if (-not $env:GEMINI_API_KEY) {
    # 1. Check project-local .agent/settings.json
    $localSettingsPath = Join-Path $rootDir ".agent\settings.json"
    
    # 2. Check global settings if local not found
    $globalSettingsPath = Join-Path $HOME ".gemini\settings.json"
    
    $settingsPath = if (Test-Path $localSettingsPath) { $localSettingsPath } elseif (Test-Path $globalSettingsPath) { $globalSettingsPath } else { $null }

    if ($settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settings.api_key) { $env:GEMINI_API_KEY = $settings.api_key }
    }
}

if ($Headless) { 
    Write-Host "Running in HEADLESS mode with AUTO-APPROVE (-y)" -ForegroundColor Yellow
    & $geminiExe -y -p "$prompt" 
}
else { 
    # Default to auto-approve for now even in non-headless to ensure background execution works
    # But strictly speaking, 'launch_subsession' is typically used for automation.
    & $geminiExe -y -p "$prompt" 
}
