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
. (Join-Path $PSScriptRoot 'Defaults.Core.ps1')
. (Join-Path $PSScriptRoot 'Defaults.UI.ps1')
. (Join-Path $PSScriptRoot 'LanAccounts.Core.ps1')
. (Join-Path $PSScriptRoot 'LanAccounts.UI.ps1')
. (Join-Path $PSScriptRoot 'LanShare.Core.ps1')
. (Join-Path $PSScriptRoot 'LanShare.UI.ps1')
. (Join-Path $PSScriptRoot 'LanConnect.Core.ps1')
. (Join-Path $PSScriptRoot 'LanConnect.UI.ps1')
. (Join-Path $PSScriptRoot 'NetworkRun.Core.ps1')
. (Join-Path $PSScriptRoot 'NetworkRun.UI.ps1')
. (Join-Path $PSScriptRoot 'Overview.Core.ps1')
. (Join-Path $PSScriptRoot 'Overview.UI.ps1')
. (Join-Path $PSScriptRoot 'AV.Repair.ps1')
. (Join-Path $PSScriptRoot 'AV.Repair.UI.ps1')
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
$ovVersion.Text = $lblTitle.Text + ' · thư mục ' + $Root
$cPrimary = '#10223F'; $cMuted = '#526880'; $cDanger = '#B91C1C'
$script:officeRun = $null; $script:mediaDownload = $null; $script:uiWork = $null
$script:officeLog = $null; $script:updateClosing = $false
function Set-Status([string]$message,[ValidateSet('Info','Working','Attention','Success','Error')][string]$Kind='Info') { Set-DeployNotice $status $message $Kind }
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
    catch { Set-Status 'Thao tác chưa hoàn tất.' 'Error'; Show-DeployMessage $_.Exception.GetBaseException().Message 'TechMaster Deploy' 'Error' }
    finally { $btnRefresh.IsEnabled = $true; $btnExport.IsEnabled = $true; $btnConfirmRetail.IsEnabled=$true; $btnConfirmCompany.IsEnabled=$true }
}
function Update-MachineInfo {
    Set-Status 'Đang đọc thông tin máy và bản quyền…'
    Set-DeployOverviewBusy $form
    Start-UiWork 'param($core) $ErrorActionPreference = ''Stop''; . $core; Get-DeployOverviewSnapshot' @((Join-Path $PSScriptRoot 'Overview.Core.ps1')) {
        param($result)
        $snapshot = $result[-1]
        $lblInfo.Text = $snapshot.Header
        Set-DeployOverviewView $form $snapshot
        Set-Status 'Đã làm mới thông tin máy.'
    }
}
# Menu items carry the name of their page in Tag; group headings have none and cannot stay selected.
function Select-DeployPage([string]$Name) {
    foreach ($item in $Navigation.Items) { if ([string]$item.Tag -ceq $Name) { $Navigation.SelectedItem = $item; return } }
}
function Sync-DeployPage {
    $item = $Navigation.SelectedItem
    if (-not $item -or -not [string]$item.Tag) { if ($script:navigationItem) { $Navigation.SelectedItem = $script:navigationItem }; return }
    $script:navigationItem = $item
    $tabs.SelectedItem = $form.FindName([string]$item.Tag)
}
$script:navigationItem = $null
$Navigation.Add_SelectionChanged({ Sync-DeployPage })
Select-DeployPage 'tabOverview'
Sync-DeployPage
foreach ($node in $markup.SelectNodes('//*[@x:Name and @Tag]', $ns)) {
    $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    if ($name -cmatch '^go[A-Z]') { $form.FindName($name).Add_Click({ param($sender, $event) Select-DeployPage ([string]$sender.Tag) }) }
}
function Copy-DeployWebCommand {
    try { [Windows.Clipboard]::SetText($script:DeployWebCommand); Set-Status ('Đã sao chép lệnh: ' + $script:DeployWebCommand + ' — dán vào PowerShell trên máy kia.') 'Success' }
    catch { Set-Status 'Chưa sao chép được lệnh; thử lại.' 'Error' }
}
Bind-Click 'btnRefresh' { Update-MachineInfo; Request-DeployUpdateNotification }
Bind-Click 'btnQuickGuide' { Show-DeployQuickGuide $Root $form }
Bind-Click 'btnContact' { Show-DeployQuickGuide $Root $form -Section 'Liên hệ / góp ý' }
Bind-Click 'headerUpdate' { if($script:updateProcess){Show-DeployUpdater}else{Select-DeployPage 'tabUpdate'} }
Bind-Click 'btnSysprepCheck' { Start-Tool (Join-Path $DirClone 'Fix-SysprepErrors.bat') 'Kiểm tra lỗi Sysprep' }
Bind-Click 'btnSysprep' { if (Confirm-Box "Chuẩn bị máy gốc và chạy Sysprep?`nCuối quy trình máy sẽ tự tắt; clone ổ trước khi bật lại." 'Sysprep') { Start-Tool (Join-Path $DirClone 'Run-Sysprep.bat') 'Chuẩn bị + Sysprep' } }
Bind-Click 'btnReinstall' { Open-DeployFolder (Join-Path $DirClone 'Reinstall') }
Bind-Click 'btnCloneHelp' { Show-DeployQuickGuide $Root $form -Section 'Clone hàng loạt' }
Bind-Click 'btnCloneFix' { Start-Tool (Join-Path $DirClone 'Fix-CloneDuplicate.bat') 'Xử lý trùng lặp' }
Bind-Click 'btnFormat' { Start-Tool (Join-Path $DirClone 'Fix-DinhDang.bat') 'Chỉnh ngày / số' }
Bind-Click 'btnDefaults' {Show-DeployDefaults $form 'Printer'}
Bind-Click 'btnPrinterCleanup' {Show-DeployDefaults $form 'Cleanup'}
Bind-Click 'btnDefaultApps' {Show-DeployDefaults $form 'Apps'}
Bind-Click 'btnLanAccounts' {Show-DeployLanAccounts $form}
Bind-Click 'btnLanShare' {Show-DeployShare $form}
Bind-Click 'btnLanConnect' {Show-DeployConnect $form}
Bind-Click 'btnNetworkRun' {Show-DeployNetworkRun $Root $form}
Bind-Click 'btnOverviewNetworkRun' {Show-DeployNetworkRun $Root $form}
Bind-Click 'btnOverviewCopyCommand' {Copy-DeployWebCommand}
Bind-Click 'btnLanCopyCommand' {Copy-DeployWebCommand}
Bind-Click 'btnOverviewRefresh' {Update-MachineInfo}
Bind-Click 'btnOverviewCopy' {
    try { [Windows.Clipboard]::SetText((Format-DeployOverviewText $btnOverviewCopy.Tag)); Set-Status 'Đã sao chép thông tin máy.' 'Success' }
    catch { Set-Status 'Chưa sao chép được; thử lại.' 'Error' }
}
Bind-Click 'btnOverviewChanges' {Show-DeployChangeLog $Root $form}
Bind-Click 'btnOverviewGuide' {Show-DeployQuickGuide $Root $form -Section 'Tổng quan'}
Bind-Click 'btnKeyboard' { Start-Tool (Join-Path $DirClone 'Fix-BanPhim.bat') 'Bàn phím / EVKey' }
Bind-Click 'btnUltraReset' {
    $script = Join-Path $DirClone 'UltraViewer-Reset.ps1'
    $command = "& '{0}'" -f $script.Replace("'", "''")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $script:desktopProcess = Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -WindowStyle Hidden -PassThru
}
function Show-DeployDiagnostic([string]$title, [string]$heading, [string]$text, [string]$fileStem) {
    $script:diagnosticWindow = Import-DeployWindow (Join-Path $PSScriptRoot 'DiagnosticsWindow.xml')
    $script:diagnosticWindow.Owner = $form
    $script:diagnosticWindow.Title = $title
    $script:diagnosticWindow.FindName('Heading').Text = $heading
    $script:diagnosticWindow.FindName('Details').Text = $text
    $script:diagnosticFileStem = $fileStem
    $script:diagnosticWindow.FindName('Copy').Add_Click({ [Windows.Clipboard]::SetText($script:diagnosticWindow.FindName('Details').Text) })
    $script:diagnosticWindow.FindName('Export').Add_Click({
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = 'Lưu kết quả chẩn đoán'
        $dialog.Filter = 'Tệp văn bản (*.txt)|*.txt'
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        $dialog.FileName = '{0}_{1}_{2}.txt' -f $script:diagnosticFileStem, $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')
        if (-not $dialog.ShowDialog($script:diagnosticWindow)) { return }
        try {
            [IO.File]::WriteAllText($dialog.FileName, $script:diagnosticWindow.FindName('Details').Text, [Text.UTF8Encoding]::new($true))
            Set-Status ('Đã lưu kết quả: ' + $dialog.FileName)
            Start-Process explorer.exe ('/select,"{0}"' -f $dialog.FileName)
        } catch { Show-DeployMessage ('Không lưu được tệp: ' + $_.Exception.Message) 'TechMaster Deploy' 'Error' }
    })
    $script:diagnosticWindow.FindName('Close').Add_Click({ $script:diagnosticWindow.Close() })
    [void]$script:diagnosticWindow.ShowDialog()
}
Bind-Click 'btnUltraDiagnostic' {
    Set-Status 'Đang đọc cấu hình UltraViewer và card mạng…'
    Start-UiWork 'param($diagnostics) . $diagnostics; Format-UltraViewerDiagnostic (Get-UltraViewerDiagnostic)' @((Join-Path $DirClone 'UltraViewer.Diagnostics.ps1')) {
        param($result)
        Show-DeployDiagnostic 'Chẩn đoán UltraViewer' 'Chẩn đoán UltraViewer — chỉ đọc' ([string]$result[-1]) 'ChanDoan-UltraViewer'
        Set-Status 'Đã chẩn đoán UltraViewer; so sánh kết quả của hai máy bị trùng ID.'
    }
}
function Format-DeployElapsed([TimeSpan]$span) { '{0}:{1:00}' -f [int][Math]::Floor($span.TotalMinutes), $span.Seconds }
function Reset-DeployAvButton {
    $button = $form.FindName('btnAvDiagnostic')
    $button.IsEnabled = $true
    $button.Content = 'Chẩn đoán lại'
}
$script:avTimer = New-DeployTimer 300 {
    $run = $script:avRun
    if (-not $run) { $script:avTimer.Stop(); return }
    $bar = $form.FindName('avBar'); $label = $form.FindName('lblAvProgress')
    $elapsed = Format-DeployElapsed ((Get-Date) - $run.Started)
    if ($script:uiWork -and $script:uiWork -eq $run.Work) {
        $p = $run.Progress
        $bar.IsIndeterminate = -not $p.Percent
        if ($p.Percent) { $bar.Value = [double]$p.Percent }
        $step = if ($p.Step) { 'Bước {0}/{1} · ' -f $p.Step, $p.Steps } else { '' }
        Set-DeployNotice $label ('{0}{1} · {2}' -f $step, $(if ($p.Stage) { $p.Stage } else { 'Đang khởi động…' }), $elapsed) 'Working'
        return
    }
    # The worker finished (or failed): the completion handler sets Done before showing results.
    $script:avTimer.Stop(); $script:avRun = $null
    $bar.IsIndeterminate = $false
    if (-not $run.Done) {
        $bar.Value = 0
        Set-DeployNotice $label ('Chẩn đoán chưa hoàn tất sau ' + $elapsed + '. Xem thông báo lỗi, rồi bấm Chẩn đoán lại.') 'Error'
    }
    Reset-DeployAvButton
}
Bind-Click 'btnAvDiagnostic' {
    if ($script:uiWork) { Set-Status 'Chờ thao tác hiện tại hoàn tất.'; return }
    $deep = [bool]$form.FindName('chkAvDeep').IsChecked
    # Any running Defender scan (full, quick or per-drive) already saturates the disk;
    # adding our reads froze Explorer on an HDD machine (KY-THUAT, 26/11).
    $running = $null
    try { $running = Get-AvRunningScan } catch { }
    if ($running) {
        $message = 'Defender đang {0} (từ {1:HH:mm}). Chạy chẩn đoán lúc này làm ổ đĩa bận thêm, máy có thể đơ.{2}' -f $running.Name.ToLower(), $running.Started, $(if ($deep) { ' Quét sâu sẽ được tắt cho lần này.' } else { '' })
        $message += "`n`nNên đợi lượt quét xong (xem Windows Security → Virus & threat protection). Vẫn chạy?"
        if (-not (Confirm-Box $message 'Defender đang quét' 'Vẫn chạy (chế độ nhẹ)' 'Để sau' -Owner $form)) { Set-Status 'Đã hoãn chẩn đoán vì Defender đang quét.'; return }
        $deep = $false
    }
    $progress = [hashtable]::Synchronized(@{ Step = 0; Steps = 6; Percent = 0; Stage = '' })
    $button = $form.FindName('btnAvDiagnostic'); $button.IsEnabled = $false; $button.Content = 'Đang chẩn đoán…'
    $form.FindName('avProgressPanel').Visibility = 'Visible'
    $bar = $form.FindName('avBar'); $bar.Value = 0; $bar.IsIndeterminate = $true
    Set-DeployNotice ($form.FindName('lblAvProgress')) 'Đang khởi động… · 0:00' 'Working'
    Set-Status 'Đang chẩn đoán báo virus (chỉ đọc). Có thể mất 1–2 phút; theo dõi tiến độ trong thẻ.' 'Working'
    $run = @{ Progress = $progress; Started = Get-Date; Done = $false; Work = $null }
    $script:avRun = $run
    # Background thread at below-normal priority so Explorer and the desktop stay responsive.
    Start-UiWork 'param($diagnostics, $progress, $deep) [Threading.Thread]::CurrentThread.Priority = ''BelowNormal''; . $diagnostics; $report = Get-AvDiagnostic -Progress $progress -Deep:$deep; $report; Format-AvDiagnostic $report' @((Join-Path $PSScriptRoot 'AV.Diagnostics.ps1'), $progress, $deep) {
        param($result)
        $text = [string]$result[-1]
        $script:avLastReport = $result[-2]
        $form.FindName('btnAvRepair').Visibility = 'Visible'
        $run = $script:avRun
        if ($run) { $run.Done = $true }
        $elapsed = if ($run) { Format-DeployElapsed ((Get-Date) - $run.Started) } else { '' }
        $kind = if ($text -match '\[NGHIÊM TRỌNG\]') { 'Error' } elseif ($text -match '\[KIỂM TRA') { 'Attention' } else { 'Success' }
        $summary = switch ($kind) { 'Error' { 'Có dấu hiệu NGHIÊM TRỌNG' } 'Attention' { 'Có mục cần kiểm tra' } default { 'Chưa thấy dấu hiệu nghiêm trọng' } }
        $bar = $form.FindName('avBar'); $bar.IsIndeterminate = $false; $bar.Value = 100
        Set-DeployNotice ($form.FindName('lblAvProgress')) ('Xong lúc {0} (mất {1}). {2} — xem KẾT LUẬN SƠ BỘ.' -f (Get-Date -Format 'HH:mm'), $elapsed, $summary) $kind
        $script:avLastResult = $text
        $form.FindName('btnAvLastResult').Visibility = 'Visible'
        Reset-DeployAvButton
        Set-Status ('Đã chẩn đoán báo virus: ' + $summary + '.') $kind
        Show-DeployDiagnostic 'Chẩn đoán ứng dụng bị báo virus' 'Ứng dụng bị báo virus — chỉ đọc' $text 'ChanDoan-BaoVirus'
    }
    if ($script:uiWork) { $run.Work = $script:uiWork; $script:avTimer.Start() }
    else { $script:avRun = $null; $form.FindName('avProgressPanel').Visibility = 'Collapsed'; Reset-DeployAvButton; $button.Content = 'Chẩn đoán báo virus' }
}
Bind-Click 'btnAvRepair' {
    if (-not $script:avLastReport) { Show-DeployMessage 'Chạy Chẩn đoán báo virus trước để lập danh sách sửa.' 'Sửa lỗi báo virus' 'Warning'; return }
    if ($script:avRepairWindow -and $script:avRepairWindow.IsVisible) { $script:avRepairWindow.Activate() | Out-Null; return }
    try { $script:avRepairWindow = New-DeployAvRepairWindow $script:avLastReport $form }
    catch { Show-DeployMessage ('Không mở được cửa sổ sửa lỗi: ' + $_.Exception.Message) 'TechMaster Deploy' 'Error'; return }
    $script:avRepairWindow.Tag.OnFinished = {
        param($results)
        $failed = @($results | Where-Object { -not $_.Ok }).Count
        $kind = if ($failed) { 'Attention' } else { 'Success' }
        Set-DeployNotice ($form.FindName('lblAvProgress')) ('Đã chạy sửa lỗi lúc {0}: {1} thành công, {2} lỗi. Bấm Chẩn đoán lại để kiểm tra.' -f (Get-Date -Format 'HH:mm'), (@($results).Count - $failed), $failed) $kind
        $form.FindName('avProgressPanel').Visibility = 'Visible'
        Set-Status 'Đã chạy sửa lỗi báo virus. Chẩn đoán lại để xác nhận.' $kind
    }
    $script:avRepairWindow.Show()
}
Bind-Click 'btnAvLastResult' {
    if ($script:avLastResult) { Show-DeployDiagnostic 'Chẩn đoán ứng dụng bị báo virus' 'Ứng dụng bị báo virus — chỉ đọc' $script:avLastResult 'ChanDoan-BaoVirus' }
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
    $tbCustomer.Text='';$tbCustomerCompany.Text='';$tbCustomerAddress.Text=''
    Update-LogoPreview
    Set-Status 'Đã xoá thông tin đơn vị và logo. Có thể nhập thông tin đơn vị mới.'
}
Bind-Click 'btnExport' {
    try { $cfg=Save-ReportInfo }
    catch { Show-DeployMessage $_.Exception.Message 'Lưu biên bản' 'Error'; return }
    Set-Status 'Đang đọc bản quyền và xuất biên bản…'
    Start-UiWork @'
param($script, $customer, $technician, $customerCompany, $customerAddress)
$ErrorActionPreference = 'Stop'
& $script -NoPrompt -Customer $customer -CustomerCompany $customerCompany -CustomerAddress $customerAddress -Technician $technician 6>$null
'@ @((Join-Path $DirBB 'Bien-Ban-Ban-Quyen.ps1'), $tbCustomer.Text.Trim(), $cfg.Technician, $tbCustomerCompany.Text.Trim(), $tbCustomerAddress.Text.Trim()) {
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
    $script:confirmationRequest=@{Template=$template;Supplier=$cfg;Customer=$tbCustomer.Text.Trim();CustomerCompany=$tbCustomerCompany.Text.Trim();CustomerAddress=$tbCustomerAddress.Text.Trim()}
    Set-Status 'Đang đọc thông tin máy và phần mềm bàn giao…'
    Start-UiWork @'
param($core)
. $core
Get-DeployConfirmationSnapshot
'@ @((Join-Path $DirBB 'LicenseConfirmation.Core.ps1')) {
        param($result)
        $request=$script:confirmationRequest
        $dialog=New-DeployLicenseConfirmationWindow -Template $request.Template -Supplier $request.Supplier -CustomerName $request.Customer -CustomerCompany $request.CustomerCompany -CustomerAddress $request.CustomerAddress -Snapshot $result[-1] -OutputDirectory (Join-Path $DirBB 'BienBan') -Owner $form
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
Bind-Click 'btnPaintStore' {
    try{Start-Process 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H' -ErrorAction Stop}
    catch{Start-Process 'https://apps.microsoft.com/detail/9PCFS5B6T72H' -ErrorAction Stop}
    Set-Status 'Đã mở trang Paint chính thức. Bấm Get / Cài đặt trong Microsoft Store; app chưa xác nhận Paint đã được cài.' 'Info'
}
Bind-Click 'btnWindowsOld' { Open-WindowsOldCleanup }
Bind-Click 'btnMenuClassic' { Set-ExplorerMenuChoice Legacy }
Bind-Click 'btnMenuDefault' { Set-ExplorerMenuChoice Default }
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
    Set-Status 'Thao tác gặp lỗi; có thể thử lại.' 'Error'
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
