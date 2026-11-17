@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Run-Sysprep.ps1"
exit /b %errorlevel%
