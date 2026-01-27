@echo off
:loop
echo [%date% %time%] Launching Agent Subsession...
pwsh -Command ".\.agent\scripts\launch_subsession.ps1"
echo [%date% %time%] Waiting for 5 minutes (300 seconds) before next check...
timeout /t 300 /nobreak
goto loop
