@echo off
rem ---------------------------------------------------------------------------
rem Double-clickable wrapper around stop-dsh.ps1.
rem
rem The normal way to stop the harness is to close its browser window. Use this
rem only when that did not happen - for example when the launcher was killed
rem from Task Manager and left the server running with nothing attached.
rem ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-dsh.ps1"
echo.
pause
