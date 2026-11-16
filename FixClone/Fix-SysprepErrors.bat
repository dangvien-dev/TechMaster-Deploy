@echo off
:: Kiem tra va sua loi sysprep validate. Tu nang quyen Administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-SysprepErrors.ps1" %*
pause
