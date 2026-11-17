@echo off
:: Chinh dinh dang ngay gio / so cho user DANG DANG NHAP.
:: KHONG tu nang quyen Admin (de ghi dung HKCU cua user hien tai).
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Fix-DinhDang.ps1" %*
set "result=%errorlevel%"
exit /b %result%
