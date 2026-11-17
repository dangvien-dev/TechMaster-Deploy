@echo off
:: Chay duoi dung user khach hang, khong tu nang quyen.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-BanPhim.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%
