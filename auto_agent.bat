@echo off
rem Windows 배치 — Windows PowerShell 5.1 로 고정 호출한다.
rem (pwsh 를 부르면 PowerShell 7 이 없는 PC 에서 command not found 로 아무 일도 하지 않고 끝난다 — giip #2559)
:loop
echo [%date% %time%] Launching Agent Subsession...
powershell -NoProfile -ExecutionPolicy Bypass -File ".agent\scripts\launch_subsession.ps1"
echo [%date% %time%] Waiting for 5 minutes (300 seconds) before next check...
timeout /t 300 /nobreak
goto loop
