<#
  TechMaster Deploy - giao diện đồ họa gom 3 bộ công cụ:
    FixClone\   : chuẩn bị máy gốc + Sysprep, xử lý máy sau clone, định dạng ngày giờ
    KichHoat\   : kích hoạt Windows / Office (online -> portal, QR, nhận CID qua LAN)
    BienBan\    : xuất biên bản kiểm tra trạng thái bản quyền
  Chạy bằng TechMaster Deploy.exe (tự xin quyền Administrator).
#>
# Báo Windows là app tự xử lý DPI -> chữ nét trên màn hình Scale 125% / 150%
# (phải gọi TRƯỚC khi tạo bất kỳ cửa sổ nào)
Add-Type -Namespace TMDeploy -Name Dpi -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
try { [void][TMDeploy.Dpi]::SetProcessDPIAware() } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'RoundedTheme.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch {}

$Root     = Split-Path -Parent $PSScriptRoot
$DirClone = Join-Path $Root 'FixClone'
$DirKH    = Join-Path $Root 'KichHoat'
$DirBB    = Join-Path $Root 'BienBan'

# ---------- Màu / font ----------
$cPrimary = [System.Drawing.Color]::FromArgb(16, 34, 63)     # #10223F
$cAction  = [System.Drawing.Color]::FromArgb(31, 61, 103)    # #1F3D67
$cHover   = [System.Drawing.Color]::FromArgb(44, 78, 122)
$cBorder  = [System.Drawing.Color]::FromArgb(198, 213, 230)
$cSoft    = [System.Drawing.Color]::FromArgb(235, 243, 253)
$cMuted   = [System.Drawing.Color]::FromArgb(71, 89, 114)
$cDanger  = [System.Drawing.Color]::FromArgb(185, 28, 28)
$cBg      = [System.Drawing.Color]::FromArgb(238, 243, 249)
$fBase    = New-Object System.Drawing.Font('Segoe UI', 10)
$fBold    = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$fTitle   = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

# ---------- Helpers ----------
function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, $font = $fBase) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h); $l.Font = $font
    return $l
}

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$danger = $false, [switch]$secondary) {
    $b = New-Object TechMaster.RoundedButton
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h); $b.Font = $fBold
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.ForeColor = [System.Drawing.Color]::White
    if ($secondary) {
        $b.ForeColor = $cPrimary
        $b.BackColor = $cSoft
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = $cBorder
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(222, 234, 250)
    } elseif ($danger) {
        $b.BackColor = $cDanger
    } else {
        $b.BackColor = $cAction
        $b.FlatAppearance.MouseOverBackColor = $cHover
    }
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

function New-TextBox([int]$x, [int]$y, [int]$w, [string]$text = '') {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, 26); $t.Font = $fBase; $t.Text = $text
    return $t
}

function Set-Status([string]$msg) { $script:status.Text = "  $msg" }

function Start-Tool([string]$file, [string]$label) {
    if (-not (Test-Path $file)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy:`n$file", 'TechMaster Deploy', 'OK', 'Error') | Out-Null
        return
    }
    # Mỗi công cụ chạy trong cửa sổ console riêng (các script có bước hỏi / xác nhận)
    Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c ""{0}""' -f $file) -WorkingDirectory (Split-Path $file)
    Set-Status "Đã mở: $label  ($([IO.Path]::GetFileName($file)))"
}

function Confirm-Box([string]$msg, [string]$title = 'Xác nhận') {
    $r = [System.Windows.Forms.MessageBox]::Show($msg, $title, 'YesNo', 'Warning', 'Button2')
    return ($r -eq 'Yes')
}

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.SuspendLayout()
$form.Text = 'TechMaster Deploy - Clone / Kích hoạt / Biên bản bản quyền'
$form.ClientSize = New-Object System.Drawing.Size(900, 602)
$form.StartPosition = 'CenterScreen'
$form.Font = $fBase
$form.BackColor = $cBg
$form.ForeColor = $cPrimary
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$icoFile = Join-Path $PSScriptRoot 'TechMaster.ico'
if (Test-Path $icoFile) { try { $form.Icon = New-Object System.Drawing.Icon($icoFile) } catch {} }   # icon cửa sổ + taskbar

# Thanh thông tin máy
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 78
$header.BackColor = $cPrimary
$form.Controls.Add($header)

$lblTitle = New-Label 'TechMaster Deploy' 16 10 400 28 $fTitle
$lblTitle.ForeColor = [System.Drawing.Color]::White
$header.Controls.Add($lblTitle)

$lblInfo = New-Label 'Đang đọc thông tin máy...' 16 42 720 26
$lblInfo.ForeColor = $cBorder
$header.Controls.Add($lblInfo)

$btnRefresh = New-Button 'Làm mới' 772 24 96 32
$btnRefresh.FlatAppearance.BorderSize = 1
$btnRefresh.FlatAppearance.BorderColor = $cHover
$header.Controls.Add($btnRefresh)

function Update-MachineInfo {
    $lblInfo.Text = 'Đang đọc thông tin bản quyền (10-30 giây)...'
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnRefresh.Enabled = $false
    $lblInfo.Refresh()
    try {
        $win = @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue)
        $off = @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='0ff1ce15-a989-479d-af46-f275c6370663' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue)
        if ($win.Count -eq 0) { $w = 'không đọc được' }
        elseif ($win | Where-Object { $_.LicenseStatus -ne 1 }) { $w = 'CHƯA kích hoạt' } else { $w = 'Đã kích hoạt' }
        if ($off.Count -eq 0) { $o = 'không phát hiện' }
        elseif ($off | Where-Object { $_.LicenseStatus -ne 1 }) { $o = 'CHƯA kích hoạt' } else { $o = 'Đã kích hoạt' }
        $lblInfo.Text = "Máy: $env:COMPUTERNAME     Windows: $w     Office: $o"
    } catch {
        $lblInfo.Text = "Máy: $env:COMPUTERNAME     (không đọc được bản quyền: $($_.Exception.Message))"
    } finally {
        $btnRefresh.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}
$btnRefresh.Add_Click({ Update-MachineInfo })

# Tabs
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, 90); $tabs.Size = New-Object System.Drawing.Size(876, 470)
$tabs.Font = $fBold
$tabs.Padding = New-Object System.Drawing.Point(10, 4)
$form.Controls.Add($tabs)

function New-Tab([string]$title) {
    $t = New-Object System.Windows.Forms.TabPage
    $t.Text = $title; $t.BackColor = [System.Drawing.Color]::White; $t.Font = $fBase
    $tabs.TabPages.Add($t)
    return $t
}

function New-Card($tab, [int]$y, [string]$title, [string]$desc, [int]$descriptionWidth = 590) {
    $card = New-Object TechMaster.RoundedCard
    $card.Location = New-Object System.Drawing.Point(12, ($y - 4))
    $card.Size = New-Object System.Drawing.Size(844, 88)
    $heading = New-Label $title 16 10 600 24 $fBold
    $heading.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($heading)
    $details = New-Label $desc 16 36 $descriptionWidth 46
    $details.ForeColor = $cMuted
    $details.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($details)
    $tab.Controls.Add($card)
    return $card
}

function Add-Card($tab, [int]$y, [string]$title, [string]$desc, [string]$btnText, [scriptblock]$onClick, [bool]$danger = $false) {
    $card = New-Card $tab $y $title $desc
    $button = New-Button $btnText 628 22 190 44 $danger
    $button.Add_Click($onClick)
    $card.Controls.Add($button)
}

# ===== Tab 1: Máy gốc =====
$t1 = New-Tab 'Máy gốc (Sysprep)'
$warn = New-Label 'Làm trên MÁY GỐC. Đóng Word, rút mạng trước khi chạy. Sau khi sysprep máy tự tắt: KHÔNG bật lại, clone ngay.' 20 14 810 40
$warn.ForeColor = $cDanger; $warn.Font = $fBold
$t1.Controls.Add($warn)
Add-Card $t1 64 '1. Kiểm tra và sửa lỗi Sysprep' `
    'BitLocker, sysprep treo, Appx cài cho user chưa provision (ArmouryCrate, WinRAR.ShellExtension, Widgets...), service ASUS. Hỏi trước khi gỡ.' `
    'Kiểm tra lỗi' { Start-Tool (Join-Path $DirClone 'Fix-SysprepErrors.bat') 'Kiểm tra lỗi Sysprep' }
Add-Card $t1 160 '2. Chuẩn bị máy gốc và chạy Sysprep' `
    'Chrome mặc định, shortcut Word/Excel, EVKey, thiết lập Word, menu chuột phải Win 10, dấu số -> áp cho user mới. Kiểm tra lỗi lại, gõ YES để chạy sysprep.' `
    'Chạy Sysprep' {
        if (Confirm-Box "Chạy chuẩn bị máy gốc và Sysprep?`n`nCuối quy trình máy sẽ TỰ TẮT. Không bật lại máy gốc trước khi clone." 'Sysprep') {
            Start-Tool (Join-Path $DirClone 'Run-Sysprep.bat') 'Chuẩn bị + Sysprep'
        }
    } $true
Add-Card $t1 256 'Thư mục cài lại phần mềm (Reinstall)' `
    'Bỏ file cài .exe / .msi vào đây, máy clone sẽ tự cài lần đăng nhập đầu. .exe chạy /S; cần tham số khác thì tạo file .args cùng tên.' `
    'Mở thư mục' { Start-Process explorer.exe (Join-Path $DirClone 'Reinstall') }

# ===== Tab 2: Sau khi clone =====
$t2 = New-Tab 'Sau khi clone'
$t2.Controls.Add((New-Label 'Máy clone đã chạy tự động lần đầu qua unattend.xml. Dùng các nút dưới đây khi cần chạy lại bằng tay.' 20 14 810 40))
Add-Card $t2 64 'Xử lý thông tin trùng lặp' `
    'Đổi tên máy (PC- + Serial BIOS / 6 ký tự cuối MAC, kiểm trùng LAN), MachineGuid mới, Windows Update ID, ID AnyDesk / TeamViewer, service ASUS, định dạng.' `
    'Xử lý trùng lặp' { Start-Tool (Join-Path $DirClone 'Fix-CloneDuplicate.bat') 'Xử lý trùng lặp' } $true
Add-Card $t2 160 'Định dạng số' `
    'Thập phân ",", phân nhóm "." (123.456.789,00). Giữ nguyên vùng, ngôn ngữ, ngày giờ và bàn phím.' `
    'Chỉnh dấu số' { Start-Tool (Join-Path $DirClone 'Fix-DinhDang.bat') 'Chỉnh định dạng' }
Add-Card $t2 256 'Bàn phím US cho EVKey' 'Tránh chuyển nhầm sang bộ gõ tiếng Việt của Windows. Giữ ngôn ngữ hiển thị, có sao lưu và khôi phục.' `
    'Bàn phím / EVKey' { Start-Tool (Join-Path $DirClone 'Fix-BanPhim.bat') 'Bàn phím cho EVKey' }
Add-Card $t2 352 'Hướng dẫn FixClone' 'Quy trình đầy đủ, danh sách lỗi Sysprep đã gặp và cách xử lý.' `
    'Mở README' { Start-Process notepad.exe ('"{0}"' -f (Join-Path $DirClone 'README.md')) }

# ===== Tab 3: Kích hoạt =====
$t3 = New-Tab 'Kích hoạt'
$t3.Controls.Add((New-Label 'Thử online trước; thất bại thì qua Product Activation Portal (QR trên điện thoại, gửi Confirmation ID về máy qua LAN). Key phải hợp lệ, khai đúng số máy.' 20 14 810 40))
Add-Card $t3 64 'Kích hoạt Windows' 'Portal: aka.ms/WindowsActivate -> Activate a Microsoft Product.' `
    'Kích hoạt Windows' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Windows.bat') 'Kích hoạt Windows' }
Add-Card $t3 160 'Kích hoạt Office' 'Portal: visualsupport.microsoft.com. Đóng Word / Excel trước khi nạp Confirmation ID.' `
    'Kích hoạt Office' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Office.bat') 'Kích hoạt Office' }
Add-Card $t3 256 'Chạy thử QR + gửi qua LAN' 'Dùng mã giả, không thay đổi license. Kiểm tra điện thoại và máy có chung mạng không.' `
    'Chạy TEST' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-TEST.bat') 'TEST kích hoạt' }

# ===== Tab 4: Biên bản =====
$t4 = New-Tab 'Biên bản'
$cfgFile = Join-Path $DirBB 'BienBan-Config.json'
$cfg = $null
if (Test-Path $cfgFile) { try { $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
if (-not $cfg) { $cfg = [pscustomobject]@{ Company = ''; Address = ''; Phone = ''; Technician = '' } }

$t4.Controls.Add((New-Label 'Thông tin đơn vị (lưu lại cho lần sau)' 20 14 400 24 $fBold))
$rows = @(
    @('Tên đơn vị', 'Company'), @('Địa chỉ', 'Address'), @('Điện thoại', 'Phone'), @('Kỹ thuật viên', 'Technician')
)
$tb = @{}
$y = 46
foreach ($r in $rows) {
    $t4.Controls.Add((New-Label $r[0] 20 ($y + 3) 130 24))
    $tb[$r[1]] = New-TextBox 150 $y 460 ([string]$cfg.($r[1]))
    $t4.Controls.Add($tb[$r[1]])
    $y += 34
}
$t4.Controls.Add((New-Label 'Thông tin lần xuất này' 20 ($y + 8) 400 24 $fBold))
$y += 40
$t4.Controls.Add((New-Label 'Khách hàng' 20 ($y + 3) 130 24)); $tbCustomer = New-TextBox 150 $y 460; $t4.Controls.Add($tbCustomer); $y += 34
$t4.Controls.Add((New-Label 'Số hóa đơn' 20 ($y + 3) 130 24)); $tbInvoice = New-TextBox 150 $y 460; $t4.Controls.Add($tbInvoice); $y += 44

# Logo
$logoBox = New-Object System.Windows.Forms.PictureBox
$logoBox.Location = New-Object System.Drawing.Point(660, 46); $logoBox.Size = New-Object System.Drawing.Size(160, 120)
$logoBox.SizeMode = 'Zoom'; $logoBox.BorderStyle = 'FixedSingle'
$t4.Controls.Add($logoBox)
$lblLogo = New-Label '' 640 170 200 40
$lblLogo.TextAlign = 'TopCenter'
$t4.Controls.Add($lblLogo)

# Khung xem trước SVG: PictureBox không đọc được SVG -> dùng WebBrowser (MSHTML, ép chế độ IE11)
$logoWeb = New-Object System.Windows.Forms.WebBrowser
$logoWeb.Location = $logoBox.Location; $logoWeb.Size = $logoBox.Size
$logoWeb.ScrollBarsEnabled = $false; $logoWeb.IsWebBrowserContextMenuEnabled = $false
$logoWeb.AllowWebBrowserDrop = $false; $logoWeb.Visible = $false
$t4.Controls.Add($logoWeb)

function Update-LogoPreview {
    $logoBox.Image = $null
    $logoWeb.Visible = $false; $logoBox.Visible = $true
    $f = Get-ChildItem $DirBB -File -ErrorAction SilentlyContinue |
         Where-Object { $_.BaseName -eq 'Logo' -and $_.Extension -in '.svg', '.png', '.jpg', '.jpeg' } | Select-Object -First 1
    if (-not $f) { $lblLogo.Text = 'Chưa có logo'; return }
    $lblLogo.Text = $f.Name
    try {
        if ($f.Extension -eq '.svg') {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
            $logoWeb.DocumentText = '<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">' +
                '<style>html,body{margin:0;height:100%;background:#fff;overflow:hidden}' +
                'body{display:flex;align-items:center;justify-content:center}' +
                'img{max-width:94%;max-height:94%}</style></head><body>' +
                "<img src=`"data:image/svg+xml;base64,$b64`"></body></html>"
            $logoBox.Visible = $false; $logoWeb.Visible = $true
        } else {
            # Đọc qua MemoryStream để không khoá file (đổi logo sau đó vẫn ghi đè được)
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            $logoBox.Image = [System.Drawing.Image]::FromStream((New-Object IO.MemoryStream (, $bytes)))
        }
    } catch { $lblLogo.Text = "$($f.Name) (không xem trước được)" }
}
$btnLogo = New-Button 'Chọn logo...' 680 212 120 30 -secondary
$btnLogo.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Logo (*.svg;*.png;*.jpg)|*.svg;*.png;*.jpg;*.jpeg'
    if ($dlg.ShowDialog() -eq 'OK') {
        Get-ChildItem $DirBB -File | Where-Object { $_.BaseName -eq 'Logo' } | Remove-Item -Force
        $ext = [IO.Path]::GetExtension($dlg.FileName).ToLower()
        Copy-Item $dlg.FileName (Join-Path $DirBB "Logo$ext") -Force
        Update-LogoPreview
        Set-Status "Đã đặt logo: $([IO.Path]::GetFileName($dlg.FileName))"
    }
})
$t4.Controls.Add($btnLogo)

$btnExport = New-Button 'Xuất biên bản' 150 $y 220 46
$btnExport.Add_Click({
    # Lưu cấu hình đơn vị
    $newCfg = [pscustomobject]@{
        Company = $tb['Company'].Text.Trim(); Address = $tb['Address'].Text.Trim()
        Phone = $tb['Phone'].Text.Trim(); Technician = $tb['Technician'].Text.Trim()
    }
    $newCfg | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8

    Set-Status 'Đang đọc bản quyền và xuất biên bản (10-30 giây)...'
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $bbScript = Join-Path $DirBB 'Bien-Ban-Ban-Quyen.ps1'
        $out = & $bbScript -NoPrompt -Customer $tbCustomer.Text.Trim() -Invoice $tbInvoice.Text.Trim() -Technician $newCfg.Technician 6>$null
        $file = @($out | Where-Object { $_ -is [string] -and $_ -like '*.html' })[-1]
        if ($file) { Set-Status "Đã xuất: $file" } else { Set-Status 'Đã chạy xuất biên bản (xem thư mục BienBan\BienBan)' }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Lỗi khi xuất biên bản:`n$($_.Exception.Message)", 'Biên bản', 'OK', 'Error') | Out-Null
        Set-Status 'Xuất biên bản lỗi'
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
})
$t4.Controls.Add($btnExport)

$btnOpenBB = New-Button 'Mở thư mục biên bản' 390 ($y + 8) 180 32 -secondary
$btnOpenBB.Add_Click({
    $d = Join-Path $DirBB 'BienBan'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null }
    Start-Process explorer.exe $d
})
$t4.Controls.Add($btnOpenBB)

# ===== Tab 5: Tải / cài Office (Office Deployment Tool) =====
$DirOffice = Join-Path $Root 'Office'
$KhoOffice = Join-Path $Root 'KhoOffice'
$t5 = New-Tab 'Tải / cài Office'

$offProducts = @(
    @('HomeBusiness2024Retail', 'Office Home & Business 2024 (bán lẻ)', 'Retail'),
    @('HomeBusiness2021Retail', 'Office Home & Business 2021 (bán lẻ)', 'Retail'),
    @('O365BusinessRetail',     'Microsoft 365 Apps for business',       'M365'),
    @('O365ProPlusRetail',      'Microsoft 365 Apps for enterprise',     'M365'),
    @('ProPlus2024Volume',      'Office LTSC Professional Plus 2024 (Volume)', 'Volume'),
    @('Standard2024Volume',     'Office LTSC Standard 2024 (Volume)',    'Volume'),
    @('ProPlus2021Volume',      'Office LTSC Professional Plus 2021 (Volume)', 'Volume')
)
$t5.Controls.Add((New-Label 'Sản phẩm' 20 16 120 24))
$cbProduct = New-Object System.Windows.Forms.ComboBox
$cbProduct.DropDownStyle = 'DropDownList'; $cbProduct.Font = $fBase
$cbProduct.Location = New-Object System.Drawing.Point(150, 12); $cbProduct.Size = New-Object System.Drawing.Size(470, 28)
foreach ($pr in $offProducts) { [void]$cbProduct.Items.Add($pr[1]) }
$cbProduct.SelectedIndex = 0
$t5.Controls.Add($cbProduct)

$lblOffNote = New-Label '' 150 44 470 40
$lblOffNote.ForeColor = $cMuted
$t5.Controls.Add($lblOffNote)

$t5.Controls.Add((New-Label 'Ngôn ngữ' 20 92 120 24))
$clLang = New-Object System.Windows.Forms.CheckedListBox
$clLang.Location = New-Object System.Drawing.Point(150, 90); $clLang.Size = New-Object System.Drawing.Size(200, 96)
$clLang.CheckOnClick = $true; $clLang.Font = $fBase
foreach ($l in 'vi-vn', 'en-us', 'zh-cn', 'ko-kr', 'ja-jp') { [void]$clLang.Items.Add($l) }
$clLang.SetItemChecked(0, $true); $clLang.SetItemChecked(1, $true)
$t5.Controls.Add($clLang)

$t5.Controls.Add((New-Label 'Kiến trúc' 380 92 80 24))
$rb64 = New-Object System.Windows.Forms.RadioButton
$rb64.Text = '64-bit (khuyên dùng)'; $rb64.Location = New-Object System.Drawing.Point(460, 90); $rb64.Size = New-Object System.Drawing.Size(170, 26); $rb64.Checked = $true
$rb32 = New-Object System.Windows.Forms.RadioButton
$rb32.Text = '32-bit'; $rb32.Location = New-Object System.Drawing.Point(460, 118); $rb32.Size = New-Object System.Drawing.Size(170, 26)
$t5.Controls.Add($rb64); $t5.Controls.Add($rb32)

$t5.Controls.Add((New-Label 'Không cài' 20 200 120 24))
$clExcl = New-Object System.Windows.Forms.CheckedListBox
$clExcl.Location = New-Object System.Drawing.Point(150, 198); $clExcl.Size = New-Object System.Drawing.Size(470, 78)
$clExcl.CheckOnClick = $true; $clExcl.MultiColumn = $true; $clExcl.ColumnWidth = 150; $clExcl.Font = $fBase
$exclItems = @('Teams', 'OneDrive', 'Lync', 'Groove', 'Bing', 'Outlook', 'OneNote', 'Access', 'Publisher')
foreach ($a in $exclItems) { [void]$clExcl.Items.Add($a) }
for ($i = 0; $i -lt 5; $i++) { $clExcl.SetItemChecked($i, $true) }   # mặc định bỏ Teams, OneDrive, Lync (Skype), Groove, Bing
$t5.Controls.Add($clExcl)

$t5.Controls.Add((New-Label 'Key (tuỳ chọn)' 20 292 120 24))
$tbOffKey = New-TextBox 150 288 300
$t5.Controls.Add($tbOffKey)
$chkMsi = New-Object System.Windows.Forms.CheckBox
$chkMsi.Text = 'Gỡ Office cũ dạng MSI (2010 / 2013 / 2016) trước khi cài'
$chkMsi.Location = New-Object System.Drawing.Point(150, 322); $chkMsi.Size = New-Object System.Drawing.Size(470, 26)
$t5.Controls.Add($chkMsi)

$lblKho = New-Label '' 650 284 190 64
$t5.Controls.Add($lblKho)

function Get-OffSel {
    $pr = $offProducts[$cbProduct.SelectedIndex]
    $langs = @($clLang.CheckedItems | ForEach-Object { [string]$_ })
    $excl  = @($clExcl.CheckedItems | ForEach-Object { [string]$_ })
    $arch  = if ($rb32.Checked) { '32' } else { '64' }
    $dir   = Join-Path $KhoOffice ("{0}_x{1}_{2}" -f $pr[0], $arch, ($langs -join '_'))
    return @{ Id = $pr[0]; Name = $pr[1]; Kind = $pr[2]; Langs = $langs; Excl = $excl; Arch = $arch; Kho = $dir }
}

function Update-OffInfo {
    $sel = Get-OffSel
    switch ($sel.Kind) {
        'Retail' { $lblOffNote.Text = 'Bản lẻ: nhập key đã mua (hoặc nhập sau trong Word). Kênh cập nhật Current.' }
        'M365'   { $lblOffNote.Text = 'Microsoft 365: không cần key, kích hoạt bằng cách đăng nhập tài khoản có bản quyền M365.' }
        'Volume' { $lblOffNote.Text = 'Bản Volume (LTSC): cần key Volume (MAK) / KMS của tổ chức. Không có thì cài xong sẽ chưa kích hoạt.' }
    }
    if ($sel.Langs.Count -eq 0) { $lblKho.Text = 'Chọn ít nhất 1 ngôn ngữ'; $lblKho.ForeColor = $cDanger; return }
    if (Test-Path (Join-Path $sel.Kho 'Office')) {
        $lblKho.Text = "Kho: ĐÃ CÓ`n$([IO.Path]::GetFileName($sel.Kho))"; $lblKho.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
    } else {
        $lblKho.Text = "Kho: chưa có`n(bấm Tải về kho)"; $lblKho.ForeColor = $cMuted
    }
}
$cbProduct.Add_SelectedIndexChanged({ Update-OffInfo })
$rb64.Add_CheckedChanged({ Update-OffInfo })
$clLang.Add_ItemCheck({ $form.BeginInvoke([Action]{ Update-OffInfo }) | Out-Null })   # ItemCheck báo trước khi đổi -> cập nhật sau

$script:officeRun = $null
$script:officeLog = $null
$officeTimer = New-Object System.Windows.Forms.Timer
$officeTimer.Interval = 750

function Finish-ODT([Nullable[int]]$exitCode) {
    $officeTimer.Stop()
    $run = $script:officeRun
    $script:officeRun = $null
    $run.Process.Dispose()
    $script:officeLog = $run.Log
    if ($exitCode -ne 0 -and (Get-Item -LiteralPath $run.ErrorLog -ErrorAction SilentlyContinue).Length -gt 0) {
        $script:officeLog = $run.ErrorLog
    }
    $bOfficeLog.Enabled = Test-Path -LiteralPath $script:officeLog -PathType Leaf
    $officeBar.MarqueeAnimationSpeed = 0
    $officeBar.Style = 'Continuous'
    $officeBar.Value = 0
    if ($exitCode -eq 0) {
        $officeBar.Value = 100
        $lblOfficeProgress.Text = if ($run.Mode -eq 'Download') { 'Đã tải bộ cài về kho.' } elseif ($run.Mode -eq 'Cleanup') { 'Đã kết thúc công cụ gỡ / dọn. Xem nhật ký để biết kết quả.' } else { 'Đã cài Office.' }
        $lblOfficeProgress.ForeColor = $cPrimary
    } else {
        $lblOfficeProgress.Text = if ($null -eq $exitCode) {
            'Không xác nhận được kết quả. Mở nhật ký để xem chi tiết.'
        } else {
            "Office báo lỗi (mã $exitCode). Mở nhật ký để xem chi tiết."
        }
        $lblOfficeProgress.ForeColor = $cDanger
    }
    Set-Status $lblOfficeProgress.Text
    $bDl.Enabled = $true
    $bKho.Enabled = $true
    $bNet.Enabled = $true
    $bCleanup.Enabled = $true
    Update-OffInfo
}

$officeTimer.Add_Tick({
    $run = $script:officeRun
    if ($null -eq $run) { return }
    if ($run.Process.HasExited) {
        $run.Process.WaitForExit()
        Finish-ODT $run.Process.ExitCode
        return
    }
    try {
        $line = [IO.File]::ReadAllText($run.Progress).Trim()
        if ($line) { $run.Stage = $line }
    } catch [IO.IOException] {}
    $elapsed = (Get-Date) - $run.Started
    $lblOfficeProgress.Text = '{0}  ·  {1:hh\:mm\:ss}' -f $run.Stage, $elapsed
})

function Start-ODT([string]$mode) {
    if ($script:officeRun) { return }
    $sel = Get-OffSel
    if ($sel.Langs.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Chọn ít nhất 1 ngôn ngữ.', 'Office') | Out-Null; return }
    $key = $tbOffKey.Text.Trim().ToUpper()
    if ($key -and $key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') {
        [System.Windows.Forms.MessageBox]::Show('Key sai định dạng XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', 'Office', 'OK', 'Warning') | Out-Null; return
    }
    if ($mode -eq 'InstallKho' -and -not (Test-Path (Join-Path $sel.Kho 'Office'))) {
        [System.Windows.Forms.MessageBox]::Show("Chưa có kho cho lựa chọn này:`n$($sel.Kho)`n`nBấm 'Tải về kho' trước.", 'Office', 'OK', 'Warning') | Out-Null; return
    }
    if ($mode -ne 'Download') {
        $msg = "Cài $($sel.Name) ($($sel.Arch)-bit, $($sel.Langs -join ', ')) lên máy này?"
        if ($chkMsi.Checked) { $msg += "`n`nSẽ GỠ Office cũ dạng MSI trước khi cài." }
        if (-not (Confirm-Box $msg 'Cài Office')) { return }
    }
    $excl = if ($sel.Excl.Count) { $sel.Excl -join ',' } else { 'none' }
    $runDir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N'))
    $log = Join-Path $runDir 'Office.log'
    $errorLog = Join-Path $runDir 'Office-errors.log'
    $progress = Join-Path $runDir 'Progress.txt'
    $a = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$(Join-Path $DirOffice 'Office-ODT.ps1')`" -Mode $mode -Product $($sel.Id) -Languages $($sel.Langs -join ',') -Arch $($sel.Arch) -Exclude $excl -KhoRoot `"$KhoOffice`" -ProgressPath `"$progress`""
    if ($key -and $mode -ne 'Download') { $a += " -PidKey $key" }
    if ($chkMsi.Checked -and $mode -ne 'Download') { $a += ' -RemoveMSI' }

    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $process = Start-Process powershell.exe -ArgumentList $a -WorkingDirectory $DirOffice -NoNewWindow `
            -RedirectStandardOutput $log -RedirectStandardError $errorLog -PassThru -ErrorAction Stop
    } catch {
        $officeBar.Style = 'Continuous'
        $officeBar.Value = 0
        $lblOfficeProgress.Text = "Không mở được Office Deployment Tool. $($_.Exception.Message)"
        $lblOfficeProgress.ForeColor = $cDanger
        Set-Status 'Không khởi chạy được Office Deployment Tool.'
        return
    }
    # Giữ handle để Windows PowerShell đọc được mã thoát của tiến trình.
    try { $null = $process.Handle } catch [InvalidOperationException] {}
    $script:officeRun = @{
        Process = $process; Mode = $mode; Log = $log; ErrorLog = $errorLog
        Progress = $progress; Started = Get-Date; Stage = 'Đang chuẩn bị Office Deployment Tool…'
    }
    $bDl.Enabled = $false
    $bKho.Enabled = $false
    $bNet.Enabled = $false
    $bCleanup.Enabled = $false
    $bOfficeLog.Enabled = $false
    $lblOfficeProgress.Text = $script:officeRun.Stage
    $lblOfficeProgress.ForeColor = $cPrimary
    $officeBar.Value = 0
    $officeBar.Style = 'Marquee'
    $officeBar.MarqueeAnimationSpeed = 30
    Set-Status $lblOfficeProgress.Text
    $officeTimer.Start()
}

$bDl = New-Button 'Tải về kho' 650 16 190 44
$bDl.Add_Click({ Start-ODT 'Download' }); $t5.Controls.Add($bDl)
$bKho = New-Button 'Cài từ kho (offline)' 650 72 190 44
$bKho.Add_Click({ Start-ODT 'InstallKho' }); $t5.Controls.Add($bKho)
$bNet = New-Button 'Cài trực tiếp (online)' 650 128 190 44
$bNet.Add_Click({ Start-ODT 'Install' }); $t5.Controls.Add($bNet)
$bOpenKho = New-Button 'Mở thư mục kho' 650 190 190 32 -secondary
$bOpenKho.Add_Click({ if (-not (Test-Path $KhoOffice)) { New-Item -ItemType Directory $KhoOffice | Out-Null }; Start-Process explorer.exe $KhoOffice })
$t5.Controls.Add($bOpenKho)

function Start-OfficeCleanup {
    if ($script:officeRun) { return }
    $runDir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\Cleanup_' + [guid]::NewGuid().ToString('N'))
    $log = Join-Path $runDir 'Cleanup.log'
    $progress = Join-Path $runDir 'Progress.txt'
    $cleanupArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -LogPath "{1}" -ProgressPath "{2}"' -f (Join-Path $DirOffice 'Office-Cleanup.ps1'), $log, $progress
    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $process = Start-Process powershell.exe -ArgumentList $cleanupArgs -WorkingDirectory $DirOffice -PassThru -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Gỡ / dọn Office', 'OK', 'Error') | Out-Null
        return
    }
    try { $null = $process.Handle } catch [InvalidOperationException] {}
    $script:officeRun = @{
        Process = $process; Mode = 'Cleanup'; Log = $log; ErrorLog = (Join-Path $runDir 'unused.log')
        Progress = $progress; Started = Get-Date; Stage = 'Chọn thao tác và xác nhận trong cửa sổ gỡ / dọn Office.'
    }
    $bDl.Enabled = $false; $bKho.Enabled = $false; $bNet.Enabled = $false; $bCleanup.Enabled = $false
    $bOfficeLog.Enabled = $false
    $lblOfficeProgress.Text = $script:officeRun.Stage
    $lblOfficeProgress.ForeColor = $cPrimary
    $officeBar.Value = 0; $officeBar.Style = 'Marquee'; $officeBar.MarqueeAnimationSpeed = 30
    Set-Status $lblOfficeProgress.Text
    $officeTimer.Start()
}
$bCleanup = New-Button 'Gỡ / dọn Office…' 650 232 190 40 -danger $true
$bCleanup.Add_Click({ Start-OfficeCleanup }); $t5.Controls.Add($bCleanup)

$offNote = New-Label 'Bộ cài được tải từ Microsoft và lưu vào kho để cài offline.' 20 352 820 24
$offNote.ForeColor = $cMuted
$t5.Controls.Add($offNote)

$officeBar = New-Object System.Windows.Forms.ProgressBar
$officeBar.Location = New-Object System.Drawing.Point(20, 380)
$officeBar.Size = New-Object System.Drawing.Size(820, 14)
$officeBar.AccessibleName = 'Tiến trình tải và cài Office'
$t5.Controls.Add($officeBar)

$lblOfficeProgress = New-Label 'Sẵn sàng' 20 404 655 24
$t5.Controls.Add($lblOfficeProgress)
$bOfficeLog = New-Button 'Xem nhật ký' 690 400 150 32 -secondary
$bOfficeLog.Enabled = $false
$bOfficeLog.Add_Click({
    if ($script:officeLog -and (Test-Path -LiteralPath $script:officeLog -PathType Leaf)) {
        Start-Process notepad.exe ('"{0}"' -f $script:officeLog)
    }
})
$t5.Controls.Add($bOfficeLog)
Update-OffInfo

function Assert-MicrosoftSignature([string]$path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Không xác minh được chữ ký Microsoft của $([IO.Path]::GetFileName($path)) ($($signature.Status))."
    }
}

$script:mediaDownload = $null
$mediaTimer = New-Object System.Windows.Forms.Timer
$mediaTimer.Interval = 350

function Start-MediaCreationTool([ValidateSet('10', '11')][string]$version) {
    if ($script:mediaDownload) { return }

    $link = if ($version -eq '11') { 'https://go.microsoft.com/fwlink/?linkid=2156295' }
            else { 'https://go.microsoft.com/fwlink/?LinkId=2265055' }
    $name = 'TechMaster-MediaCreationTool-{0}-{1}.exe' -f $version, [guid]::NewGuid().ToString('N')
    $file = Join-Path ([IO.Path]::GetTempPath()) $name
    $client = New-Object System.Net.WebClient
    try {
        $task = $client.DownloadFileTaskAsync([uri]$link, $file)
        $script:mediaDownload = @{ Client = $client; Task = $task; File = $file; Version = $version }
        $btnUsb11.Enabled = $false
        $btnUsb10.Enabled = $false
        Set-Status "Đang tải Media Creation Tool cho Windows $version…"
        $mediaTimer.Start()
    } catch {
        $client.Dispose()
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
        Set-Status "Không tải được Media Creation Tool. $($_.Exception.Message)"
    }
}

function Complete-MediaCreationTool($download) {
    $download.Task.GetAwaiter().GetResult()
    Assert-MicrosoftSignature $download.File
    Start-Process -FilePath $download.File -WorkingDirectory ([IO.Path]::GetDirectoryName($download.File)) -ErrorAction Stop
}

$mediaTimer.Add_Tick({
    $download = $script:mediaDownload
    if (-not $download -or -not $download.Task.IsCompleted) { return }
    $mediaTimer.Stop()
    try {
        Complete-MediaCreationTool $download
        Set-Status "Đã mở Media Creation Tool cho Windows $($download.Version). Chọn USB trong công cụ Microsoft."
    } catch {
        Remove-Item -LiteralPath $download.File -ErrorAction SilentlyContinue
        Set-Status "Không mở được Media Creation Tool. $($_.Exception.GetBaseException().Message)"
    } finally {
        $download.Client.Dispose()
        $script:mediaDownload = $null
        $btnUsb11.Enabled = $true
        $btnUsb10.Enabled = $true
    }
})

function Open-WindowsOldCleanup {
    $oldInstall = Join-Path ($env:SystemDrive + '\') 'Windows.old'
    if (-not (Test-Path -LiteralPath $oldInstall -PathType Container)) {
        Set-Status 'Không tìm thấy Windows.old trên ổ cài Windows.'
        return
    }
    try {
        Start-Process 'ms-settings:storagesense' -ErrorAction Stop
        Set-Status 'Chọn Tệp tạm thời → Bản cài đặt Windows trước đây → Xóa tệp.'
    } catch {
        Set-Status 'Mở Cài đặt → Hệ thống → Lưu trữ → Tệp tạm thời để dọn Windows.old.'
    }
}

function Start-WindowsSetup([string]$isoPath) {
    $mountedHere = $false
    try {
        $disk = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop
        if (-not $disk.Attached) {
            $disk = Mount-DiskImage -ImagePath $isoPath -StorageType ISO -PassThru -ErrorAction Stop
            $mountedHere = $true
        }
        $volume = Get-Volume -DiskImage $disk -ErrorAction Stop |
            Where-Object DriveLetter | Select-Object -First 1
        if (-not $volume) { throw 'Windows chưa gán ký tự ổ cho ISO. Hãy gắn ISO trong File Explorer rồi thử lại.' }
        $drive = '{0}:\' -f $volume.DriveLetter
        $setup = Join-Path $drive 'setup.exe'
        if (-not (Test-Path -LiteralPath $setup -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $drive 'sources\boot.wim') -PathType Leaf)) {
            throw 'ISO không có bộ cài Windows hoàn chỉnh.'
        }

        Assert-MicrosoftSignature $setup
        Start-Process -FilePath $setup -WorkingDirectory $drive -ErrorAction Stop
    } catch {
        if ($mountedHere) {
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
}

$t6 = New-Tab 'Cài Windows'
$win11 = New-Card $t6 24 'Windows 11' 'Cắm USB trống từ 8 GB. Công cụ Microsoft sẽ xóa dữ liệu trên USB được chọn.' 400
$btnIso11 = New-Button 'Trang tải Microsoft' 426 22 190 44 -secondary
$btnIso11.Add_Click({ Start-Process 'https://www.microsoft.com/vi-vn/software-download/windows11' })
$win11.Controls.Add($btnIso11)
$btnUsb11 = New-Button 'Tạo USB Windows 11' 628 22 190 44
$btnUsb11.Add_Click({ Start-MediaCreationTool '11' })
$win11.Controls.Add($btnUsb11)

$win10 = New-Card $t6 120 'Windows 10' 'Chọn Tạo phương tiện cài đặt cho PC khác trong công cụ Microsoft, sau đó chọn USB.' 400
$btnIso10 = New-Button 'Trang tải Microsoft' 426 22 190 44 -secondary
$btnIso10.Add_Click({ Start-Process 'https://www.microsoft.com/vi-vn/software-download/windows10' })
$win10.Controls.Add($btnIso10)
$btnUsb10 = New-Button 'Tạo USB Windows 10' 628 22 190 44
$btnUsb10.Add_Click({ Start-MediaCreationTool '10' })
$win10.Controls.Add($btnUsb10)

Add-Card $t6 216 'Mở Windows Setup từ ISO' `
    'Chọn ISO đã tải để nâng cấp hoặc cài lại ngay trong Windows. Chọn mục giữ dữ liệu và ứng dụng trong Windows Setup nếu bộ cài hỗ trợ.' `
    'Chọn ISO…' {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $dialog.Title = 'Chọn bộ cài Windows'
            $dialog.Filter = 'Windows ISO (*.iso)|*.iso'
            if ($dialog.ShowDialog($form) -ne 'OK') { return }
            $path = $dialog.FileName
        } finally {
            $dialog.Dispose()
        }
        $form.UseWaitCursor = $true
        Set-Status 'Đang gắn ISO và kiểm tra bộ cài Windows…'
        $status.Refresh()
        try {
            Start-WindowsSetup $path
            Set-Status 'Đã mở Windows Setup. Tiếp tục trong cửa sổ cài đặt.'
        } catch {
            Set-Status 'Không mở được Windows Setup.'
            [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Cài Windows', 'OK', 'Error')
        } finally {
            $form.UseWaitCursor = $false
        }
    }
Add-Card $t6 312 'Dọn Windows.old sau khi cài' `
    'Sau khi cài trực tiếp, mở Tệp tạm thời trong Cài đặt Windows để xóa bản cài trước. Xóa xong sẽ mất tùy chọn quay lại bản Windows cũ.' `
    'Dọn Windows.old' { Open-WindowsOldCleanup }

. (Join-Path $PSScriptRoot 'BasicApps.ps1')
. (Join-Path $PSScriptRoot 'Update-UI.ps1')

# Thanh trạng thái
$script:status = New-Object System.Windows.Forms.Label
$status.Dock = [System.Windows.Forms.DockStyle]::Bottom
$status.Height = 30
$status.TextAlign = 'MiddleLeft'; $status.BackColor = [System.Drawing.Color]::FromArgb(220, 231, 244)
$status.Text = '  Sẵn sàng'
$form.Controls.Add($status)

# Co giãn cửa sổ và các control cùng lúc sau khi đã dựng đủ giao diện.
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.ResumeLayout($true)

$form.Add_Shown({ Update-LogoPreview; Update-MachineInfo; $form.Activate() })
[void]$form.ShowDialog()
$officeTimer.Dispose()
$basicAppTimer.Dispose()
if ($script:basicAppRun.Process) { $script:basicAppRun.Process.Dispose() }
$mediaTimer.Dispose()
$updateTimer.Dispose()
if ($script:updateProcess) { $script:updateProcess.Dispose() }
if ($script:mediaDownload) {
    $script:mediaDownload.Client.CancelAsync()
    $script:mediaDownload.Client.Dispose()
    Remove-Item -LiteralPath $script:mediaDownload.File -ErrorAction SilentlyContinue
}
if ($script:officeRun) { $script:officeRun.Process.Dispose() }
