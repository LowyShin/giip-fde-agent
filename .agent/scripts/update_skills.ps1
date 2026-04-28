# update_skills.ps1 - Helper script for /gaupdate workflow

param (
    [string]$ConfigPath = ".agent/config/update_urls.json"
)

function Log-Update {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$Timestamp] $Message"
}

if (-Not (Test-Path $ConfigPath)) {
    Log-Update "Error: Configuration file not found at $ConfigPath"
    exit 1
}

$Config = Get-Content $ConfigPath | ConvertFrom-Json
Log-Update "Checking for updates from $($Config.sources.Count) sources..."

# This script is called by the /gaupdate workflow.
# The actual network fetching and file writing is handled by the agent's tools
# for maximum reliability within the environment.

$Config.lastUpdate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
$Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath

Log-Update "Registry updated. Last check time saved."
