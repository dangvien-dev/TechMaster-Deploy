<#
.SYNOPSIS
    Kích hoạt Windows / Office: thử online trước, thất bại thì kích hoạt qua
    Product Activation Portal (Installation ID -> Confirmation ID) - bán tự động.

.PARAMETER Product
    Windows hoặc Office.

.DESCRIPTION
      1. Tìm sản phẩm đã nhập key nhưng chưa kích hoạt
      2. Thử kích hoạt ONLINE (không cần tài khoản). Thành công thì dừng.
      3. Thất bại -> lấy Installation ID, copy vào clipboard, mở portal của Microsoft
         (đăng nhập, captcha, dán IID -> làm tay trên web)
      4. Dán Confirmation ID (48 số) -> script tự nạp
      5. Kiểm tra trạng thái

    Dùng WMI SoftwareLicensingProduct (Windows 10/11, Office 2016 trở lên).
#>
param(
    [ValidateSet('Windows', 'Office')][string]$Product = 'Office',
    [switch]$Test     # Chạy thử QR + nhận Confirmation ID qua LAN bằng mã giả, KHÔNG nạp gì vào máy
)

$ErrorActionPreference = 'Stop'
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit -PathType Leaf) {
    . $consoleInit
    Initialize-TechMasterConsole
}
$uiRuntime=Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Wpf.Runtime.ps1'
if(Test-Path -LiteralPath $uiRuntime){. $uiRuntime}
. (Join-Path $PSScriptRoot 'Activation.Core.ps1')
if($Product -eq 'Windows'){. (Join-Path (Split-Path -Parent $PSScriptRoot) 'FixClone/Windows.License.Core.ps1')}
. (Join-Path $PSScriptRoot 'QrWindow.Core.ps1')
. (Join-Path $PSScriptRoot 'Cid.Phone.Core.ps1')
$cfg = @{
    Windows = @{ AppId = '55c92734-d682-4d71-983e-d6ec3f16059f'; Url = 'https://aka.ms/WindowsActivate'
                 Check = 'Settings -> System -> Activation' }
    Office  = @{ AppId = '0ff1ce15-a989-479d-af46-f275c6370663'; Url = 'https://visualsupport.microsoft.com/'
                 Check = "Word -> File -> Account -> 'Product Activated'" }
}[$Product]
$AppId = $cfg.AppId
$Url   = $cfg.Url

function Write-Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [LỖI] $t" -ForegroundColor Red }

$statusText = @{ 0 = 'Chưa có license'; 1 = 'ĐÃ KÍCH HOẠT'; 2 = 'Đang dùng thử (OOB Grace)'; 3 = 'Hết hạn dùng thử';
                 4 = 'Non-Genuine Grace'; 5 = 'Notification (chưa kích hoạt)'; 6 = 'Extended Grace' }
if($Product -eq 'Windows'){foreach($state in 0..6){$statusText[$state]=Get-WindowsLicenseStateText $state}}

function Get-LicProducts {
    Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='$AppId' AND PartialProductKey IS NOT NULL"
}
function Format-Groups([string]$digits, [int]$size) {
    ($digits -split "(.{$size})" | Where-Object { $_ }) -join ' '
}

# ---------- Nhập Confirmation ID: gõ tay / clipboard ----------
function Read-CidKeyboard {
    while ($true) {
        $in = Request-DeployText "Nhập / dán Confirmation ID 48 số. Để trống rồi bấm Tiếp tục để đọc clipboard; Huỷ để bỏ qua." "Confirmation ID"
        if($null -eq $in){return $null}
        if ($in -eq 'q') { return $null }
        if ([string]::IsNullOrWhiteSpace($in)) { try { $in = Get-Clipboard -Raw } catch { $in = '' } }
        $c = ($in -replace '\D', '')
        if ($c.Length -eq 48) { return $c }
        Write-Err "Confirmation ID phải đủ 48 số (8 nhóm x 6), đang có $($c.Length) số. Thử lại."
    }
}

# ---------- Nhận Confirmation ID từ điện thoại qua mạng LAN ----------
$FwRuleName = 'KichHoat-CID-Temp'

function Get-LanIP {
    $cfgs = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }
    foreach ($c in $cfgs) {
        foreach ($a in $c.IPv4Address) { if ($a.IPAddress -notlike '169.254.*') { return $a.IPAddress } }
    }
    return $null
}

function Send-Html($ctx, [string]$html) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($html)
    $ctx.Response.ContentType = 'text/html; charset=utf-8'
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}

function Start-CidReceiver {
    # Trả về @{ Listener; Url } hoặc $null nếu không mở được
    $ip = Get-LanIP
    if (-not $ip) { Write-Warn "Máy không có mạng LAN -> chỉ nhập tay."; return $null }
    $listener = $null
    try {
        $port  = Get-Random -Minimum 20000 -Maximum 40000
        $token = -join ((48..57) + (97..102) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://+:$port/$token/")
        $listener.Start()
        New-NetFirewallRule -DisplayName $FwRuleName -Direction Inbound -Protocol TCP -LocalPort $port `
            -Action Allow -Profile Any | Out-Null
        return @{ Listener = $listener; Url = "http://${ip}:$port/$token/" }
    } catch {
        Write-Warn "Không mở được cổng nhận qua LAN: $($_.Exception.Message) -> chỉ nhập tay."
        if ($listener) { $listener.Close() }
        Remove-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
        return $null
    }
}

function Stop-CidReceiver($rcv) {
    if ($rcv) { try { $rcv.Listener.Stop(); $rcv.Listener.Close() } catch {} }
    Remove-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
}

function Test-CidManualInput {
    try{return [Console]::KeyAvailable}catch{return $false}
}
function Wait-Cid($rcv,[string]$InstallationId,[string]$Portal,$License=$null) {
    # Vừa chờ điện thoại gửi qua LAN, vừa cho phép gõ tay (nhấn phím bất kỳ)
    Write-Host "`n  Đang chờ Confirmation ID gửi từ điện thoại..." -ForegroundColor White
    Write-Host "  (Nhấn phím bất kỳ nếu muốn gõ tay thay vì gửi từ điện thoại)"
    $phoneProduct=if($Test){'TEST '+$Product}elseif($License){$Product+' · key …'+$License.PartialProductKey}else{$Product}
    $nextKeyCheck=[DateTime]::UtcNow
    $page = New-CidPhonePage $InstallationId $env:COMPUTERNAME $phoneProduct $Portal
    $task = $rcv.Listener.GetContextAsync()
    while ($true) {
        if(-not $Test -and $License -and [DateTime]::UtcNow -ge $nextKeyCheck){
            $null=Get-OfflineActivationLicense $License $InstallationId
            $nextKeyCheck=[DateTime]::UtcNow.AddSeconds(5)
        }
        $done = $false
        try { $done = $task.Wait(300) } catch { Write-Warn "Kết nối LAN lỗi -> chuyển sang gõ tay."; return (Read-CidKeyboard) }
        if ($done) {
            $ctx = $task.Result
            try {
                if ($ctx.Request.HttpMethod -eq 'POST') {
                    $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
                    $body = [Uri]::UnescapeDataString(($reader.ReadToEnd() -replace '\+', ' '))
                    $c = $body -replace '\D', ''
                    if ($c.Length -eq 48) {
                        Send-Html $ctx (New-CidPhonePage $InstallationId $env:COMPUTERNAME $phoneProduct $Portal '<div class="msg ok">&#10004; Đã gửi về máy tính. Xem kết quả trên màn hình máy.</div>')
                        Write-Ok "Đã nhận Confirmation ID từ điện thoại ($($ctx.Request.RemoteEndPoint.Address))"
                        return $c
                    }
                    Send-Html $ctx (New-CidPhonePage $InstallationId $env:COMPUTERNAME $phoneProduct $Portal "<div class=`"msg err`">Cần đủ 48 số, đang nhận $($c.Length) số. Dán lại.</div>")
                    Write-Warn "Điện thoại gửi $($c.Length) số (cần 48) -> đã báo lại trên điện thoại."
                } else {
                    Send-Html $ctx $page
                }
            } catch { }
            $task = $rcv.Listener.GetContextAsync()
        }
        if (Test-CidManualInput) {
            [void][Console]::ReadKey($true)
            return (Read-CidKeyboard)
        }
    }
}

# ---------- Quyền Admin ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Cần chạy bằng quyền Administrator."; exit 2
}

# ---------- CHẾ ĐỘ TEST ----------
if ($Test) {
    Write-Step "CHE DO TEST - dung ma gia, KHONG thay doi license cua may"
    $iid = '123456712345671234567123456712345671234567123456712345671234567'   # 63 số giả
    $tpl = Join-Path $PSScriptRoot 'QR-Template.html'
    if (-not (Test-Path $tpl)) { Write-Err "Thiếu QR-Template.html cạnh script."; exit 1 }
    Remove-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
    $rcv = Start-CidReceiver
    $qrWindow = $null
    try {
        $cidUrl = ''
        if ($rcv) { $cidUrl = $rcv.Url; Write-Ok "Đã mở cổng nhận: $cidUrl" }
        $qrWindow = Open-CidQrWindow $tpl $iid "$env:COMPUTERNAME (TEST)" "TEST $Product" $Url $cidUrl
        Write-Host @"

  Kiểm tra lần lượt:
    1. Quét QR 1 -> trang điện thoại có mã giả và nút Sao chép Installation ID / Mở portal Microsoft
    2. Quét QR 2 -> mở thẳng phần Gửi Confirmation ID trên cùng trang
    3. Dán 48 số bất kỳ (vd 111111 222222 333333 444444 555555 666666 777777 888888) -> Gửi
    4. Thử gửi thiếu số -> điện thoại phải báo lỗi, script vẫn chờ
"@
        if ($rcv) { $cid = Wait-Cid $rcv $iid $Url } else { $cid = Read-CidKeyboard }
        if ($cid) {
            Write-Ok ("Nhận được: " + (Format-Groups $cid 6))
            Write-Host "`n  TEST THÀNH CÔNG - chưa nạp gì vào máy." -ForegroundColor Green
        } else { Write-Warn "Không nhận được Confirmation ID." }
    } finally {
        Close-CidQrWindow $qrWindow
        Stop-CidReceiver $rcv
        if (-not (Get-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue)) {
            Write-Ok "Đã đóng cổng tường lửa tạm"
        } else { Write-Warn "Rule tường lửa '$FwRuleName' vẫn còn -> xoá tay trong Windows Defender Firewall." }
    }
    exit 0
}

# ---------- 1. Tìm sản phẩm ----------
Write-Step "1. TIM SAN PHAM $($Product.ToUpper()) (mat khoang 10-30 giay)"
try{$all = @(Get-LicProducts)}catch{Show-DeployMessage 'Chưa đọc được thông tin giấy phép. Kiểm tra lại Windows / Office rồi thử lại; chưa thay đổi key trên máy.' 'Kiểm tra bản quyền' 'Warning';exit 1}
if (-not $all) {
    $message=Get-MissingActivationKeyMessage $Product
    Write-Warn $message
    Show-DeployMessage $message ('Chưa có key '+$Product) 'Warning'
    exit 1
}
if($Product -eq 'Office' -and (Test-OfficeActivationNeedsKey $all)){
    $message='Office hiện chỉ có giấy phép Grace / Trial / Evaluation. '+(Get-MissingActivationKeyMessage 'Office')
    Show-DeployMessage $message 'Office cần key bản quyền' 'Warning'
    exit 1
}
if($Product -eq 'Office' -and (Test-OfficeActivationNeedsKey $all)){
    Show-DeployMessage ('Office đang có giấy phép Grace / Trial, chưa phải key bản quyền riêng. '+(Get-MissingActivationKeyMessage 'Office')) 'Cần nhập key Office' 'Warning'
    exit 1
}
foreach ($p in $all) {
    Write-Host ("  - {0}  (key ...{1}) : {2}" -f $p.Name, $p.PartialProductKey, $statusText[[int]$p.LicenseStatus])
}
$todo = @(Select-ActivationLicenses -Product $Product -Products $all | Where-Object { $_.LicenseStatus -ne 1 })
if (-not $todo) { Write-Ok "$Product đã kích hoạt, không cần làm gì."; Show-DeployMessage "$Product đã kích hoạt. Không cần kích hoạt lại." 'Kiểm tra bản quyền'; exit 0 }

# ---------- 1b. Thử kích hoạt online trước ----------
Write-Step "2. THU KICH HOAT ONLINE (khong can tai khoan)"
foreach ($p in $todo) {
    Write-Host "  $($p.Name) ..." -NoNewline
    try {
        $activation = Invoke-VerifiedLicenseActivation $p 'Activate'
        Write-Host ""
        if ($activation.State -eq 'Activated') { Write-Ok 'Kích hoạt online thành công (đã kiểm tra trạng thái).' }
        elseif ($activation.State -eq 'Failed') { Write-Warn ("Online thất bại: " + $activation.Detail) }
        else { Write-Warn ("Chưa xác nhận kích hoạt online: " + $activation.Detail) }
    } catch {
        $code = $_.Exception.HResult
        Write-Host ""
        Write-Warn ("Online thất bại: {0} (0x{1:X8})" -f $_.Exception.Message.Trim(), $code)
    }
}
try { Invoke-CimMethod -InputObject (Get-CimInstance SoftwareLicensingService) -MethodName RefreshLicenseStatus | Out-Null } catch {}
try{$currentProducts=@(Select-ActivationLicenses -Product $Product -Products @(Get-LicProducts))}catch{Show-DeployMessage 'Chưa đọc lại được key hiện tại. Kiểm tra lại trước khi lấy Installation ID.' 'Kiểm tra bản quyền' 'Warning';exit 1}
if(-not $currentProducts.Count){Show-DeployMessage (Get-MissingActivationKeyMessage $Product) 'Chưa xác định được key hiện tại' 'Warning';exit 1}
$todo = @($currentProducts | Where-Object { $_.LicenseStatus -ne 1 })
if (-not $todo) {
    Write-Ok "$Product đã kích hoạt online, không cần dùng portal."
    Write-Host "`n  Kiểm tra lại: $($cfg.Check)"
    Show-DeployMessage "$Product đã kích hoạt online. Kiểm tra lại trong ứng dụng Microsoft trước khi bàn giao." 'Hoàn tất kích hoạt'
    exit 0
}
if($Product -eq 'Windows'){
    try{$notice=Get-WindowsSetupActivationNotice (Get-WindowsSetupKeyInventory)}catch{Show-DeployMessage 'Chưa xác minh được key Windows. Kiểm tra lại trong Windows Settings trước khi dùng QR / portal.' 'Kiểm tra key Windows' 'Warning';exit 1}
    if($notice){Show-DeployMessage $notice 'Windows cần key riêng / bản quyền số' 'Warning';exit 1}
}
Write-Warn "Online thất bại -> chuyển sang kích hoạt qua Product Activation Portal."

if ($Product -eq 'Office') {
    Write-Warn "Đóng hết Word/Excel/PowerPoint/Outlook trước khi tiếp tục (đóng cả cửa sổ Activation Wizard)."
    if(-not (Confirm-Box 'Đã lưu tài liệu và đóng Word / Excel / PowerPoint / Outlook cùng cửa sổ Activation Wizard?' 'Chuẩn bị nạp mã' -ConfirmText 'Đã đóng Office')){exit 0}
}

# ---------- 2-4. Kích hoạt từng sản phẩm ----------
foreach ($p in $todo) {
    Write-Step "3. KICH HOAT QUA PORTAL: $($p.Name)"
    try{
        $p=Get-OfflineActivationLicense $p
        if($p.LicenseStatus -eq 1){Write-Ok 'Sản phẩm hiện đã kích hoạt, bỏ qua bước offline.';continue}
        $iid=([string]$p.OfflineInstallationId -replace '\D','')
        $details="Sản phẩm: $($p.Name)`nKey hiện tại: …$($p.PartialProductKey)`n`nĐối chiếu 5 ký tự cuối với key bạn vừa nhập trước khi lấy Installation ID."
        if(-not (Confirm-Box $details 'Xác nhận key cần kích hoạt' -ConfirmText 'Đúng key này')){continue}
        $p=Get-OfflineActivationLicense $p $iid
    }catch{Show-DeployMessage $_.Exception.GetBaseException().Message 'Chưa lấy Installation ID' 'Warning';continue}

    Write-Host "  Installation ID (9 nhóm):" -ForegroundColor White
    Write-Host ("    " + (Format-Groups $iid 7)) -ForegroundColor Yellow
    try { Set-Clipboard -Value $iid; Write-Ok "Đã copy Installation ID vào clipboard" } catch { Write-Warn "Không copy được clipboard, chép tay dãy số trên." }

    if ($Product -eq 'Office') {
        $guide = @"

  Trên trang web vừa mở:
    1. Đăng nhập tài khoản Microsoft, giải captcha
    2. Chọn Office / dán Installation ID (Ctrl+V)
    3. Nhập số máy đã cài: 1 -> Gửi -> Tiếp
    4. Bấm "Sao chép ID xác nhận" rồi quay lại cửa sổ này
"@
    } else {
        $guide = @"

  Trên trang Product Activation Portal vừa mở:
    1. Đăng nhập tài khoản Microsoft, giải captcha
    2. Chọn Windows / dán Installation ID (Ctrl+V)
    3. Làm theo câu hỏi trên trang cho đến khi hiện Confirmation ID
    4. Copy Confirmation ID rồi quay lại cửa sổ này
"@
    }
    # Chọn nơi làm portal: điện thoại (quét QR, khỏi đăng nhập trên máy này) hoặc ngay trên máy này
    $tpl = Join-Path $PSScriptRoot 'QR-Template.html'
    $mode = '2'
    if (Test-Path $tpl) {
        $choice=Select-DeployOption 'Chọn nơi thực hiện portal Microsoft. Điện thoại dùng QR và gửi mã về máy qua LAN.' 'Kích hoạt qua portal' 'Điện thoại / QR' 'Trên máy này'
        if(-not $choice){continue}
        $mode=if($choice -eq 'Primary'){'1'}else{'2'}
    }
    $cid = $null
    if ($mode -eq '1') {
        Remove-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue   # dọn rule sót lần trước
        $rcv = Start-CidReceiver
        $qrWindow = $null
        try {
            $cidUrl = ''
            if ($rcv) { $cidUrl = $rcv.Url }
            $qrWindow = Open-CidQrWindow $tpl $iid $env:COMPUTERNAME ($Product+' · key …'+$p.PartialProductKey) $Url $cidUrl
            Write-Host "`n  Đã mở trang QR trên trình duyệt:"
            Write-Host "    QR 1: mở trang trên điện thoại -> Sao chép Installation ID -> Mở portal Microsoft"
            if ($rcv) {
                Write-Host "    QR 2: quét mở trang gửi Confirmation ID về máy này ($cidUrl)"
                Write-Host "          (điện thoại phải CHUNG MẠNG Wi-Fi/LAN với máy này)" -ForegroundColor Yellow
                $cid = Wait-Cid $rcv $iid $Url $p
            } else {
                $cid = Read-CidKeyboard
            }
        } catch {
            Show-DeployMessage $_.Exception.GetBaseException().Message 'Dừng QR / kiểm tra lại key' 'Warning'
            continue
        } finally {
            Close-CidQrWindow $qrWindow
            Stop-CidReceiver $rcv
        }
    } else {
        Write-Host $guide
        Start-Process $Url
        $cid = Read-CidKeyboard
    }
    if (-not $cid) { Write-Warn "Bỏ qua $($p.Name)"; continue }
    Write-Host ("  Confirmation ID: " + (Format-Groups $cid 6))

    try {
        $activation = Invoke-VerifiedLicenseActivation $p 'DepositOfflineConfirmationId' $iid $cid
        if ($activation.State -eq 'Activated') {
            Write-Ok 'Sản phẩm ĐÃ KÍCH HOẠT sau khi nạp Confirmation ID (đã kiểm tra trạng thái).'
        } elseif ($activation.State -eq 'Failed') {
            Write-Err ("Nạp Confirmation ID thất bại: " + $activation.Detail)
            Write-Host '  Xem lỗi trên. Nếu cần lấy lại CID, dùng đúng Installation ID của license này.'
        } else {
            Write-Warn ("Đã gửi Confirmation ID nhưng chưa xác nhận kích hoạt: " + $activation.Detail)
            Write-Host ("  Kiểm tra lại: " + $cfg.Check)
        }
    } catch {
        Write-Err "Nạp Confirmation ID thất bại: $($_.Exception.Message)"
        Show-DeployMessage $_.Exception.GetBaseException().Message 'Chưa nạp Confirmation ID' 'Warning'
        continue
    }
}

# ---------- 5. Kiểm tra ----------
Write-Step "4. TRANG THAI SAU KHI KICH HOAT"
try { Invoke-CimMethod -InputObject (Get-CimInstance SoftwareLicensingService) -MethodName RefreshLicenseStatus | Out-Null } catch {}
foreach ($p in @(Get-LicProducts)) {
    $s = [int]$p.LicenseStatus
    $line = "  - {0} : {1}" -f $p.Name, $statusText[$s]
    if ($s -eq 1) { Write-Host $line -ForegroundColor Green } else { Write-Host $line -ForegroundColor Red }
}
Write-Host "`n  Kiểm tra lại: $($cfg.Check)"
