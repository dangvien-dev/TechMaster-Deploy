<#
.SYNOPSIS
    Kiểm tra và sửa các lỗi khiến sysprep báo
    "Sysprep was not able to validate your Windows installation".

.DESCRIPTION
    1. Đóng tiến trình sysprep còn treo
    2. Kiểm tra BitLocker / Device Encryption ổ C:
    3. Gỡ các package mà setupact.log đã báo lỗi
       ("SYSPRP Package ... was installed for a user, but not provisioned for all users")
    4. Quét chủ động các package cài cho user nhưng chưa provision (sẽ gây lỗi lần sau)
    5. Máy ASUS: tạm tắt service ASUS để Armoury Crate không tự cài lại
       (Fix-CloneDuplicate.ps1 sẽ bật lại trên máy clone)
    6. Hiện các dòng lỗi mới nhất trong log

.PARAMETER PreCheck
    Chế độ kiểm tra trước khi sysprep (Run-Sysprep.bat gọi). Exit code 1 nếu còn vấn đề.

.PARAMETER Auto
    Gỡ toàn bộ package tìm thấy, không hỏi.
#>
[CmdletBinding()]
param([switch]$PreCheck, [switch]$Auto)

$ErrorActionPreference = 'Continue'
function Write-Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [LỖI] $t" -ForegroundColor Red }
function Confirm-Step([string]$q, [bool]$def = $true) {
    if ($Auto) { return $true }
    $a = Read-Host "$q $(if ($def) {'[Y/n]'} else {'[y/N]'})"
    if ([string]::IsNullOrWhiteSpace($a)) { return $def }
    return $a.Trim().ToLower() -in 'y', 'yes', 'c', 'co'
}

# ---------- Quyền Admin ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Cần chạy bằng quyền Administrator (cửa sổ phải có chữ 'Administrator:')."
    exit 2
}

$sysprepDir = "$env:SystemRoot\System32\Sysprep"
$log        = "$sysprepDir\Panther\setupact.log"
$problems   = 0

# ---------- 1. Sysprep đang treo ----------
Write-Step "1. TIEN TRINH SYSPREP"
$sp = Get-Process sysprep -ErrorAction SilentlyContinue
if ($sp) {
    $sp | Stop-Process -Force
    Write-Ok "Đã đóng sysprep.exe đang chạy"
} else { Write-Host "  Không có sysprep đang chạy." }

# ---------- 2. BitLocker ----------
Write-Step "2. BITLOCKER / DEVICE ENCRYPTION"
$v = Get-CimInstance -Namespace root/cimv2/Security/MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume `
        -Filter "DriveLetter='C:'" -ErrorAction SilentlyContinue
if ($v -and $v.ConversionStatus -ne 0) {
    Write-Err "Ổ C: đang mã hoá (ConversionStatus=$($v.ConversionStatus))."
    if (-not $PreCheck -and (Confirm-Step "Tắt BitLocker ổ C: (giải mã mất vài phút đến vài giờ)?" $false)) {
        & manage-bde.exe -off C:
        Write-Warn "Đang giải mã. Kiểm tra tiến độ: manage-bde -status C:  -> đợi 100% rồi chạy sysprep."
    }
    $problems++
} else { Write-Ok "Ổ C: không mã hoá" }

# ---------- 3 + 4. Package gây lỗi ----------
Write-Step "3. PACKAGE GAY LOI SYSPREP"
$names = New-Object System.Collections.Generic.List[string]

# 3a. Từ log của các lần sysprep trước
if (Test-Path $log) {
    Select-String -Path $log -Pattern 'SYSPRP Package (\S+) was installed for a user' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Matches[0].Groups[1].Value.Split('_')[0] } |
        Sort-Object -Unique | ForEach-Object { if (-not $names.Contains($_)) { $names.Add($_) } }
}
# 3b. Quét chủ động: cài cho user nhưng không provision, không phải framework/system
$prov = (Get-AppxProvisionedPackage -Online).DisplayName
Get-AppxPackage -AllUsers |
    Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' -and $prov -notcontains $_.Name } |
    ForEach-Object { if (-not $names.Contains($_.Name)) { $names.Add($_.Name) } }

# Chỉ giữ những package còn đang cài
$found = foreach ($n in $names) {
    Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $found) {
    Write-Ok "Không còn package nào chặn sysprep"
} else {
    $found | Format-Table Name, Version, SignatureKind -AutoSize | Out-Host
    $problems += @($found).Count
    if (Confirm-Step ("Gỡ {0} package trên cho mọi user?" -f @($found).Count)) {
        # Đóng các tiến trình có thể đang giữ package (Widgets)
        Get-Process Widgets, WidgetService -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        foreach ($p in $found) {
            Write-Host "  Đang gỡ $($p.Name) (tối đa 3 phút)..." -NoNewline
            # Chạy trong job để có timeout, tránh treo cả script
            $job = Start-Job -ArgumentList $p.Name, ($prov -contains $p.Name) -ScriptBlock {
                param($name, $isProv)
                Get-AppxPackage -AllUsers -Name $name | Remove-AppxPackage -AllUsers -ErrorAction Stop
                if ($isProv) {
                    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $name |
                        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                }
            }
            if (-not (Wait-Job $job -Timeout 180)) {
                Stop-Job $job; Remove-Job $job -Force
                Write-Host ""
                Write-Err "$($p.Name): quá 3 phút, bỏ qua. Restart máy rồi chạy lại script."
                continue
            }
            $err = $null
            Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable err | Out-Null
            Remove-Job $job -Force
            Write-Host ""
            if (Get-AppxPackage -AllUsers -Name $p.Name) {
                Write-Err "$($p.Name) vẫn còn. $($err | Select-Object -First 1)"
            } else { Write-Ok "Đã gỡ $($p.Name)"; $problems-- }
        }
    }
}

# ---------- 5. ASUS ----------
Write-Step "5. MAY ASUS"
$maker = (Get-CimInstance Win32_ComputerSystem).Manufacturer
$asusSvc = Get-Service *Armoury*, *Asus* -ErrorAction SilentlyContinue
if ($maker -notmatch 'ASUS' -or -not $asusSvc) {
    Write-Host "  Không phải máy ASUS hoặc không có service ASUS, bỏ qua."
} else {
    $asusSvc | Format-Table Name, Status, StartType -AutoSize | Out-Host
    if (Confirm-Step "Tạm tắt service ASUS để Armoury Crate không tự cài lại? (máy clone sẽ tự bật lại)") {
        $asusSvc | Stop-Service -Force -ErrorAction SilentlyContinue
        $asusSvc | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Ok "Đã tắt service ASUS"
    }
}

# ---------- 6. Lỗi mới nhất trong log ----------
if (-not $PreCheck) {
    Write-Step "6. LOI MOI NHAT TRONG setupact.log"
    if (Test-Path $log) {
        Select-String -Path $log -Pattern ', Error' | Select-Object -Last 10 | ForEach-Object { "  " + $_.Line }
    } else { Write-Host "  Chưa có log." }
}

# ---------- Kết luận ----------
Write-Host ""
if ($problems -le 0) {
    Write-Host "SẴN SÀNG CHẠY SYSPREP. Rút dây mạng / tắt Wi-Fi trước khi chạy." -ForegroundColor Green
    exit 0
} else {
    Write-Host "CÒN $problems VẤN ĐỀ. Xử lý xong rồi chạy lại script này." -ForegroundColor Red
    exit 1
}
