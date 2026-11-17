@echo off
:: Chay duoi dung user khach hang, khong tu nang quyen.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Fix-BanPhim.ps1" %*
set "result=%errorlevel%"
exit /b %result%
