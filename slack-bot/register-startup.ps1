# Register the Slack bot (via pm2) to auto-start on user logon.
# Run in an elevated (Administrator) PowerShell session.
#
# Project-agnostic: uses the current user and auto-detects the pm2 launcher.
# Optionally override the pm2 path with the PM2_CMD environment variable.

$user     = $env:USERNAME
$taskName = "PM2-SlackBot-Resurrect"

# Locate pm2: env override → pm2.cmd on PATH → default npm global location for this user
$pm2Path = $env:PM2_CMD
if (-not $pm2Path) {
    $cmd = Get-Command pm2.cmd -ErrorAction SilentlyContinue
    if ($cmd) { $pm2Path = $cmd.Source }
}
if (-not $pm2Path) {
    $pm2Path = Join-Path $env:APPDATA "npm\pm2.cmd"
}
if (-not (Test-Path $pm2Path)) {
    Write-Error "pm2 launcher not found. Install pm2 (npm i -g pm2) or set the PM2_CMD environment variable to its full path."
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "cmd.exe" `
    -Argument "/c `"$pm2Path`" resurrect"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable $true

$principal = New-ScheduledTaskPrincipal `
    -UserId $user `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Auto-start pm2 slack-bot on logon" `
    -Force

Write-Host "Task Scheduler registration complete: $taskName" -ForegroundColor Green
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State
