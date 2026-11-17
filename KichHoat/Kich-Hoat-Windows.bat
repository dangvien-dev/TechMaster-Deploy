@echo off
:: Kich hoat Windows: online truoc, that bai thi qua Product Activation Portal
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Kich-Hoat.ps1" -Product Windows
