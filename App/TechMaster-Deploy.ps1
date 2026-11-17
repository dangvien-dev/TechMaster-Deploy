# WPF entry point. Use Windows PowerShell 5.1, STA, through the launcher.
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$DirClone = Join-Path $Root 'FixClone'; $DirKH = Join-Path $Root 'KichHoat'
$DirBB = Join-Path $Root 'BienBan'; $DirOffice = Join-Path $Root 'Office'; $KhoOffice = Join-Path $Root 'KhoOffice'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
$form = Import-DeployWindow (Join-Path $PSScriptRoot 'MainWindow.xml')
$form.Width = [Math]::Max($form.MinWidth, [Math]::Min($form.Width, [Windows.SystemParameters]::WorkArea.Width - 30))
$form.Height = [Math]::Max($form.MinHeight, [Math]::Min($form.Height, [Windows.SystemParameters]::WorkArea.Height - 30))
[xml]$markup = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MainWindow.xml'))
$ns = New-Object Xml.XmlNamespaceManager($markup.NameTable); $ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
foreach ($node in $markup.SelectNodes('//*[@x:Name]', $ns)) {
    $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $control = $form.FindName($name)
    if ($control) { Set-Variable -Name $name -Value $control -Scope Script }
}
$form.Icon = New-Object Windows.Media.Imaging.BitmapImage([uri](Join-Path $PSScriptRoot 'TechMaster.ico'))
$lblTitle.Text = 'TechMaster Deploy v' + ([IO.File]::ReadAllText((Join-Path $Root 'version.txt'))).Trim()
$cPrimary = '#10223F'; $cMuted = '#526880'; $cDanger = '#B91C1C'
$script:officeRun = $null; $script:mediaDownload = $null; $script:uiWork = $null
$script:officeLog = $null; $script:updateClosing = $false
function Set-Status([string]$message) { $status.Text = $message }
function Bind-Click([string]$name, [scriptblock]$handler) { $form.FindName($name).Add_Click($handler) }
function Open-DeployFolder([string]$path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Start-Process explorer.exe ('"{0}"' -f $path)
}
. (Join-Path $PSScriptRoot 'Deploy.Actions.ps1')
function Start-UiWork([string]$code, [object[]]$arguments, [scriptblock]$completed) {
    if ($script:uiWork) { Set-Status 'Chờ thao tác hiện tại hoàn tất.'; return }
    try {
        $script:uiWork = Start-DeployWork $code $arguments
        $script:uiWork.Complete = $completed
        $btnRefresh.IsEnabled = $false; $btnExport.IsEnabled = $false
        $uiTimer.Start()
    } catch { Show-DeployMessage $_.Exception.Message 'TechMaster Deploy' 'Error' }
}
$uiTimer = New-DeployTimer 200 {
    $job = $script:uiWork
    if (-not $job -or -not $job.Async.IsCompleted) { return }
    $uiTimer.Stop(); $script:uiWork = $null
    try { $result = @(Receive-DeployWork $job); & $job.Complete $result }
    catch { Set-Status 'Thao tác chưa hoàn tất.'; Show-DeployMessage $_.Exception.GetBaseException().Message 'TechMaster Deploy' 'Error' }
    finally { $btnRefresh.IsEnabled = $true; $btnExport.IsEnabled = $true }
}
function Update-MachineInfo {
    Set-Status 'Đang đọc thông tin bản quyền…'
    Start-UiWork @'
param($computer)
$ErrorActionPreference = 'Stop'
function Status($id, $missing) {
    $items = @(Get-CimInstance SoftwareLicensingProduct -Filter ("ApplicationID='$id' AND PartialProductKey IS NOT NULL") -ErrorAction Stop)
    if (-not $items.Count) { return $missing }
    if ($items | Where-Object LicenseStatus -ne 1) { return 'CHƯA kích hoạt' }
    return 'Đã kích hoạt'
}
[pscustomobject]@{ Text = "Máy: $computer    Windows: $(Status '55c92734-d682-4d71-983e-d6ec3f16059f' 'không đọc được')    Office: $(Status '0ff1ce15-a989-479d-af46-f275c6370663' 'không phát hiện')" }
'@ @($env:COMPUTERNAME) { param($result) $lblInfo.Text = $result[-1].Text; Set-Status 'Đã làm mới thông tin máy.' }
}
$Navigation.Add_SelectionChanged({ $tabs.SelectedIndex = $Navigation.SelectedIndex })
$tabs.SelectedIndex = 0
Bind-Click 'btnRefresh' { Update-MachineInfo }
Bind-Click 'headerUpdate' { $Navigation.SelectedIndex = 7 }
Bind-Click 'btnSysprepCheck' { Start-Tool (Join-Path $DirClone 'Fix-SysprepErrors.bat') 'Kiểm tra lỗi Sysprep' }
Bind-Click 'btnSysprep' { if (Confirm-Box "Chuẩn bị máy gốc và chạy Sysprep?`nCuối quy trình máy sẽ tự tắt; clone ổ trước khi bật lại." 'Sysprep') { Start-Tool (Join-Path $DirClone 'Run-Sysprep.bat') 'Chuẩn bị + Sysprep' } }
Bind-Click 'btnReinstall' { Open-DeployFolder (Join-Path $DirClone 'Reinstall') }
Bind-Click 'btnCloneHelp' { Start-Process notepad.exe ('"{0}"' -f (Join-Path $DirClone 'README.md')) }
Bind-Click 'btnCloneFix' { Start-Tool (Join-Path $DirClone 'Fix-CloneDuplicate.bat') 'Xử lý trùng lặp' }
Bind-Click 'btnFormat' { Start-Tool (Join-Path $DirClone 'Fix-DinhDang.bat') 'Chỉnh dấu số' }
Bind-Click 'btnKeyboard' { Start-Tool (Join-Path $DirClone 'Fix-BanPhim.bat') 'Bàn phím / EVKey' }
Bind-Click 'btnUltraDiagnostic' {
    Set-Status 'Đang đọc cấu hình UltraViewer và card mạng…'
    Start-UiWork 'param($diagnostics) . $diagnostics; Format-UltraViewerDiagnostic (Get-UltraViewerDiagnostic)' @((Join-Path $DirClone 'UltraViewer.Diagnostics.ps1')) {
        param($result)
        $script:diagnosticWindow = Import-DeployWindow (Join-Path $PSScriptRoot 'DiagnosticsWindow.xml')
        $script:diagnosticWindow.Owner = $form
        $script:diagnosticWindow.FindName('Details').Text = [string]$result[-1]
        $script:diagnosticWindow.FindName('Copy').Add_Click({ [Windows.Clipboard]::SetText($script:diagnosticWindow.FindName('Details').Text) })
        $script:diagnosticWindow.FindName('Close').Add_Click({ $script:diagnosticWindow.Close() })
        [void]$script:diagnosticWindow.ShowDialog()
        Set-Status 'Đã chẩn đoán UltraViewer; so sánh kết quả của hai máy bị trùng ID.'
    }
}
Bind-Click 'btnDesktopPreflight' {
    $script = Join-Path $DirClone 'Master-Preflight.ps1'
    $command = "& '{0}' -AfterClone" -f $script.Replace("'", "''")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $script:desktopProcess = Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -WindowStyle Hidden -PassThru
}
Bind-Click 'btnActivateWindows' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Windows.bat') 'Kích hoạt Windows' }
Bind-Click 'btnActivateOffice' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Office.bat') 'Kích hoạt Office' }
Bind-Click 'btnActivationTest' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-TEST.bat') 'TEST kích hoạt' }
Bind-Click 'btnPortalWindows' { Start-Process 'https://aka.ms/WindowsActivate' }
Bind-Click 'btnPortalOffice' { Start-Process 'https://visualsupport.microsoft.com/' }
$cfgFile = Join-Path $DirBB 'BienBan-Config.json'
if (Test-Path -LiteralPath $cfgFile) {
    try { $cfg = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in 'Company','Address','Phone','Technician') { $form.FindName($name).Text = [string]$cfg.$name }
    } catch { Set-Status 'Chưa đọc được cấu hình biên bản đã lưu.' }
}
function Update-LogoPreview {
    $logoBox.Source = $null; $logoWeb.Visibility = 'Collapsed'; $logoBox.Visibility = 'Visible'
    $file = Get-ChildItem -LiteralPath $DirBB -File | Where-Object { $_.BaseName -eq 'Logo' -and $_.Extension -in '.svg','.png','.jpg','.jpeg' } | Select-Object -First 1
    if (-not $file) { $lblLogo.Text = 'Chưa có logo'; return }
    $lblLogo.Text = $file.Name
    try {
        if ($file.Extension -eq '.svg') {
            $data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
            $logoWeb.Visibility = 'Visible'; $logoBox.Visibility = 'Collapsed'
            $logoWeb.NavigateToString('<!doctype html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge"></head><body style="margin:0;text-align:center"><img style="max-width:100%;max-height:140px" src="data:image/svg+xml;base64,' + $data + '"></body></html>')
        } else {
            $stream = New-Object IO.MemoryStream(,([IO.File]::ReadAllBytes($file.FullName)))
            try {
                $image = New-Object Windows.Media.Imaging.BitmapImage
                $image.BeginInit(); $image.CacheOption = 'OnLoad'; $image.StreamSource = $stream; $image.EndInit(); $image.Freeze()
                $logoBox.Source = $image
            } finally { $stream.Dispose() }
        }
    } catch { $lblLogo.Text = $file.Name + ' (không xem trước được)' }
}
Bind-Click 'btnLogo' {
    $path = Select-DeployFile 'Chọn logo đơn vị' 'Logo (*.svg;*.png;*.jpg;*.jpeg)|*.svg;*.png;*.jpg;*.jpeg'
    if (-not $path) { return }
    $destination = Join-Path $DirBB ('Logo' + [IO.Path]::GetExtension($path).ToLowerInvariant())
    if ([IO.Path]::GetFullPath($path) -ne [IO.Path]::GetFullPath($destination)) {
        Copy-Item -LiteralPath $path -Destination $destination -Force
        Get-ChildItem -LiteralPath $DirBB -File | Where-Object { $_.BaseName -eq 'Logo' -and $_.FullName -ne $destination } | Remove-Item -Force
    }
    Update-LogoPreview; Set-Status 'Đã lưu logo.'
}
Bind-Click 'btnExport' {
    $cfg = [pscustomobject]@{ Company = $Company.Text.Trim(); Address = $Address.Text.Trim(); Phone = $Phone.Text.Trim(); Technician = $Technician.Text.Trim() }
    try { $cfg | ConvertTo-Json | Set-Content -LiteralPath $cfgFile -Encoding UTF8 }
    catch { Show-DeployMessage $_.Exception.Message 'Lưu biên bản' 'Error'; return }
    Set-Status 'Đang đọc bản quyền và xuất biên bản…'
    Start-UiWork @'
param($script, $customer, $invoice, $technician)
$ErrorActionPreference = 'Stop'
& $script -NoPrompt -Customer $customer -Invoice $invoice -Technician $technician 6>$null
'@ @((Join-Path $DirBB 'Bien-Ban-Ban-Quyen.ps1'), $tbCustomer.Text.Trim(), $tbInvoice.Text.Trim(), $cfg.Technician) {
        param($result)
        $files = @($result | Where-Object { $_ -is [string] -and $_ -like '*.html' })
        if ($files.Count) { Set-Status ('Đã xuất: ' + $files[-1]) } else { Set-Status 'Đã xuất biên bản; xem thư mục biên bản.' }
    }
}
Bind-Click 'btnOpenBB' { Open-DeployFolder (Join-Path $DirBB 'BienBan') }
foreach ($product in $offProducts) { [void]$cbProduct.Items.Add($product[1]) }
$cbProduct.SelectedIndex = 0
$languageChoices = @(); $excludeChoices = @()
foreach ($language in 'vi-vn','en-us','zh-cn','ko-kr','ja-jp') {
    $box = New-Object Windows.Controls.CheckBox
    $box.Content = $language; $box.Tag = $language; $box.IsChecked = $language -in 'vi-vn','en-us'
    $languageChoices += $box; [void]$clLang.Children.Add($box)
    $box.Add_Click({ Update-OffInfo })
}
foreach ($name in 'Teams','OneDrive','Lync','Groove','Bing','Outlook','OneNote','Access','Publisher') {
    $box = New-Object Windows.Controls.CheckBox
    $box.Content = $name; $box.Tag = $name; $box.IsChecked = $name -in 'Teams','OneDrive','Lync','Groove','Bing'
    $excludeChoices += $box; [void]$clExcl.Children.Add($box)
}
$cbProduct.Add_SelectionChanged({ Update-OffInfo }); $rb64.Add_Click({ Update-OffInfo }); $rb32.Add_Click({ Update-OffInfo })
$officeTimer = New-DeployTimer 500 {
    $run = $script:officeRun
    if (-not $run) { return }
    if ($run.Process.HasExited) { $run.Process.WaitForExit(); Finish-ODT $run.Process.ExitCode; return }
    try { $line = [IO.File]::ReadAllText($run.Progress).Trim(); if ($line) { $run.Stage = $line } } catch [IO.IOException] {}
    $lblOfficeProgress.Text = '{0} · {1:hh\:mm\:ss}' -f $run.Stage, ((Get-Date) - $run.Started)
}
Bind-Click 'bDl' { Start-ODT 'Download' }; Bind-Click 'bKho' { Start-ODT 'InstallKho' }; Bind-Click 'bNet' { Start-ODT 'Install' }
Bind-Click 'bCleanup' { Start-OfficeCleanup }; Bind-Click 'bOpenKho' { Open-DeployFolder $KhoOffice }
$bOfficeLog.IsEnabled = $false
Bind-Click 'bOfficeLog' { if ($script:officeLog) { Start-Process notepad.exe ('"{0}"' -f $script:officeLog) } }
Update-OffInfo
$mediaTimer = New-DeployTimer 350 {
    $download = $script:mediaDownload
    if (-not $download -or -not $download.Task.IsCompleted) { return }
    $mediaTimer.Stop()
    try { Complete-MediaCreationTool $download; Set-Status ('Đã mở Media Creation Tool cho Windows ' + $download.Version) }
    catch { Set-Status ('Không mở được công cụ: ' + $_.Exception.GetBaseException().Message); Remove-Item -LiteralPath $download.File -ErrorAction SilentlyContinue }
    finally { $download.Client.Dispose(); $script:mediaDownload = $null; $btnUsb11.IsEnabled = $true; $btnUsb10.IsEnabled = $true }
}
Bind-Click 'btnIso11' { Start-Process 'https://www.microsoft.com/vi-vn/software-download/windows11' }
Bind-Click 'btnIso10' { Start-Process 'https://www.microsoft.com/vi-vn/software-download/windows10' }
Bind-Click 'btnUsb11' { Start-MediaCreationTool '11' }; Bind-Click 'btnUsb10' { Start-MediaCreationTool '10' }
Bind-Click 'btnWindowsOld' { Open-WindowsOldCleanup }
Bind-Click 'btnWindowsIso' {
    $path = Select-DeployFile 'Chọn ISO Windows' 'Windows ISO (*.iso)|*.iso'
    if (-not $path) { return }
    Set-Status 'Đang gắn ISO và kiểm tra chữ ký Microsoft…'
    Start-UiWork 'param($actions, $iso) $ErrorActionPreference = "Stop"; . $actions; Start-WindowsSetup $iso' @((Join-Path $PSScriptRoot 'Deploy.Actions.ps1'), $path) { Set-Status 'Đã mở Windows Setup.' }
}
. (Join-Path $PSScriptRoot 'BasicApps.ps1')
$basicAppChoices = @()
foreach ($app in $basicApps) {
    $box = New-Object Windows.Controls.CheckBox
    $box.Content = $app.Name; $box.ToolTip = $app.Description; $box.Tag = $app; $box.MinWidth = 205
    $basicAppChoices += $box; [void]$lbBasicApps.Children.Add($box)
}
$btnBasicAppLog.IsEnabled = $false
Bind-Click 'btnBasicAppInstall' { Start-BasicApps }
Bind-Click 'btnBasicAppLog' { Start-Process notepad.exe ('"{0}"' -f $script:basicAppLog) }
Bind-Click 'btnBasicAppHelp' { Start-Process 'https://learn.microsoft.com/vi-vn/windows/package-manager/winget/' }
. (Join-Path $PSScriptRoot 'Update-UI.ps1')
$form.Add_Closing({
    param($sender, $event)
    if ($script:updateClosing) { return }
    if ($script:uiWork -or $script:officeRun -or $script:basicAppRun -or $script:mediaDownload -or $script:updateProcess) {
        $event.Cancel = $true
        Set-Status 'Chờ thao tác đang chạy hoàn tất hoặc đóng cửa sổ cập nhật trước khi thoát.'
    }
})
$form.Add_ContentRendered({ Update-LogoPreview; Update-MachineInfo })
if ($ValidateOnly) { return $form }
try { [void]$form.ShowDialog() }
finally {
    foreach ($timer in $uiTimer,$officeTimer,$basicAppTimer,$mediaTimer,$updateTimer) { $timer.Stop() }
    if ($script:updateProcess) { $script:updateProcess.Dispose() }
}
