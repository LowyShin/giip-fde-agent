# Agent Lightning Setup Guide for Windows (WSL2)
Write-Host "Checking for WSL2 environment..." -ForegroundColor Cyan

$isWsl = (uname -a).Contains("microsoft") 2>$null
if (-not $isWsl) {
    Write-Host "Warning: Agent Lightning requires Linux or WSL2." -ForegroundColor Yellow
    Write-Host "If you are on Windows, please run this script inside a WSL2 terminal." -ForegroundColor White
    Write-Host "For installation instructions for WSL2, see: https://learn.microsoft.com/en-us/windows/wsl/install" -ForegroundColor Blue
}

Write-Host "`nTo install Agent Lightning, run the following commands in your Linux/WSL2 terminal:" -ForegroundColor Cyan
Write-Host "1. python3 -m venv .agl_venv" -ForegroundColor Green
Write-Host "2. source .agl_venv/bin/activate" -ForegroundColor Green
Write-Host "3. pip install agentlightning" -ForegroundColor Green

Write-Host "`nOnce installed, you can start the dashboard using:" -ForegroundColor Cyan
Write-Host "agl-dashboard" -ForegroundColor Green
