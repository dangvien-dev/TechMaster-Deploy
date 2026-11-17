<#
.SYNOPSIS
    Chỉnh định dạng ngày giờ / số cho user ĐANG ĐĂNG NHẬP (chạy trên máy đã clone).

    Ngày         : dd/MM/yyyy      (16/11/2026)
    Giờ          : HH:mm / HH:mm:ss (24 giờ)
    Thập phân    : ,
    Hàng nghìn   : .
    List         : ;
    Đơn vị đo    : Metric

    Chạy KHÔNG cần quyền Admin (ghi vào HKCU của user hiện tại).
    Thêm -AllNewUsers (cần Admin) để áp dụng luôn cho user tạo mới sau này.
#>
param([switch]$AllNewUsers)
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit -PathType Leaf) {
    . $consoleInit
    Initialize-TechMasterConsole
}

$values = [ordered]@{
    'LocaleName'     = 'vi-VN'
    'sShortDate'     = 'dd/MM/yyyy'
    'sDate'          = '/'
    'iDate'          = '1'          # 1 = Ngày-Tháng-Năm
    'sShortTime'     = 'HH:mm'
    'sTimeFormat'    = 'HH:mm:ss'
    'sTime'          = ':'
    'iTime'          = '1'          # 1 = 24 giờ
    'sDecimal'       = ','
    'sMonDecimalSep' = ','
    'sThousand'      = '.'
    'sMonThousandSep'= '.'
    'sList'          = ';'
    'iMeasure'       = '0'          # 0 = Metric
}

function Set-Intl([string]$root) {
    $key = "$root\Control Panel\International"
    foreach ($name in $values.Keys) {
        & reg.exe add $key /v $name /t REG_SZ /d $values[$name] /f | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Không ghi được $name vào $key (mã lỗi $LASTEXITCODE)."
        }
    }
}

if ($AllNewUsers) {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '-AllNewUsers cần chạy bằng quyền Administrator.'
    }
}

Write-Host "`n=== DINH DANG NGAY GIO / SO - user $env:USERNAME ===" -ForegroundColor Cyan
Set-Culture vi-VN -ErrorAction Stop
Set-Intl 'HKCU'
$actual = Get-ItemProperty 'HKCU:\Control Panel\International' -ErrorAction Stop
foreach ($name in $values.Keys) {
    if ($actual.$name -cne $values[$name]) {
        throw "Giá trị đã lưu của $name không khớp với cấu hình."
    }
}
Write-Host "  [OK] $env:USERNAME - $($actual.LocaleName), $($actual.sShortDate), $($actual.sShortTime)" -ForegroundColor Green

if ($AllNewUsers) {
    $hive = 'HKU\FixDinhDang'
    $profiles = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop
    $defaultHive = Join-Path ([Environment]::ExpandEnvironmentVariables($profiles.Default)) 'NTUSER.DAT'
    & reg.exe load $hive $defaultHive | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Không mở được Default profile: $defaultHive (mã lỗi $LASTEXITCODE)." }
    try {
        Set-Intl $hive
    } finally {
        & reg.exe unload $hive | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "Không đóng được Default profile (mã lỗi $LASTEXITCODE)." }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Không xác nhận được Default profile đã lưu.' }
    Write-Host '  [OK] Đã ghi cho Default profile (user tạo mới)' -ForegroundColor Green
}

# Yêu cầu các ứng dụng đang chạy đọc lại thiết lập vùng.
try {
    if (-not ('Win32.Msg' -as [type])) {
        Add-Type -Namespace Win32 -Name Msg -ErrorAction Stop -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [Win32.Msg]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'intl', 2, 5000, [ref]$result) | Out-Null
} catch {
    Write-Warning "Không gửi được thông báo cập nhật định dạng: $($_.Exception.Message)"
}
Write-Host "`nMở lại ứng dụng. Nếu đồng hồ taskbar chưa đổi, hãy đăng xuất rồi đăng nhập lại."
