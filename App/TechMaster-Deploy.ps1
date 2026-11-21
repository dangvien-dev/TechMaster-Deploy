# WPF entry point. Use Windows PowerShell 5.1, STA, through the launcher.
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
trap {
    if ($ValidateOnly) { throw $_ }
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($_.Exception.GetBaseException().Message, 'TechMaster Deploy', 'OK', 'Error')
    exit 1
}
$Root = Split-Path -Parent $PSScriptRoot
$DirClone = Join-Path $Root 'FixClone'; $DirKH = Join-Path $Root 'KichHoat'
$DirBB = Join-Path $Root 'BienBan'; $DirOffice = Join-Path $Root 'Office'; $KhoOffice = Join-Path $Root 'KhoOffice'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Info.UI.ps1')
. (Join-Path $PSScriptRoot 'CustomApps.UI.ps1')
. (Join-Path $PSScriptRoot 'Report.Identity.ps1')
. (Join-Path $PSScriptRoot 'Logo.Preview.ps1')
. (Join-Path $PSScriptRoot 'LicenseConfirmation.UI.ps1')
. (Join-Path $PSScriptRoot 'Startup.UI.ps1')
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
        $btnRefresh.IsEnabled = $false; $btnExport.IsEnabled = $false; $btnConfirmRetail.IsEnabled=$false; $btnConfirmCompany.IsEnabled=$false
        $uiTimer.Start()
    } catch { Show-DeployMessage $_.Exception.Message 'TechMaster Deploy' 'Error' }
}
$uiTimer = New-DeployTimer 200 {
    $job = $script:uiWork
    if (-not $job -or -not $job.Async.IsCompleted) { return }
    $uiTimer.Stop(); $script:uiWork = $null
    try { $result = @(Receive-DeployWork $job); & $job.Complete $result }
    catch { Set-Status 'Thao tác chưa hoàn tất.'; Show-DeployMessage $_.Exception.GetBaseException().Message 'TechMaster Deploy' 'Error' }
    finally { $btnRefresh.IsEnabled = $true; $btnExport.IsEnabled = $true; $btnConfirmRetail.IsEnabled=$true; $btnConfirmCompany.IsEnabled=$true }
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
Bind-Click 'btnRefresh' { Update-MachineInfo; Request-DeployUpdateNotification }
Bind-Click 'btnQuickGuide' { Show-DeployQuickGuide $Root $form }
Bind-Click 'btnContact' { Show-DeployQuickGuide $Root $form -Section 'Liên hệ / góp ý' }
Bind-Click 'headerUpdate' { if($script:updateProcess){Show-DeployUpdater}else{$Navigation.SelectedIndex = 7} }
Bind-Click 'btnSysprepCheck' { Start-Tool (Join-Path $DirClone 'Fix-SysprepErrors.bat') 'Kiểm tra lỗi Sysprep' }
Bind-Click 'btnSysprep' { if (Confirm-Box "Chuẩn bị máy gốc và chạy Sysprep?`nCuối quy trình máy sẽ tự tắt; clone ổ trước khi bật lại." 'Sysprep') { Start-Tool (Join-Path $DirClone 'Run-Sysprep.bat') 'Chuẩn bị + Sysprep' } }
Bind-Click 'btnReinstall' { Open-DeployFolder (Join-Path $DirClone 'Reinstall') }
Bind-Click 'btnCloneHelp' { Show-DeployQuickGuide $Root $form -Section 'Máy gốc / Sysprep' }
Bind-Click 'btnCloneFix' { Start-Tool (Join-Path $DirClone 'Fix-CloneDuplicate.bat') 'Xử lý trùng lặp' }
Bind-Click 'btnFormat' { Start-Tool (Join-Path $DirClone 'Fix-DinhDang.bat') 'Chỉnh ngày / số' }
Bind-Click 'btnKeyboard' { Start-Tool (Join-Path $DirClone 'Fix-BanPhim.bat') 'Bàn phím / EVKey' }
Bind-Click 'btnUltraReset' {
    $script = Join-Path $DirClone 'UltraViewer-Reset.ps1'
    $command = "& '{0}'" -f $script.Replace("'", "''")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $script:desktopProcess = Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -WindowStyle Hidden -PassThru
}
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
Bind-Click 'btnDriverFix' {
    $entry=Join-Path $DirClone 'DriverFix.ps1'
    $command="& '{0}'" -f $entry.Replace("'","''")
    Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))) -WindowStyle Hidden|Out-Null
}
Bind-Click 'btnDriverGuide' { Show-DeployQuickGuide $Root $form -Section 'Fix Driver' }
Bind-Click 'btnActivateWindows' { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Windows.bat') 'Kích hoạt Windows' }
Bind-Click 'btnWindowsSetupKey' {
    $entry=Join-Path $DirClone 'Windows-SetupKey.ps1'
    $command="& '{0}'" -f $entry.Replace("'","''")
    Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))) -WindowStyle Hidden|Out-Null
}
Bind-Click 'btnActivateOffice'  { Start-Tool (Join-Path $DirKH 'Kich-Hoat-Office.bat') 'Kích hoạt Office' }
Bind-Click 'bCleanup' { Start-OfficeCleanup -CleanupMode Keys }
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
    $logoBox.Source = $null
    $file = Get-ChildItem -LiteralPath $DirBB -File | Where-Object { $_.BaseName -eq 'Logo' -and $_.Extension -in '.svg','.png','.jpg','.jpeg' } | Select-Object -First 1
    $btnRemoveLogo.IsEnabled = [bool]$file
    if (-not $file) { $lblLogo.Text = 'Chưa có logo'; return }
    $lblLogo.Text = $file.Name
    try { $logoBox.Source = Get-DeployLogoPreview $file.FullName }
    catch { $lblLogo.Text = $file.Name + ' (chưa xem trước được; có thể chọn PNG/JPG). Logo gốc vẫn dùng trong biên bản.' }
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
Bind-Click 'btnRemoveLogo' {
    try {
        Remove-DeployReportLogo $DirBB
        Update-LogoPreview
        Set-Status 'Đã xoá logo. Thông tin đơn vị đã lưu và các biên bản đã xuất được giữ nguyên.'
    } catch { Show-DeployMessage $_.Exception.GetBaseException().Message 'Xoá logo' 'Error' }
}
function Save-ReportInfo {
    Save-DeployReportIdentity -Directory $DirBB -Company $Company.Text -Address $Address.Text -Phone $Phone.Text -Technician $Technician.Text
}
Bind-Click 'btnSaveIdentity' {
    try {
        $null=Save-ReportInfo
        Set-Status 'Đã lưu thông tin đơn vị và kỹ thuật viên. Các trường để trống cũng đã được lưu.'
    } catch { Show-DeployMessage $_.Exception.GetBaseException().Message 'Lưu thông tin biên bản' 'Error' }
}
Bind-Click 'btnResetIdentity' {
    if(-not (Confirm-Box 'Xoá thông tin đơn vị, kỹ thuật viên và logo đang lưu trong bộ công cụ này?' 'Xoá thông tin đơn vị' -ConfirmText 'Xoá thông tin / logo' -Danger -Owner $form)){return}
    Reset-DeployReportIdentity $DirBB
    foreach($name in 'Company','Address','Phone','Technician'){$form.FindName($name).Text=''}
    $tbCustomer.Text=''
    Update-LogoPreview
    Set-Status 'Đã xoá thông tin đơn vị và logo. Có thể nhập thông tin đơn vị mới.'
}
Bind-Click 'btnExport' {
    try { $cfg=Save-ReportInfo }
    catch { Show-DeployMessage $_.Exception.Message 'Lưu biên bản' 'Error'; return }
    Set-Status 'Đang đọc bản quyền và xuất biên bản…'
    Start-UiWork @'
param($script, $customer, $technician)
$ErrorActionPreference = 'Stop'
& $script -NoPrompt -Customer $customer -Technician $technician 6>$null
'@ @((Join-Path $DirBB 'Bien-Ban-Ban-Quyen.ps1'), $tbCustomer.Text.Trim(), $cfg.Technician) {
        param($result)
        $files = @($result | Where-Object { $_ -is [string] -and $_ -like '*.html' })
        if ($files.Count) { Set-Status ('Đã xuất: ' + $files[-1]) } else { Set-Status 'Đã xuất biên bản; xem thư mục biên bản.' }
    }
}
function Start-DeployConfirmation([string]$template) {
    if($script:uiWork){Set-Status 'Chờ thao tác hiện tại hoàn tất.';return}
    if(-not $Company.Text.Trim()){Show-DeployMessage 'Nhập tên đơn vị cung cấp tại phần Thông tin biên bản.' 'Xác nhận bàn giao';return}
    try{$cfg=Save-ReportInfo}catch{Show-DeployMessage $_.Exception.Message 'Lưu thông tin đơn vị' 'Error';return}
    $logo=Get-ChildItem -LiteralPath $DirBB -File|Where-Object {$_.BaseName -eq 'Logo' -and $_.Extension -in '.svg','.png','.jpg','.jpeg'}|Select-Object -First 1
    $cfg|Add-Member NoteProperty LogoPath $(if($logo){$logo.FullName}else{''})
    $script:confirmationRequest=@{Template=$template;Supplier=$cfg;Customer=$tbCustomer.Text.Trim()}
    Set-Status 'Đang đọc thông tin máy và phần mềm bàn giao…'
    Start-UiWork @'
param($core)
. $core
Get-DeployConfirmationSnapshot
'@ @((Join-Path $DirBB 'LicenseConfirmation.Core.ps1')) {
        param($result)
        $request=$script:confirmationRequest
        $dialog=New-DeployLicenseConfirmationWindow -Template $request.Template -Supplier $request.Supplier -CustomerName $request.Customer -Snapshot $result[-1] -OutputDirectory (Join-Path $DirBB 'BienBan') -Owner $form
        [void]$dialog.ShowDialog()
        if($dialog.Tag.Path){Set-Status ('Đã xuất: '+$dialog.Tag.Path)}else{Set-Status 'Đã đóng mẫu xác nhận bàn giao.'}
    }
}
Bind-Click 'btnConfirmRetail' {Start-DeployConfirmation 'Retail'}
Bind-Click 'btnConfirmCompany' {Start-DeployConfirmation 'Company'}
Bind-Click 'btnOpenBB'  { Open-DeployFolder (Join-Path $DirBB 'BienBan') }
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
Bind-Click 'bRemoveOffice' { Start-OfficeCleanup }; Bind-Click 'bOpenKho' { Open-DeployFolder $KhoOffice }
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
function Update-DeployBasicChoices {
    $selected=@($basicAppChoices|Where-Object IsChecked|ForEach-Object {$_.Tag.Id})
    $script:basicAppChoices=@();$lbBasicApps.Children.Clear()
    foreach($app in @(Get-DeployBasicApps)){
        $box=New-Object Windows.Controls.CheckBox
        $box.Content=$app.Name;$box.ToolTip=$app.Description;$box.Tag=$app;$box.MinWidth=205;$box.IsChecked=$app.Id -in $selected
        $script:basicAppChoices+=$box;[void]$lbBasicApps.Children.Add($box)
    }
    if($script:customAppsError){$lblBasicAppStatus.Text='Chưa đọc được danh sách bổ sung. Mở Quản lý ứng dụng để kiểm tra.'}
}
$basicAppChoices=@()
Update-DeployBasicChoices
Bind-Click 'btnManageApps' {
    if(Show-DeployCustomApps $script:customAppsPath $script:builtInBasicApps $form){Update-DeployBasicChoices}
}
$btnBasicAppLog.IsEnabled = $false
Bind-Click 'btnBasicAppInstall' { Start-BasicApps }
Bind-Click 'btnBasicAppLog' { Start-Process notepad.exe ('"{0}"' -f $script:basicAppLog) }
Bind-Click 'btnBasicAppHelp' { Start-Process 'https://learn.microsoft.com/vi-vn/windows/package-manager/winget/' }
. (Join-Path $PSScriptRoot 'Update.Notifications.UI.ps1')
. (Join-Path $PSScriptRoot 'Update-UI.ps1')
$form.Add_Closing({
    param($sender, $event)
    if ($script:updateClosing) { return }
    if ($script:uiWork -or $script:officeRun -or $script:basicAppRun -or $script:mediaDownload) {
        $event.Cancel = $true
        Set-Status 'Chờ thao tác đang chạy hoàn tất trước khi thoát.'
    }
})
$form.Add_ContentRendered({ Update-LogoPreview; Update-MachineInfo; Start-DeployUpdateNotifications })
if (-not $ValidateOnly) {
$form.Dispatcher.Add_UnhandledException({
    param($sender, $event)
    $event.Handled = $true
    Set-Status 'Thao tác gặp lỗi; có thể thử lại.'
    Show-DeployMessage $event.Exception.GetBaseException().Message 'TechMaster Deploy' 'Error'
})
}
if ($ValidateOnly) { return $form }
Wait-DeployUpdaterBeforeShow $Root
try { [void]$form.ShowDialog() }
finally {
    foreach ($timer in $uiTimer,$officeTimer,$basicAppTimer,$mediaTimer,$updateTimer,$availabilityTimer) { $timer.Stop() }
    Stop-DeployUpdateProbe
    if ($script:updateProcess) { $script:updateProcess.Dispose() }
}
