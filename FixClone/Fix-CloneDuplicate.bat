@echo off
:: Tu nang quyen Administrator roi chay script PowerShell cung thu muc
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-CloneDuplicate.ps1" %*
pause
