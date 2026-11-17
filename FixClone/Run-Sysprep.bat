@echo off
:: ============================================================
::  Chay tren MAY GOC truoc khi clone.
::  Copy script FixClone vao C:\FixClone, dat unattend.xml,
::  kiem tra BitLocker roi chay sysprep (tu tat may).
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Xu ly truong hop CMD 32-bit (System32 bi chuyen sang SysWOW64)
set "SYSDIR=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\Sysprep\sysprep.exe" set "SYSDIR=%SystemRoot%\Sysnative"

if not exist "%SYSDIR%\Sysprep\sysprep.exe" (
    echo [LOI] Khong tim thay sysprep.exe tai %SYSDIR%\Sysprep
    pause & exit /b 1
)
if not exist "%~dp0unattend.xml" (
    echo [LOI] Thieu file unattend.xml canh file bat nay
    pause & exit /b 1
)
if not exist "%~dp0Fix-CloneDuplicate.ps1" (
    echo [LOI] Thieu file Fix-CloneDuplicate.ps1 canh file bat nay
    pause & exit /b 1
)

if not exist "%~dp0Fix-DinhDang.ps1" (
    echo [LOI] Thieu file Fix-DinhDang.ps1 canh file bat nay
    pause & exit /b 1
)

if not exist "%~dp0New-Unattend.ps1" (
    echo [LOI] Thieu file New-Unattend.ps1. Tai lai bo cong cu day du.
    pause & exit /b 1
)

:: Kiem tra BitLocker / Device Encryption o C: (ConversionStatus 0 = FullyDecrypted)
powershell -NoProfile -Command "$v = Get-CimInstance -Namespace root/cimv2/Security/MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume -Filter \"DriveLetter='C:'\" -ErrorAction SilentlyContinue; if ($v -and $v.ConversionStatus -ne 0) { exit 1 }"
if %errorlevel% neq 0 (
    echo [LOI] O C: dang ma hoa BitLocker. Tat bang lenh: manage-bde -off C:
    echo       Doi giai ma xong 100%% roi chay lai.
    pause & exit /b 1
)

:: Copy file
if not exist C:\FixClone mkdir C:\FixClone
copy /y "%~dp0Fix-CloneDuplicate.ps1" C:\FixClone\ >nul || goto :CopyFailed
copy /y "%~dp0Fix-DinhDang.ps1" C:\FixClone\ >nul || goto :CopyFailed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-Unattend.ps1" -OutputPath "%SYSDIR%\Sysprep\unattend.xml"
if errorlevel 1 goto :CopyFailed
if exist "%~dp0Reinstall\" (
    xcopy "%~dp0Reinstall" C:\FixClone\Reinstall\ /E /I /Y /Q >nul
    if errorlevel 2 goto :CopyFailed
    echo Da xu ly thu muc Reinstall
)
echo [OK] Da copy Fix-CloneDuplicate.ps1 vao C:\FixClone
echo [OK] Da dat unattend.xml vao %SYSDIR%\Sysprep

:: Chuyen thiet lap user (Chrome mac dinh, shortcut, EVKey) thanh thiet lap toan may
if exist "%~dp0Prepare-Master.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-Master.ps1"
    if errorlevel 1 (
        echo [LOI] Chuan bi may goc that bai. Sua loi o tren truoc khi chay Sysprep.
        pause & exit /b 1
    )
    echo Kiem tra ket qua o tren. Neu co dong [!] thi sua roi chay lai.
    pause
)

:: Kiem tra truoc cac loi lam sysprep fail (package Appx, BitLocker, ASUS)
if exist "%~dp0Fix-SysprepErrors.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-SysprepErrors.ps1" -PreCheck
    if errorlevel 1 (
        echo [LOI] Con van de chua xu ly, dung lai. Sua xong chay lai Run-Sysprep.bat
        pause & exit /b 1
    )
)

echo.
echo  Sau khi sysprep chay xong may se TU TAT.
echo  KHONG bat lai may goc - thao o / boot USB de clone ngay.
echo.
set /p ok=Go YES de chay sysprep:
if /i not "%ok%"=="YES" (
    echo Da huy.
    pause & exit /b
)

"%SYSDIR%\Sysprep\sysprep.exe" /generalize /oobe /shutdown /unattend:"%SystemRoot%\System32\Sysprep\unattend.xml"
if %errorlevel% neq 0 (
    echo [LOI] Sysprep that bai. Chay Fix-SysprepErrors.bat de kiem tra va sua.
    pause
    exit /b 1
)
exit /b 0

:CopyFailed
echo [LOI] Khong copy duoc file trien khai. Kiem tra cac dong loi o tren.
pause
exit /b 1
