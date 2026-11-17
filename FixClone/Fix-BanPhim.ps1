param([ValidateSet('Menu', 'US', 'Restore', 'Settings')][string]$Mode = 'Menu')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Fix-BanPhim.Core.ps1')
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit) { . $consoleInit; Initialize-TechMasterConsole }
try {
    Write-Host "BÀN PHÍM CHO EVKEY — user $env:USERNAME" -ForegroundColor Cyan
    Write-Host '1. Chỉ dùng bàn phím US, tránh chuyển nhầm sang bộ gõ Windows'
    Write-Host '2. Khôi phục cấu hình bàn phím trước đó'
    Write-Host '3. Mở cài đặt ngôn ngữ / bàn phím Windows'
    Write-Host '0. Thoát'
    if ($Mode -eq 'Menu') {
        switch (Read-Host 'Chọn 0 / 1 / 2 / 3') {
            '1' { $Mode = 'US' }
            '2' { $Mode = 'Restore' }
            '3' { $Mode = 'Settings' }
            default { return }
        }
    }
    if ($Mode -eq 'Settings') { Start-Process 'ms-settings:regionlanguage'; return }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = (Get-Process -Id $PID).SessionId
    $owners = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" -ErrorAction Stop | ForEach-Object {
        (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop).Sid
    } | Where-Object { $_ } | Sort-Object -Unique)
    if ($owners.Count -ne 1 -or $owners[0] -cne $sid) { throw 'Hãy chạy Fix-BanPhim.bat trực tiếp tại user khách hàng, không Run as administrator bằng tài khoản khác.' }
    $store = Join-Path $env:LOCALAPPDATA 'TechMaster Deploy/Keyboard Backups'
    if ($Mode -eq 'US') {
        $before = Get-KeyboardSnapshot $sid
        $names = @($before.languages | ForEach-Object { [Globalization.CultureInfo]::GetCultureInfo($_.tag).DisplayName })
        Write-Host ('Giữ các ngôn ngữ hiện có: ' + ($names -join ', '))
        Write-Host 'Sẽ giữ danh sách ngôn ngữ hiển thị và chỉ để bàn phím US. Không gỡ language pack, không tắt EVKey.'
        if ((Read-Host 'Gõ US để xác nhận') -cne 'US') { Write-Host 'Đã huỷ.'; return }
        $backup = Set-EvKeyUsKeyboard $store $sid
        if ($backup) { Write-Host 'Đã chọn bàn phím US và lưu sao lưu để khôi phục.' -ForegroundColor Green }
    } else {
        $last = @(Get-ChildItem -LiteralPath $store -Filter 'before-*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if (-not $last.Count) { Write-Host 'Chưa có sao lưu bàn phím.'; return }
        if ((Read-Host 'Gõ KHOI PHUC để lấy lại cấu hình bàn phím đã lưu') -cne 'KHOI PHUC') { return }
        Restore-EvKeyKeyboard $last[0].FullName $sid
        Write-Host 'Đã khôi phục bàn phím.' -ForegroundColor Green
    }
    Write-Host 'Đăng xuất rồi đăng nhập lại nếu danh sách ở thanh tác vụ chưa đổi. Định dạng ngày / số được chỉnh bằng nút riêng.'
} catch { Write-Host ('LỖI: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
