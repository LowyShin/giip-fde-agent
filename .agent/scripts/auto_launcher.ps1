param(
    [int]$IntervalSeconds = 120,
    [string]$TargetWindowTitle = "Agent Manager"
)

$scriptPath = Join-Path $PSScriptRoot "launch_role.ps1"
$checkStatusPath = Join-Path $PSScriptRoot "check_status.ps1"
$dispatchDir = Join-Path $PSScriptRoot "..\dispatch"

# ---------------------------------------------------------
# Win32 API Wrapper for Robust Window Focusing
# ---------------------------------------------------------
$win32Code = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class AgentWindowHelper {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private const int SW_RESTORE = 9;

    public static bool FocusWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return false;
        
        // Restore if minimized
        if (IsIconic(hWnd)) {
            ShowWindow(hWnd, SW_RESTORE);
        }
        
        return SetForegroundWindow(hWnd);
    }

    public static Dictionary<IntPtr, string> GetOpenWindows() {
        var windows = new Dictionary<IntPtr, string>();
        
        EnumWindows((hWnd, lParam) => {
            int length = GetWindowTextLength(hWnd);
            if (length > 0) {
                var sb = new StringBuilder(length + 1);
                GetWindowText(hWnd, sb, sb.Capacity);
                string title = sb.ToString();
                
                // Simple filter to reduce noise (optional)
                if (!string.IsNullOrWhiteSpace(title)) {
                    windows[hWnd] = title;
                }
            }
            return true;
        }, IntPtr.Zero);

        return windows;
    }
}
"@

Add-Type -TypeDefinition $win32Code

# ---------------------------------------------------------
# Main Script
# ---------------------------------------------------------

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   GIIP Agent Auto-Launcher v3.0" -ForegroundColor Cyan
Write-Host "   (Win32 API Enhanced)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Window Selection Helper
function Select-Window {
    Write-Host "`nScanning open windows..." -ForegroundColor Gray
    $windows = [AgentWindowHelper]::GetOpenWindows()
    $titles = $windows.Values | Sort-Object | Select-Object -Unique

    Write-Host "`n=== Detected Windows (Partial List) ===" -ForegroundColor Yellow
    $i = 0
    foreach ($t in $titles) {
        if ($t -match "Agent" -or $t -match "Code" -or $t -match "Visual" -or $t -match "Chrome" -or $t -match "Edge") {
            Write-Host "  $t" -ForegroundColor White
        }
        $i++
    }
    Write-Host "=======================================" -ForegroundColor Yellow
    
    $input = Read-Host "Enter the EXACT unique part of the Window Title (or 'list' for all)"
    if ($input -eq 'list') {
        $titles | ForEach-Object { Write-Host $_ }
        return Select-Window
    }
    return $input
}

if ([string]::IsNullOrWhiteSpace($TargetWindowTitle)) {
    $TargetWindowTitle = Select-Window
}
else {
    # Check if we can find it immediately
    $windows = [AgentWindowHelper]::GetOpenWindows()
    $match = $windows.Values | Where-Object { $_ -match [System.Text.RegularExpressions.Regex]::Escape($TargetWindowTitle) } | Select-Object -First 1
    
    if (-not $match) {
        Write-Host "Warning: Could not find window matching '$TargetWindowTitle' at startup." -ForegroundColor Red
        $doSelect = Read-Host "Do you want to scan for it? (Y/n)"
        if ($doSelect -ne 'n') {
            $TargetWindowTitle = Select-Window
        }
    }
    else {
        Write-Host "Target identified: '$match'" -ForegroundColor Green
    }
}


Write-Host "`nWatching for Pending Tasks..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop.`n"

while ($true) {
    # 1. Periodically Report Status
    $currentTime = Get-Date -Format "HH:mm:ss"
    Write-Host "`n[$currentTime] Checking Status..." -ForegroundColor DarkGray
    
    if (Test-Path $checkStatusPath) {
        & $checkStatusPath
    }

    # 2. Check for pending files
    $pendingFile = Get-ChildItem -Path $dispatchDir -Filter "*.md" | Where-Object { 
        $_ -is [System.IO.FileInfo] -and $_.Name -ne "TASK_TEMPLATE.md"
    } | Where-Object {
        (Get-Content $_.FullName -TotalCount 10) -match "\*\*Status\*\*:\s*Pending" -or (Get-Content $_.FullName -TotalCount 10) -match "\*\*Status:\*\*\s*Pending" 
    } | Select-Object -First 1

    if ($pendingFile) {
        $fileName = $pendingFile.Name
        Write-Host "`n[AutoLauncher] Pending task detected: $fileName" -ForegroundColor Green
        
        # Snapshot existing windows BEFORE launching new one
        $windowsBefore = [AgentWindowHelper]::GetOpenWindows()
        
        # Initial Launch - This prepares the clipboard
        & $scriptPath -TaskFile $fileName -Role auto

        [System.Console]::Beep(1000, 200)
        
        # 3. Modern Antigravity Workflow: No new window launch
        $projectRoot = Resolve-Path "$PSScriptRoot\..\.."
        Write-Host "[AutoLauncher] MODERN WORKFLOW: Sequential execution in current Antigravity Tool (Skipping window launch)" -ForegroundColor Cyan
        
        # 4. WAIT FOR NEW WINDOW (Skipped in Modern Workflow)
        # In modern workflow, we don't wait for a new handle as we remain in the same tool.
        $foundNewWindow = $false
        $targetHwnd = [IntPtr]::Zero
        
        # In Modern Workflow, we just notify and return.
        Write-Host "[AutoLauncher] MODERN WORKFLOW: Context ready in clipboard. Antigravity will handle it here." -ForegroundColor Gray
        Start-Sleep -Seconds 1
        # No loop, no timeout, just resume monitoring.
    }
    else {
        Start-Sleep -Seconds $IntervalSeconds
    }
}
