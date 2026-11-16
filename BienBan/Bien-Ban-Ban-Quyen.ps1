<#
.SYNOPSIS
    Xuất "Biên bản kiểm tra trạng thái bản quyền phần mềm" (Windows / Office) ra file HTML
    để in hoặc lưu PDF giao cho khách.

    - Chỉ ĐỌC trạng thái license (WMI SoftwareLicensingProduct), không thay đổi gì trên máy.
    - Chỉ in 5 ký tự cuối của key, không in key đầy đủ / Installation ID / Confirmation ID.
    - Thông tin đơn vị + kỹ thuật viên lưu ở BienBan-Config.json cạnh script (nhập 1 lần).
    - File xuất: thư mục BienBan\ cạnh script, tên <TênMáy>_<yyyyMMdd_HHmm>.html
#>
param(
    [string]$Customer,
    [string]$Invoice,
    [string]$Technician,
    [switch]$NoPrompt      # GUI gọi: không hỏi, không pause
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# ---------- Cấu hình đơn vị / kỹ thuật viên (lưu cạnh script, nhập 1 lần) ----------
$cfgFile = Join-Path $here 'BienBan-Config.json'
$cfg = $null
if (Test-Path $cfgFile) { try { $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null } }
if (-not $cfg -and $NoPrompt) { $cfg = [pscustomobject]@{ Company = ''; Address = ''; Phone = ''; Technician = '' } }
if (-not $cfg) {
    Write-Host "`nLần đầu chạy: nhập thông tin đơn vị (lưu vào BienBan-Config.json, lần sau không hỏi lại)" -ForegroundColor Cyan
    $cfg = [pscustomobject]@{
        Company    = Read-Host "  Tên đơn vị"
        Address    = Read-Host "  Địa chỉ"
        Phone      = Read-Host "  Điện thoại"
        Technician = Read-Host "  Kỹ thuật viên"
    }
    $cfg | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8
}

Write-Host "`n=== BIEN BAN KIEM TRA BAN QUYEN ===" -ForegroundColor Cyan
if ($NoPrompt) {
    $customer = $Customer; $invoice = $Invoice
    if (-not [string]::IsNullOrWhiteSpace($Technician)) { $cfg.Technician = $Technician }
} else {
    $customer = Read-Host "  Tên khách hàng / đơn vị (Enter để bỏ trống)"
    $invoice  = Read-Host "  Số hóa đơn / nguồn mua key (Enter để bỏ trống)"
    $techIn   = Read-Host "  Kỹ thuật viên (Enter = $($cfg.Technician))"
    if (-not [string]::IsNullOrWhiteSpace($techIn)) { $cfg.Technician = $techIn }
}

# ---------- Đọc thông tin máy ----------
Write-Host "  Đang đọc thông tin bản quyền (10-30 giây)..."
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem

$statusText = @{ 0 = 'Chưa có license'; 1 = 'Đã kích hoạt'; 2 = 'Chưa kích hoạt (dùng thử)'; 3 = 'Chưa kích hoạt (hết hạn dùng thử)';
                 4 = 'Không hợp lệ (Non-Genuine)'; 5 = 'Chưa kích hoạt'; 6 = 'Chưa kích hoạt (gia hạn)' }

function Get-Channel($p) {
    # ProductKeyChannel có từ Windows 10; bản cũ thì đọc từ Description
    $ch = ''
    try { $ch = [string]$p.ProductKeyChannel } catch {}
    if (-not $ch) {
        $d = [string]$p.Description
        if     ($d -match 'RETAIL')        { $ch = 'Retail' }
        elseif ($d -match 'OEM')           { $ch = 'OEM' }
        elseif ($d -match 'VOLUME_KMS')    { $ch = 'Volume:GVLK' }
        elseif ($d -match 'VOLUME_MAK')    { $ch = 'Volume:MAK' }
        elseif ($d -match 'TIMEBASED_SUB') { $ch = 'Subscription' }
    }
    switch -Regex ($ch) {
        '^Retail'        { return 'Bán lẻ (Retail)' }
        '^OEM:DM'        { return 'OEM – key gắn trong BIOS (OEM:DM)' }
        '^OEM'           { return "OEM ($ch)" }
        '^Volume:GVLK'   { return 'Volume – KMS (GVLK)' }
        '^Volume:MAK'    { return 'Volume – MAK' }
        '^Volume'        { return "Volume ($ch)" }
        '^$'             { return 'Không xác định' }
        default          { return $ch }
    }
}

function Get-Products([string]$appId) {
    @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='$appId' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue)
}

function HtmlEnc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

function New-ProductRows($products, [string]$emptyText) {
    if (-not $products -or $products.Count -eq 0) {
        return "<tr><td colspan='4' class='muted'>$(HtmlEnc $emptyText)</td></tr>"
    }
    $rows = foreach ($p in $products) {
        $s = [int]$p.LicenseStatus
        $cls = if ($s -eq 1) { 'ok' } else { 'bad' }
        $st = $statusText[$s]
        $ch = Get-Channel $p
        # Volume KMS: kích hoạt có thời hạn -> ghi số ngày còn lại
        if ($s -eq 1 -and $ch -like 'Volume – KMS*' -and $p.GracePeriodRemaining -gt 0) {
            $st += " (KMS, còn $([math]::Floor($p.GracePeriodRemaining / 1440)) ngày, cần gia hạn định kỳ)"
        }
        $name = HtmlEnc ([string]$p.Name)
        if ($p.Description) { $name += "<div class='sub'>$(HtmlEnc ([string]$p.Description))</div>" }
        "<tr><td>$name</td><td>$(HtmlEnc $ch)</td><td class='mono'>*****-$(HtmlEnc ([string]$p.PartialProductKey))</td><td class='$cls'>$(HtmlEnc $st)</td></tr>"
    }
    return ($rows -join "`n")
}

$win = Get-Products '55c92734-d682-4d71-983e-d6ec3f16059f'
$off = Get-Products '0ff1ce15-a989-479d-af46-f275c6370663'

$now = Get-Date
$serial = ([string]$bios.SerialNumber).Trim()
if ($serial -match 'to be filled|default string|system serial|^0+$|^$') { $serial = "$serial (BIOS không có serial)" }

$winAll = $win.Count -gt 0 -and -not ($win | Where-Object { $_.LicenseStatus -ne 1 })
$offAll = $off.Count -eq 0 -or -not ($off | Where-Object { $_.LicenseStatus -ne 1 })
if ($winAll -and $offAll) { $summary = '<div class="sum ok">Tất cả sản phẩm phát hiện được đều ở trạng thái <b>Đã kích hoạt</b>.</div>' }
else                      { $summary = '<div class="sum bad">Có sản phẩm <b>chưa kích hoạt</b> – xem chi tiết bên dưới.</div>' }

# ---------- Mẫu biên bản ----------
$html = @'
<!DOCTYPE html>
<html lang="vi"><head><meta charset="utf-8">
<title>Biên bản bản quyền - {{PC}}</title>
<style>
 @page { size: A4; margin: 14mm 14mm 16mm 14mm; }
 * { box-sizing: border-box; }
 body { font-family: "Segoe UI", Arial, sans-serif; color: #111827; font-size: 13.5px; margin: 0; background: #f3f4f6; }
 .page { background: #fff; max-width: 210mm; margin: 16px auto; padding: 14mm; box-shadow: 0 2px 10px rgba(0,0,0,.08); }
 .head { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #1f2937; padding-bottom: 8px; }
 .brand { display: flex; align-items: center; gap: 12px; } .brand img { height: 64px; width: auto; }
 .head .co { font-weight: 700; font-size: 15px; } .head .small { color: #4b5563; font-size: 12.5px; }
 h1 { text-align: center; font-size: 19px; margin: 18px 0 2px; letter-spacing: .3px; }
 .date { text-align: center; color: #4b5563; margin-bottom: 14px; }
 h2 { font-size: 14px; margin: 16px 0 6px; padding-left: 8px; border-left: 4px solid #0067c0; }
 table { width: 100%; border-collapse: collapse; }
 th, td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; vertical-align: top; }
 th { background: #f3f4f6; font-weight: 600; }
 table.kv td:first-child { width: 32%; background: #f9fafb; font-weight: 600; }
 .mono { font-family: Consolas, monospace; }
 .ok  { color: #166534; font-weight: 700; } .bad { color: #b91c1c; font-weight: 700; }
 .muted { color: #6b7280; font-style: italic; } .sub { color: #6b7280; font-size: 11.5px; margin-top: 2px; }
 .sum { margin: 12px 0 2px; padding: 9px 12px; border-radius: 6px; }
 .sum.ok { background: #ecfdf5; border: 1px solid #a7f3d0; } .sum.bad { background: #fef2f2; border: 1px solid #fecaca; }
 ol { margin: 4px 0 0 18px; padding: 0; line-height: 1.6; }
 .note { margin-top: 14px; padding: 9px 12px; background: #fffbeb; border: 1px solid #fde68a; border-radius: 6px; font-size: 12.5px; }
 .sign { display: flex; justify-content: space-between; margin-top: 26px; text-align: center; }
 .sign > div { width: 45%; } .sign .hint, .sign .space { width: auto; } .sign .hint { color: #6b7280; font-size: 12px; } .sign .space { height: 70px; }
 .bar { max-width: 210mm; margin: 12px auto 0; text-align: right; }
 .bar button { padding: 8px 18px; font-size: 14px; background: #0067c0; color: #fff; border: 0; border-radius: 6px; cursor: pointer; }
 @media print { body { background: #fff; font-size: 12.5px; } .page { box-shadow: none; margin: 0; padding: 0; max-width: none; } .bar { display: none; }
   h1 { margin-top: 12px; } h2 { margin: 11px 0 5px; } th, td { padding: 4px 7px; } .sign { margin-top: 16px; } .sign .space { height: 60px; } }
</style></head><body>
<div class="bar"><button onclick="window.print()">In / Lưu PDF</button></div>
<div class="page">
 <div class="head">
  <div class="brand">{{LOGO}}<div><div class="co">{{COMPANY}}</div><div class="small">{{ADDRESS}}</div><div class="small">ĐT: {{PHONE}}</div></div></div>
  <div class="small" style="text-align:right">Số: {{DOCNO}}</div>
 </div>

 <h1>BIÊN BẢN KIỂM TRA TRẠNG THÁI BẢN QUYỀN PHẦN MỀM</h1>
 <div class="date">Thời điểm kiểm tra: {{DATETIME}}</div>

 <h2>1. Thông tin chung</h2>
 <table class="kv">
  <tr><td>Khách hàng</td><td>{{CUSTOMER}}</td></tr>
  <tr><td>Kỹ thuật viên</td><td>{{TECH}}</td></tr>
  <tr><td>Số hóa đơn / nguồn mua key</td><td>{{INVOICE}}</td></tr>
 </table>

 <h2>2. Thông tin máy</h2>
 <table class="kv">
  <tr><td>Tên máy</td><td class="mono">{{PC}}</td></tr>
  <tr><td>Hãng / Model</td><td>{{MODEL}}</td></tr>
  <tr><td>Serial BIOS</td><td class="mono">{{SERIAL}}</td></tr>
  <tr><td>Hệ điều hành</td><td>{{OS}}</td></tr>
 </table>

 {{SUMMARY}}

 <h2>3. Windows</h2>
 <table>
  <tr><th style="width:38%">Sản phẩm</th><th>Kênh phân phối</th><th>Key</th><th>Trạng thái</th></tr>
  {{WINROWS}}
 </table>

 <h2>4. Microsoft Office</h2>
 <table>
  <tr><th style="width:38%">Sản phẩm</th><th>Kênh phân phối</th><th>Key</th><th>Trạng thái</th></tr>
  {{OFFROWS}}
 </table>

 <h2>5. Khách hàng tự kiểm tra lại</h2>
 <ol>
  <li><b>Windows:</b> Settings → System → Activation → mục <i>Activation state</i> phải là <b>Active</b>.</li>
  <li><b>Office:</b> mở Word → File → Account → phải có dòng <b>Product Activated</b>.</li>
  <li>Hoặc mở Command Prompt, gõ <span class="mono">slmgr /dlv</span> → dòng <i>License Status</i> phải là <b>Licensed</b>.</li>
 </ol>

 <div class="note">
  <b>Ghi chú:</b> Biên bản phản ánh trạng thái kích hoạt do Windows / Office báo tại thời điểm kiểm tra.
  Đây <b>không phải</b> chứng nhận do Microsoft cấp. Key chỉ in 5 ký tự cuối để bảo mật.
  Bằng chứng mua bản quyền hợp lệ là hóa đơn / chứng từ mua hàng ghi ở mục 1.
 </div>

 <div class="sign">
  <div><b>Kỹ thuật viên</b><div class="hint">(ký, ghi rõ họ tên)</div><div class="space"></div>{{TECH}}</div>
  <div><b>Khách hàng</b><div class="hint">(ký, ghi rõ họ tên)</div><div class="space"></div>{{CUSTOMER_SIGN}}</div>
 </div>
</div>
</body></html>
'@

$dash = '<span class="muted">—</span>'
function OrDash([string]$v) { if ([string]::IsNullOrWhiteSpace($v)) { $dash } else { HtmlEnc $v } }

# Logo: file Logo.svg / Logo.png / Logo.jpg cạnh script, nhúng thẳng vào HTML (base64)
$logoTag = ''
foreach ($ext in 'svg', 'png', 'jpg', 'jpeg') {
    $lf = Join-Path $here "Logo.$ext"
    if (Test-Path $lf) {
        $mime = @{ svg = 'image/svg+xml'; png = 'image/png'; jpg = 'image/jpeg'; jpeg = 'image/jpeg' }[$ext]
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($lf))
        $logoTag = "<img src=`"data:$mime;base64,$b64`" alt=`"Logo`">"
        break
    }
}
$html = $html.Replace('{{LOGO}}', $logoTag)
$html = $html.Replace('{{COMPANY}}',  (OrDash $cfg.Company)).Replace('{{ADDRESS}}', (OrDash $cfg.Address))
$html = $html.Replace('{{PHONE}}',    (OrDash $cfg.Phone)).Replace('{{TECH}}', (OrDash $cfg.Technician))
$html = $html.Replace('{{DOCNO}}',    ("BB-{0:yyyyMMdd-HHmm}-{1}" -f $now, $env:COMPUTERNAME))
$html = $html.Replace('{{DATETIME}}', ("{0:HH:mm}, ngày {0:dd/MM/yyyy}" -f $now))
$html = $html.Replace('{{CUSTOMER}}', (OrDash $customer)).Replace('{{INVOICE}}', (OrDash $invoice))
$html = $html.Replace('{{CUSTOMER_SIGN}}', $(if ($customer) { HtmlEnc $customer } else { '' }))
$html = $html.Replace('{{PC}}',       (HtmlEnc $env:COMPUTERNAME))
$html = $html.Replace('{{MODEL}}',    (OrDash ("{0} {1}" -f $cs.Manufacturer, $cs.Model).Trim()))
$html = $html.Replace('{{SERIAL}}',   (OrDash $serial))
$html = $html.Replace('{{OS}}',       (OrDash ("{0} (build {1})" -f $os.Caption, $os.BuildNumber)))
$html = $html.Replace('{{SUMMARY}}',  $summary)
$html = $html.Replace('{{WINROWS}}',  (New-ProductRows $win 'Không đọc được thông tin Windows'))
$html = $html.Replace('{{OFFROWS}}',  (New-ProductRows $off 'Không phát hiện Office (hoặc Office không dùng key, ví dụ Microsoft 365 đăng nhập tài khoản)'))

# ---------- Ghi file + mở ----------
$outDir = Join-Path $here 'BienBan'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory $outDir | Out-Null }
$outFile = Join-Path $outDir ("{0}_{1:yyyyMMdd_HHmm}.html" -f $env:COMPUTERNAME, $now)
[IO.File]::WriteAllText($outFile, $html, (New-Object Text.UTF8Encoding $true))

Write-Host ""
foreach ($p in @($win) + @($off)) {
    $s = [int]$p.LicenseStatus
    $c = if ($s -eq 1) { 'Green' } else { 'Red' }
    Write-Host ("  - {0} (...{1}): {2}" -f $p.Name, $p.PartialProductKey, $statusText[$s]) -ForegroundColor $c
}
Write-Host "`n  [OK] Đã xuất: $outFile" -ForegroundColor Green
Write-Host "  Bấm nút 'In / Lưu PDF' trên trang (hoặc Ctrl+P -> Microsoft Print to PDF)."
Start-Process $outFile
if ($NoPrompt) { Write-Output $outFile }
