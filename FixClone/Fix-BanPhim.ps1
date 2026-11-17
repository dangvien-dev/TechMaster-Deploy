param([ValidateSet('Menu','US','Restore','Settings')][string]$Mode='Menu',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'Fix-BanPhim.Core.ps1')
$keyboardWindow=Import-DeployWindow (Join-Path $PSScriptRoot 'Fix-BanPhim.xml')
function Invoke-KeyboardChoice([string]$Mode) {
    try {
    if($Mode -eq 'Settings'){Start-Process 'ms-settings:regionlanguage';return}
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
        if (-not (Confirm-Box 'Chỉ giữ kiểu nhập US cho các ngôn ngữ hiện có? Có sao lưu và giữ nguyên EVKey / ngôn ngữ hiển thị.' 'Bàn phím US' -ConfirmText 'Áp dụng')) { return }
        $backup = Set-EvKeyUsKeyboard $store $sid
        if ($backup) { Write-Host 'Đã chọn bàn phím US và lưu sao lưu để khôi phục.' -ForegroundColor Green }
    } else {
        $last = @(Get-ChildItem -LiteralPath $store -Filter 'before-*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if (-not $last.Count) { Write-Host 'Chưa có sao lưu bàn phím.'; return }
        if (-not (Confirm-Box 'Khôi phục cấu hình bàn phím đã lưu?' 'Khôi phục bàn phím' -ConfirmText 'Khôi phục')) { return }
        Restore-EvKeyKeyboard $last[0].FullName $sid
        Write-Host 'Đã khôi phục bàn phím.' -ForegroundColor Green
    }

    $keyboardWindow.FindName('Status').Text='Đã thực hiện. Đăng xuất / đăng nhập nếu thanh tác vụ chưa cập nhật.'
    }catch{Show-DeployMessage $_.Exception.Message 'Bàn phím cho EVKey' 'Error'}
}
$keyboardWindow.FindName('US').Add_Click({Invoke-KeyboardChoice 'US'})
$keyboardWindow.FindName('Restore').Add_Click({Invoke-KeyboardChoice 'Restore'})
$keyboardWindow.FindName('Settings').Add_Click({Invoke-KeyboardChoice 'Settings'})
if($ValidateOnly){return $keyboardWindow}
if($Mode -ne 'Menu'){Invoke-KeyboardChoice $Mode}else{[void]$keyboardWindow.ShowDialog()}
