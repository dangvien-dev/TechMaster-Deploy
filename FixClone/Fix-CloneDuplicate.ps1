<#
.SYNOPSIS
    Xử lý thông tin trùng lặp trên máy sau khi clone ổ (disk to disk / Ghost).

.DESCRIPTION
    Các bước (mỗi bước đều hỏi Y/N, trừ khi chạy với -Auto):
      1. Đổi Computer Name
      2. Tạo mới MachineGuid (HKLM\SOFTWARE\Microsoft\Cryptography)
      3. Reset Windows Update / WSUS Client ID (SusClientId)
      4. Reset ID AnyDesk
      5. Reset ID TeamViewer
      6. Chuyển card mạng đang dùng IP tĩnh về DHCP
      7. Reset KMS CMID (chỉ khi Windows đang dùng license KMS Volume)
      8. Cài lại phần mềm trong thư mục Reinstall (WinRAR...)
      9. Bật lại service ASUS nếu là máy ASUS
     10. Dấu thập phân / hàng nghìn (gọi Fix-DinhDang.ps1)
     11. Khởi động lại

    KHÔNG xử lý: Machine SID. Muốn có SID mới thì phải chạy sysprep /generalize
    trên máy gốc trước khi clone (bắt buộc nếu máy sẽ join Domain).

.PARAMETER NewName
    Tên máy mới. Nếu bỏ trống, script đề xuất PC-<6 ký tự cuối Serial BIOS / MAC>.

.PARAMETER Auto
    Chạy toàn bộ, không hỏi (trừ bước 6, 7 chỉ chạy khi có thêm -ResetIP / -RearmKMS).

.EXAMPLE
    .\Fix-CloneDuplicate.ps1
    .\Fix-CloneDuplicate.ps1 -NewName KETOAN-01 -Auto -ResetIP
#>
[CmdletBinding()]
param(
    [string]$NewName,
    [switch]$Auto,
    [switch]$ResetIP,
    [switch]$RearmKMS,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit -PathType Leaf) {
    . $consoleInit
    Initialize-TechMasterConsole
}

# ---------- Kiểm tra quyền Admin ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Cần chạy với quyền Administrator." -ForegroundColor Red
    exit 1
}

# ---------- Log ----------
$logDir = Join-Path $PSScriptRoot 'Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("{0}_{1:yyyyMMdd_HHmmss}.log" -f $env:COMPUTERNAME, (Get-Date))
Start-Transcript -Path $logFile | Out-Null

# ---------- Helpers ----------
function Write-Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  [!] $text" -ForegroundColor Yellow }
function Write-Err($text)  { Write-Host "  [LỖI] $text" -ForegroundColor Red }

function Confirm-Step([string]$question, [bool]$defaultYes = $true, [bool]$autoValue = $true) {
    if ($Auto) { return $autoValue }
    $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $ans = Read-Host "$question $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    return $ans.Trim().ToLower() -in @('y', 'yes', 'c', 'co')
}

function Get-MachineSidPrefix {
    try {
        $sid = (Get-LocalUser | Select-Object -First 1).SID.Value
        return ($sid -replace '-\d+$', '')
    } catch { return '(không đọc được)' }
}

function Test-SerialValid([string]$serial) {
    # Serial rác thường gặp trên main máy ráp / OEM chưa ghi
    $s = ($serial + '').Trim()
    if ($s.Length -lt 5) { return $false }
    $junk = 'to be filled|default string|system serial|chassis serial|serial number|not applicable|not specified|' +
            '^none$|^n/?a$|o\.?e\.?m|^x+$|^0+$|^1234567|^0123456|^abcdef|invalid|unknown|^empty$|^base board'
    if ($s -match $junk) { return $false }
    if (($s.ToCharArray() | Sort-Object -Unique).Count -le 2) { return $false }   # vd 00000000, 11111111
    return $true
}

function Test-NameInUse([string]$name) {
    # Tên đã có máy khác dùng trong mạng LAN? (DNS/NetBIOS/LLMNR)
    try {
        $r = Resolve-DnsName $name -ErrorAction Stop -QuickTimeout -DnsOnly:$false
        $myIPs = (Get-NetIPAddress -ErrorAction SilentlyContinue).IPAddress
        return [bool]($r | Where-Object { $_.IPAddress -and $myIPs -notcontains $_.IPAddress })
    } catch { return $false }
}

function Get-SuggestedName {
    $serial = ((Get-CimInstance Win32_BIOS).SerialNumber + '').Trim()
    if (Test-SerialValid $serial) {
        $token = ($serial -replace '[^A-Za-z0-9]', '')
        if ($token.Length -gt 6) { $token = $token.Substring($token.Length - 6) }
        $source = "Serial BIOS ($serial)"
    } else {
        # 6 ký tự cuối MAC = số riêng của card mạng (6 ký tự đầu là mã hãng)
        $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
        if (-not $nic) { $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Select-Object -First 1 }
        $token = ($nic.MacAddress -replace '[^A-Fa-f0-9]', '')
        if ($token.Length -gt 6) { $token = $token.Substring($token.Length - 6) }
        $source = "MAC $($nic.Name) (Serial BIOS không hợp lệ: '$serial')"
    }
    $name = ("PC-" + $token).ToUpper()
    Write-Host "  Tên đề xuất lấy từ $source"

    # Trùng với máy khác trong mạng -> thêm hậu tố -2, -3...
    $base = $name; $i = 2
    while ((Test-NameInUse $name) -and $i -lt 10) {
        Write-Warn "Tên $name đã có máy khác dùng trong mạng"
        $suffix = "-$i"
        $name = $base.Substring(0, [Math]::Min($base.Length, 15 - $suffix.Length)) + $suffix
        $i++
    }
    return $name
}

function Test-ComputerName([string]$name) {
    # NetBIOS: tối đa 15 ký tự, chỉ chữ, số, gạch ngang, không toàn số, không bắt đầu/kết thúc bằng '-'
    return ($name -match '^[A-Za-z0-9-]{1,15}$') -and ($name -notmatch '^\d+$') -and
           ($name -notmatch '^-') -and ($name -notmatch '-$')
}

# ---------- Thông tin hiện tại ----------
$cryptoKey = 'HKLM:\SOFTWARE\Microsoft\Cryptography'
$wuKey     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'

Write-Step "THÔNG TIN HIỆN TẠI"
Write-Host ("  Computer Name : {0}" -f $env:COMPUTERNAME)
Write-Host ("  MachineGuid   : {0}" -f (Get-ItemProperty $cryptoKey).MachineGuid)
Write-Host ("  SusClientId   : {0}" -f (Get-ItemProperty $wuKey -ErrorAction SilentlyContinue).SusClientId)
Write-Host ("  Machine SID   : {0}" -f (Get-MachineSidPrefix))
Write-Host ("  BIOS Serial   : {0}" -f (Get-CimInstance Win32_BIOS).SerialNumber)
Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("  MAC           : {0}  ({1}, {2})" -f $_.MacAddress, $_.Name, $_.Status)
}
$partOfDomain = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
if ($partOfDomain) {
    Write-Warn "Máy đang join Domain. Đổi tên máy cần quyền Domain và SID trùng có thể gây lỗi xác thực -> nên dùng sysprep."
}

$needReboot = $false

# ---------- 1. Computer Name ----------
Write-Step "1. ĐỔI COMPUTER NAME"
if (Confirm-Step "Đổi tên máy?") {
    if (-not $NewName) {
        $suggest = Get-SuggestedName
        if ($Auto) { $NewName = $suggest }
        else {
            $in = Read-Host "Nhập tên mới (Enter = $suggest)"
            $NewName = if ([string]::IsNullOrWhiteSpace($in)) { $suggest } else { $in.Trim() }
        }
    }
    $NewName = $NewName.ToUpper()
    if (-not (Test-ComputerName $NewName)) {
        Write-Err "Tên '$NewName' không hợp lệ (tối đa 15 ký tự, chỉ A-Z 0-9 -, không toàn số). Bỏ qua bước này."
    } elseif ($NewName -eq $env:COMPUTERNAME) {
        Write-Warn "Tên mới trùng tên hiện tại, bỏ qua."
    } else {
        try {
            Rename-Computer -NewName $NewName -Force -WarningAction SilentlyContinue
            Write-Ok "Đã đặt tên mới: $NewName (có hiệu lực sau khi restart)"
            $needReboot = $true
        } catch { Write-Err $_.Exception.Message }
    }
}

# ---------- 2. MachineGuid ----------
Write-Step "2. TẠO MỚI MachineGuid"
if (Confirm-Step "Tạo MachineGuid mới?") {
    try {
        $newGuid = [guid]::NewGuid().ToString()
        Set-ItemProperty -Path $cryptoKey -Name MachineGuid -Value $newGuid
        Write-Ok "MachineGuid mới: $newGuid"
        $needReboot = $true
    } catch { Write-Err $_.Exception.Message }
}

# ---------- 3. WSUS / Windows Update Client ID ----------
Write-Step "3. RESET WINDOWS UPDATE CLIENT ID (SusClientId)"
if (Confirm-Step "Reset SusClientId?") {
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service bits -Force -ErrorAction SilentlyContinue
        foreach ($v in 'SusClientId', 'SusClientIdValidation', 'PingID', 'AccountDomainSid') {
            Remove-ItemProperty -Path $wuKey -Name $v -ErrorAction SilentlyContinue
        }
        Start-Service bits -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        # Yêu cầu tạo ID mới và đăng ký lại (chỉ có tác dụng rõ ràng khi dùng WSUS)
        & "$env:SystemRoot\System32\wuauclt.exe" /resetauthorization /detectnow 2>$null
        Write-Ok "Đã xoá SusClientId, ID mới sẽ được tạo khi Windows Update chạy."
    } catch { Write-Err $_.Exception.Message }
}

# ---------- 4. AnyDesk ----------
Write-Step "4. RESET ID ANYDESK"
$anyDeskConfs = @()
$anyDeskConfs += Join-Path $env:ProgramData 'AnyDesk\service.conf'
Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $anyDeskConfs += Join-Path $_.FullName 'AppData\Roaming\AnyDesk\service.conf'
}
$anyDeskFound = $anyDeskConfs | Where-Object { Test-Path $_ }
if (-not $anyDeskFound) {
    Write-Host "  Không thấy AnyDesk, bỏ qua."
} elseif (Confirm-Step "Tìm thấy AnyDesk. Reset ID?") {
    try {
        Stop-Service AnyDesk -Force -ErrorAction SilentlyContinue
        Get-Process AnyDesk -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        foreach ($f in $anyDeskFound) {
            Remove-Item $f -Force
            Write-Ok "Đã xoá $f"
        }
        Start-Service AnyDesk -ErrorAction SilentlyContinue
        Write-Ok "AnyDesk sẽ nhận ID mới khi mở lại."
    } catch { Write-Err $_.Exception.Message }
}

# ---------- 5. TeamViewer ----------
Write-Step "5. RESET ID TEAMVIEWER"
$tvKeys = @('HKLM:\SOFTWARE\WOW6432Node\TeamViewer', 'HKLM:\SOFTWARE\TeamViewer') |
          Where-Object { Test-Path $_ }
if (-not $tvKeys) {
    Write-Host "  Không thấy TeamViewer, bỏ qua."
} elseif (Confirm-Step "Tìm thấy TeamViewer. Reset ID?") {
    try {
        Stop-Service TeamViewer -Force -ErrorAction SilentlyContinue
        Get-Process TeamViewer* -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        foreach ($k in $tvKeys) {
            Remove-ItemProperty -Path $k -Name ClientID -ErrorAction SilentlyContinue
        }
        Start-Service TeamViewer -ErrorAction SilentlyContinue
        Write-Ok "Đã xoá ClientID. Nếu sau restart ID vẫn trùng -> gỡ và cài lại TeamViewer."
    } catch { Write-Err $_.Exception.Message }
}

# UltraViewer has a separate identity mechanism; do not reuse AnyDesk/TeamViewer resets.
$ultraInstalled = @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^UltraViewer(?:\s|$)' })
if ($ultraInstalled.Count) {
    Write-Warn 'Có UltraViewer. Chưa reset ID tự động; nếu bị trùng, mở TechMaster → Sau khi clone → Chẩn đoán UltraViewer trên hai máy.'
    Write-Host '  Giữ nguyên cấu hình và phiên kết nối UltraViewer đang chạy.'
}

# ---------- 6. IP tĩnh -> DHCP ----------
Write-Step "6. KIỂM TRA IP TĨNH"
$staticIfs = Get-NetIPInterface -AddressFamily IPv4 -Dhcp Disabled -ErrorAction SilentlyContinue |
             Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and
                            (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue) }
if (-not $staticIfs) {
    Write-Host "  Không có card mạng nào dùng IP tĩnh."
} else {
    foreach ($i in $staticIfs) {
        $ip = (Get-NetIPAddress -InterfaceIndex $i.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ', '
        Write-Warn ("{0} đang dùng IP tĩnh: {1}" -f $i.InterfaceAlias, $ip)
    }
    if (Confirm-Step "Chuyển các card trên về DHCP (tránh trùng IP)?" $false $ResetIP.IsPresent) {
        foreach ($i in $staticIfs) {
            try {
                Remove-NetRoute -InterfaceIndex $i.InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                Set-NetIPInterface -InterfaceIndex $i.InterfaceIndex -Dhcp Enabled
                Set-DnsClientServerAddress -InterfaceIndex $i.InterfaceIndex -ResetServerAddresses
                Write-Ok "$($i.InterfaceAlias) -> DHCP"
            } catch { Write-Err "$($i.InterfaceAlias): $($_.Exception.Message)" }
        }
        ipconfig /renew | Out-Null
    }
}

# ---------- 7. KMS CMID ----------
Write-Step "7. KMS CLIENT MACHINE ID (CMID)"
$kms = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -like 'Windows*' -and $_.Description -like '*VOLUME_KMSCLIENT*' }
if (-not $kms) {
    Write-Host "  Windows không dùng KMS Volume license, bỏ qua (Retail/OEM/Digital License không cần)."
} else {
    $remain = $kms.RemainingWindowsReArmCount
    Write-Warn "Windows đang dùng KMS. Số lần rearm còn lại: $remain"
    if ($remain -gt 0 -and (Confirm-Step "Chạy slmgr /rearm để tạo CMID mới? (cần activate lại với KMS sau restart)" $false $RearmKMS.IsPresent)) {
        cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /rearm
        $needReboot = $true
    }
}

# ---------- 8. Cài lại phần mềm từ thư mục Reinstall ----------
# Đặt file cài vào thư mục Reinstall (cạnh script). Tham số cài im lặng:
#   - .msi : tự dùng msiexec /i "<file>" /qn /norestart
#   - .exe : mặc định /S (đúng cho WinRAR, NSIS...). Cần tham số khác thì tạo file
#            cùng tên đuôi .args, ví dụ: setup.exe + setup.args chứa "/VERYSILENT /NORESTART"
Write-Step "8. CÀI LẠI PHẦN MỀM (thư mục Reinstall)"
$reinstallDir = Join-Path $PSScriptRoot 'Reinstall'
$installers = @()
if (Test-Path $reinstallDir) {
    $installers = Get-ChildItem $reinstallDir -File | Where-Object { $_.Extension -in '.exe', '.msi' } | Sort-Object Name
}
if (-not $installers) {
    Write-Host "  Không có file cài trong $reinstallDir, bỏ qua."
} elseif (Confirm-Step ("Cài {0} phần mềm trong thư mục Reinstall?" -f $installers.Count)) {
    foreach ($f in $installers) {
        try {
            if ($f.Extension -eq '.msi') {
                $exe = "$env:SystemRoot\System32\msiexec.exe"
                $arg = "/i `"$($f.FullName)`" /qn /norestart"
            } else {
                $exe = $f.FullName
                $argFile = [IO.Path]::ChangeExtension($f.FullName, '.args')
                $arg = if (Test-Path $argFile) { (Get-Content $argFile -Raw).Trim() } else { '/S' }
            }
            Write-Host "  Đang cài $($f.Name) $arg ..."
            $p = Start-Process -FilePath $exe -ArgumentList $arg -Wait -PassThru
            if ($p.ExitCode -in 0, 3010) { Write-Ok "$($f.Name) (ExitCode $($p.ExitCode))" }
            else { Write-Err "$($f.Name) ExitCode $($p.ExitCode)" }
        } catch { Write-Err "$($f.Name): $($_.Exception.Message)" }
    }
}

# ---------- 9. Bật lại service ASUS (chỉ máy ASUS) ----------
Write-Step "9. SERVICE ASUS"
$maker = (Get-CimInstance Win32_ComputerSystem).Manufacturer
if ($maker -notmatch 'ASUS') {
    Write-Host "  Không phải máy ASUS ($maker), bỏ qua."
} else {
    $asusSvc = [ordered]@{
        'asus' = 'Automatic'; 'AsusCertService' = 'Automatic'; 'AsusFanControlService' = 'Automatic'
        'AsusUpdateCheck' = 'Automatic'; 'asusm' = 'Manual'
    }
    if (Confirm-Step "Máy ASUS: bật lại các service ASUS (quạt, cert, update)?") {
        foreach ($name in $asusSvc.Keys) {
            if (Get-Service $name -ErrorAction SilentlyContinue) {
                Set-Service $name -StartupType $asusSvc[$name]
                if ($asusSvc[$name] -eq 'Automatic') { Start-Service $name -ErrorAction SilentlyContinue }
                Write-Ok "$name -> $($asusSvc[$name])"
            }
        }
    }
}

# ---------- 10. Chỉ dấu thập phân / phân nhóm số ----------
Write-Step "10. DẤU THẬP PHÂN / HÀNG NGHÌN"
$dd = Join-Path $PSScriptRoot 'Fix-DinhDang.ps1'
if (Test-Path -LiteralPath $dd -PathType Leaf) {
    try { & $dd -AllNewUsers }
    catch { Write-Err "Định dạng số: $($_.Exception.Message)" }
}
else { Write-Warn "Không có $dd -> chạy Fix-DinhDang.bat bằng tay sau." }

# ---------- Machine SID ----------
Write-Step "LƯU Ý VỀ MACHINE SID"
Write-Warn "Script không đổi được Machine SID: $(Get-MachineSidPrefix)"
Write-Host "  - Mạng Workgroup: SID trùng không gây lỗi thực tế."
Write-Host "  - Join Domain: phải sysprep /generalize máy gốc trước khi clone."

# ---------- Kết thúc ----------
Stop-Transcript | Out-Null
Write-Host "`nLog: $logFile" -ForegroundColor DarkGray

if ($needReboot -and -not $NoReboot) {
    if (Confirm-Step "`nCần khởi động lại để áp dụng. Restart ngay?") {
        Restart-Computer -Force
    }
}
