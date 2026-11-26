# Windows-only native WPF load/layout smoke; never launches deployment actions.
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this native WPF smoke test on Windows, in STA.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Use powershell.exe -STA -File App/Test-Wpf.ps1.' }
$checks = 0
function Assert($condition, $message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Get-VisualPixel($visual,[int]$x,[int]$y){
    $w=[int][Math]::Ceiling($visual.ActualWidth);$h=[int][Math]::Ceiling($visual.ActualHeight)
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($w,$h,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $drawing=New-Object Windows.Media.DrawingVisual;$context=$drawing.RenderOpen()
    try{$context.DrawRectangle([Windows.Media.VisualBrush]::new($visual),$null,[Windows.Rect]::new(0,0,$visual.ActualWidth,$visual.ActualHeight))}finally{$context.Close()}
    $bitmap.Render($drawing);$pixels=New-Object byte[] 4
    $bitmap.CopyPixels([Windows.Int32Rect]::new($x,$y,1,1),$pixels,4,0)
    return ($pixels -join ',')
}
function Assert-RoundedCornerPixels($frame) {
    foreach($scale in 1.0,1.25,1.5){
        $width=[int][Math]::Ceiling($frame.ActualWidth*$scale);$height=[int][Math]::Ceiling($frame.ActualHeight*$scale)
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,(96*$scale),(96*$scale),[Windows.Media.PixelFormats]::Pbgra32)
        $drawing=New-Object Windows.Media.DrawingVisual
        $context=$drawing.RenderOpen()
        try{$context.DrawRectangle([Windows.Media.VisualBrush]::new($frame),$null,[Windows.Rect]::new(0,0,$frame.ActualWidth,$frame.ActualHeight))}finally{$context.Close()}
        $bitmap.Render($drawing)
        $pixels=New-Object byte[] ($width*$height*4);$bitmap.CopyPixels($pixels,($width*4),0)
        $start=[int][Math]::Ceiling($scale);$end=[int][Math]::Floor(7*$scale)
        foreach($corner in 'TL','TR','BL','BR'){
            $ink=0
            for($y=$start;$y -le $end;$y++){
                for($x=$start;$x -le $end;$x++){
                    $px=if($corner.EndsWith('R')){$width-1-$x}else{$x}
                    $py=if($corner.StartsWith('B')){$height-1-$y}else{$y}
                    $i=4*($py*$width+$px)
                    if($pixels[$i+3] -gt 64 -and ([int]$pixels[$i]-[int]$pixels[$i+2]) -gt 4){$ink++}
                }
            }
            Assert ($ink -ge 3) "Rounded stroke visible at $corner / scale $scale (pixels=$ink)"
        }
    }
}
$main = . (Join-Path $PSScriptRoot 'TechMaster-Deploy.ps1') -ValidateOnly
Assert ($main -is [Windows.Window]) 'Main shell is a native WPF Window'
Assert ($main.FindName('Navigation').Items.Count -eq 9 -and $main.FindName('tabs').Items.Count -eq 9) 'All nine sections are present'
for ($i = 0; $i -lt 9; $i++) {
    $main.FindName('Navigation').SelectedIndex = $i
    Assert ($main.FindName('tabs').SelectedIndex -eq $i) "Navigation $i selects its content"
}
foreach ($scale in 1.0,1.25,1.5) {
    $size = New-Object Windows.Size((1366 / $scale), (768 / $scale))
    $main.Content.Measure($size); $main.Content.Arrange((New-Object Windows.Rect($size))); $main.UpdateLayout()
    Assert ($main.FindName('headerUpdate').ActualHeight -gt 0 -and $main.FindName('headerUpdate').ActualHeight -eq $main.FindName('btnRefresh').ActualHeight) "Aligned header button height at scale $scale"
    foreach ($button in 'btnAvDiagnostic','btnAvLastResult','avBar','lblAvProgress','avProgressPanel','btnDefaults','btnPaintStore','btnDriverFix','btnDriverGuide','btnFormat','btnKeyboard','btnExport','bDl','btnWindowsIso','btnBasicAppInstall','checkUpdate','btnManageApps','btnQuickGuide','btnContact','btnResetIdentity','btnSaveIdentity','btnRemoveLogo','btnWindowsSetupKey','btnConfirmRetail','btnConfirmCompany') {
        Assert ($null -ne $main.FindName($button)) "$button exists at scale $scale"
    }
}
# Render actual focused buttons: the focus ring must not reflow or clip text.
$preview=Import-DeployWindow (Join-Path $PSScriptRoot 'MainWindow.xml')
try {
    $preview.Show()
    $preview.WindowState='Maximized'
    $preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    Assert ($preview.ActualWidth -ge [Windows.SystemParameters]::WorkArea.Width-2 -and $preview.ActualHeight -ge [Windows.SystemParameters]::WorkArea.Height-2) 'Maximized window fills the work area without right/bottom gaps'
    $preview.WindowState='Normal';$preview.UpdateLayout()
    $nav=$preview.FindName('Navigation');$sidebar=$nav.Parent.Parent
    $beforeLock=Get-VisualPixel $sidebar 4 22
    $nav.IsEnabled=$false;$preview.UpdateLayout()
    $preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $afterLock=Get-VisualPixel $sidebar 4 22
    Assert ($beforeLock -ceq '70,43,20,255' -and $afterLock -ceq $beforeLock) 'Locked navigation retains its navy background rather than turning white'
    $nav.IsEnabled=$true
    $update=$preview.FindName('headerUpdate');$refresh=$preview.FindName('btnRefresh')
    foreach($button in $refresh,$update){$button.ApplyTemplate()|Out-Null}
    [void]$refresh.Focus();$preview.UpdateLayout()
    $label=$update.Template.FindName('ButtonContent',$update)
    $before=$label.TranslatePoint((New-Object Windows.Point(0,($label.ActualHeight/2))),$update).Y
    [void]$update.Focus();$preview.UpdateLayout()
    $focused=$label.TranslatePoint((New-Object Windows.Point(0,($label.ActualHeight/2))),$update).Y
    $other=$refresh.Template.FindName('ButtonContent',$refresh)
    $otherY=$other.TranslatePoint((New-Object Windows.Point(0,($other.ActualHeight/2))),$refresh).Y
    Assert ($update.IsKeyboardFocused) 'Update button receives real keyboard focus'
    Assert ([Math]::Abs($focused-$before) -le 1) 'Focus does not move Update text'
    Assert ([Math]::Abs($focused-$update.ActualHeight/2) -le 1 -and [Math]::Abs($focused-$otherY) -le 1) 'Both header labels remain vertically centered'
    Assert ($label.ActualHeight -le $update.ActualHeight-$update.Padding.Top-$update.Padding.Bottom) 'Update label fits inside fixed button height'
    $preview.FindName('tabs').SelectedIndex=3;$preview.UpdateLayout()
    $input=$preview.FindName('Company');$input.Text='Nội dung mẫu';$input.SelectAll()
    Assert ($input.SelectedText -ceq 'Nội dung mẫu' -and $input.Parent.Clip -is [Windows.Media.RectangleGeometry]) 'Rounded input retains native text editing and receives a size-aware clip'
    $preview.FindName('tabs').SelectedIndex=4;$preview.UpdateLayout()
    $picker=$preview.FindName('cbProduct');[void]$picker.Items.Add('Office A');[void]$picker.Items.Add('Office B');$picker.SelectedIndex=1
    $preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    [void]$picker.Focus();$picker.IsDropDownOpen=$true;$preview.UpdateLayout()
    $preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    Assert ($picker.SelectedItem -eq 'Office B') 'Rounded selector retains native selection'
    Assert ($picker.IsLoaded -and $picker.IsDropDownOpen) ("Rounded selector popup opens after Loaded; loaded=$($picker.IsLoaded), open=$($picker.IsDropDownOpen), visible=$($picker.IsVisible)")
    $picker.IsDropDownOpen=$false
    $key=$preview.FindName('tbOffKey')
    $frame=$key.Parent
    while($frame -and $frame.Tag -cne 'RoundedClip'){$frame=[Windows.Media.VisualTreeHelper]::GetParent($frame)}
    Assert ($null -ne $frame) 'Office key uses a rounded frame'
    [void]$update.Focus();$preview.UpdateLayout()
    Assert-RoundedCornerPixels $frame
    [void]$key.Focus();$preview.UpdateLayout()
    Assert-RoundedCornerPixels $frame


} finally {$preview.Close()}
$selected = Get-OffSel
Assert ($selected.Id -eq 'HomeBusiness2024Retail' -and $selected.Arch -eq '64' -and $selected.Langs.Count -eq 2) 'Office defaults preserved'
$rb32.IsChecked = $true
Assert ((Get-OffSel).Arch -eq '32') 'WPF architecture choice reaches Office selection'
$languageChoices[0].IsChecked = $false
Assert (((Get-OffSel).Langs -join ',') -eq 'en-us') 'WPF language selection reaches Office options'
Assert ($basicAppChoices.Count -eq 12) 'All existing apps retained plus UltraViewer'
$ultraChoice=@($basicAppChoices|Where-Object {$_.Tag.Name -eq 'UltraViewer'})
Assert ($ultraChoice.Count -eq 1 -and $ultraChoice[0].Tag.Source -eq 'Official' -and $ultraChoice[0].Tag.Version -eq '6.6.133' -and -not $ultraChoice[0].IsChecked) 'UltraViewer is optional and uses the chosen official version'
foreach ($node in $markup.SelectNodes('//*[@x:Name and not(ancestor::*[local-name()="ControlTemplate"])]', $ns)) {
    $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    Assert ($null -ne $main.FindName($name)) "XAML control $name resolves"
}
# Report settings actions use an isolated directory, never the checkout's identity.
$identityFixture=Join-Path ([IO.Path]::GetTempPath()) ('tm-settings-ui-'+[guid]::NewGuid().ToString('N'))
$previousReportDirectory=$DirBB
try{
    $DirBB=$identityFixture
    $Company.Text='Đơn vị kiểm tra';$Address.Text='Địa chỉ kiểm tra';$Phone.Text='0123';$Technician.Text='Kỹ thuật viên kiểm tra'
    $main.FindName('btnSaveIdentity').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $settingsPath=Join-Path $identityFixture 'BienBan-Config.json'
    $saved=[IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json
    Assert ($saved.Company -ceq 'Đơn vị kiểm tra') 'Save button persists edited settings without exporting a report'
    $Address.Text='';$Phone.Text=''
    $main.FindName('btnSaveIdentity').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $saved=[IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json
    Assert ($saved.Address -ceq '' -and $saved.Phone -ceq '' -and $saved.Company -ceq 'Đơn vị kiểm tra') 'Save button persists cleared fields while retaining other values'
    $logoFixture=Join-Path $identityFixture 'Logo.svg'
    [IO.File]::WriteAllText($logoFixture,'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0H10V10H0Z"/></svg>')
    [IO.File]::WriteAllText((Join-Path $identityFixture 'customer-report.html'),'retained')
    Update-LogoPreview
    Assert ($main.FindName('btnRemoveLogo').IsEnabled -and $main.FindName('logoBox').Source) 'A stored logo enables the remove action and renders its preview'
    $before=[IO.File]::ReadAllText($settingsPath)
    $main.FindName('btnRemoveLogo').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (-not (Test-Path $logoFixture) -and -not $main.FindName('logoBox').Source -and -not $main.FindName('btnRemoveLogo').IsEnabled) 'Remove-logo button clears the stored file, preview and enabled state'
    Assert ([IO.File]::ReadAllText($settingsPath) -ceq $before -and (Test-Path (Join-Path $identityFixture 'customer-report.html'))) 'Remove-logo button preserves settings and existing reports'
}finally{$DirBB=$previousReportDirectory;if(Test-Path $identityFixture){Remove-Item $identityFixture -Recurse -Force}}
# Exercise both real handover dialogs and export handlers, without opening a browser.
$confirmationOutput=Join-Path ([IO.Path]::GetTempPath()) ('tm-confirm-ui-'+[guid]::NewGuid().ToString('N'))
$confirmationSupplier=[pscustomobject]@{Company='Supplier test';Address='';Phone='';Technician='Test tech'}
$confirmationSnapshot=[pscustomobject]@{Computer='TEST';Model='Model';Serial='Serial';CheckedAt=(Get-Date);Products=@([pscustomobject]@{Name='Windows 11 Pro';KeyTail='12345';Status='Đã kích hoạt'})}
function Start-Process{param($FilePath)$script:confirmationOpened=$FilePath}
try{
    foreach($kind in 'Retail','Company'){
        $confirm=New-DeployLicenseConfirmationWindow -Template $kind -Supplier $confirmationSupplier -CustomerName 'Test customer' -Snapshot $confirmationSnapshot -OutputDirectory $confirmationOutput
        Assert ($confirm.FindName('CompanyFields').Visibility.ToString() -eq $(if($kind -eq 'Company'){'Visible'}else{'Collapsed'})) "$kind shows only its relevant fields"
        $confirm.FindName('Export').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert (-not $confirm.Tag.Path -and $confirm.FindName('Validation').Text) 'An unselected product cannot be confirmed'
        $confirm.Tag.Choices[0].Check.IsChecked=$true
        $confirm.FindName('Export').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ((Test-Path $confirm.Tag.Path) -and $script:confirmationOpened -eq $confirm.Tag.Path) "$kind export writes and opens its own document"
    }
    Assert (@(Get-ChildItem $confirmationOutput -File).Count -eq 2) 'Retail and company actions produce separate files'
}finally{Remove-Item Function:Start-Process;if(Test-Path $confirmationOutput){Remove-Item $confirmationOutput -Recurse -Force}}
$updater = . (Join-Path $PSScriptRoot 'Update-App.ps1') -Root (Split-Path -Parent $PSScriptRoot) -ValidateOnly
Assert ($updater -is [Windows.Window]) 'Updater is a native WPF Window'
foreach ($state in 'Available','Ready','Applying','Latest','History','Error','Complete','RollbackReady') {
    Set-UpdateView $state 'Test only'
    $view = Get-DeployUpdateView $state
    Assert ($updater.FindName('Primary').Content -ceq $view.primary) "$state primary action shown correctly"
    Assert ($updater.FindName('Primary').IsEnabled -eq (-not $view.busy)) "$state correctly enables actions"
}
Set-UpdateView 'Applying' 'Test only'
Assert (-not $updater.FindName('Cancel').IsEnabled) 'Apply cannot be interrupted by Close button'
$precheck = . (Join-Path (Split-Path -Parent $PSScriptRoot) 'FixClone/Master-Preflight.ps1') -AfterClone -ValidateOnly
Assert ($precheck -is [Windows.Window] -and $null -ne $precheck.FindName('CleanDesktop')) 'Native WPF Sysprep/desktop preflight loads without running deployment'
Set-UpdateView 'Complete' 'Hoàn tất'
Assert ($updater.FindName('Cancel').Visibility -eq 'Collapsed' -and $updater.FindName('Primary').Content -eq 'Đóng và mở ứng dụng') 'Completed update has exactly one Close button'
Assert ($updater.FindName('ChoosePackage').Visibility -eq 'Collapsed') 'Offline installer is hidden after completion'
Assert ($null -ne $main.Icon -and $null -ne $updater.Icon) 'Application windows use TechMaster icon'
Assert ([TechMaster.DesktopIdentity]::CurrentId() -ceq 'TechMaster.Deploy') 'PowerShell host uses TechMaster taskbar identity'
$dialog=New-DeployConfirmWindow 'Test' 'Cài đặt bản cập nhật' 'Cài đặt' -Danger
Assert ($dialog.FindName('Confirm').Content -eq 'Cài đặt' -and $dialog.FindName('Cancel').IsDefault -and $dialog.Tag -eq $false) 'Styled confirmation defaults to Cancel'
Assert ($dialog.FindName('Input').Visibility -eq 'Collapsed') 'Destructive confirmation requires no typed phrase'
$dialog.FindName('Confirm').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($dialog.Tag -eq $true) 'Confirm button returns explicit consent'
$dialog=New-DeployConfirmWindow 'Test' 'Thông báo' 'Đóng' -Information
Assert ($dialog.FindName('Cancel').Visibility -eq 'Collapsed' -and $dialog.FindName('Confirm').IsDefault) 'Information dialog shows one Close button'
$dialog.Close()
$diag=Import-DeployWindow (Join-Path $PSScriptRoot 'DiagnosticsWindow.xml')
$size=New-Object Windows.Size(760,590);$diag.Content.Measure($size);$diag.Content.Arrange((New-Object Windows.Rect($size)));$diag.UpdateLayout()
$heights=@('Export','Copy','Close'|ForEach-Object{$diag.FindName($_).ActualHeight})
Assert ($null -ne $diag.FindName('Heading') -and $heights[0] -gt 0 -and $heights[0] -eq $heights[1] -and $heights[1] -eq $heights[2]) "Diagnostic Export / Copy / Close buttons share one height ($($heights -join '/'))"
$diag.Close()
$root=Split-Path -Parent $PSScriptRoot
$office= . (Join-Path $root 'Office/Office-Cleanup.ps1') -Mode Inspect -ValidateOnly
Assert ($office -is [Windows.Window] -and $office.FindName('Keys').IsReadOnly -and -not $office.FindName('DeleteKeys').IsEnabled) 'Office inventory UI is read-only in Inspect mode'
$ultra= . (Join-Path $root 'FixClone/UltraViewer-Reset.ps1') -ValidateOnly
Assert ($ultra -is [Windows.Window] -and $null -ne $ultra.FindName('Restore')) 'UltraViewer UI loads with restore action; no identity mutation'
$keyboard= . (Join-Path $root 'FixClone/Fix-BanPhim.ps1') -ValidateOnly
Assert ($keyboard -is [Windows.Window]) 'Keyboard graphical choices load without changing input settings'
$master= . (Join-Path $root 'FixClone/Master-Preflight.ps1') -ValidateOnly
Assert ($master.FindName('CleanOfficeTrial').IsChecked -and $master.FindName('PrepareUltra').IsChecked -and -not $master.FindName('CleanWindowsSetupKey').IsChecked) 'Master preflight offers conservative trial cleanup and clone identity preparation'
$master.Close()
$windowsKeyView= . (Join-Path $root 'FixClone/Windows-SetupKey.ps1') -ValidateOnly
Assert ($windowsKeyView -is [Windows.Window] -and -not $windowsKeyView.FindName('Clean').IsEnabled -and -not $windowsKeyView.FindName('Restore').IsEnabled) 'Windows setup-key review requires inspection before any cleanup or undo is enabled'
$windowsKeyView.Close(); $keyboard.Close(); $ultra.Close(); $office.Close(); $precheck.Close()
$docs=New-DeployInfoWindow (Split-Path -Parent $PSScriptRoot) -Kind Changes
Assert ($docs -is [Windows.Window] -and $docs.FindName('Sections').Items.Count -ge 3 -and $docs.FindName('ContentTitle').Text -match 'Phiên bản') 'Changelog is readable in WPF with initial content'
$docs.Show();$docs.UpdateLayout()
$docs.FindName('Sections').SelectedIndex=1
Assert ($docs.FindName('ContentTitle').Text -eq $docs.FindName('Sections').SelectedItem.Heading) 'Choosing a release updates its content'
$guide=New-DeployInfoWindow (Split-Path -Parent $PSScriptRoot) -Kind Guide -Section 'Liên hệ / góp ý'
Assert ($guide.FindName('Sections').SelectedItem.Label -eq 'Liên hệ / góp ý' -and $guide.FindName('Notes').Items.Count -gt 0) 'Guide opens the requested contact topic'
Assert ($guide.FindName('ZaloLink').NavigateUri.AbsoluteUri -ceq 'https://zalo.me/0976852096' -and $guide.FindName('MailLink').NavigateUri.AbsoluteUri -ceq 'mailto:vienkendo@gmail.com') 'User-provided contact links are present without sending anything'
$docs.Close();$guide.Close()
$store=Join-Path ([IO.Path]::GetTempPath()) ('tm-manager-'+[guid]::NewGuid().ToString('N')+'/CustomApps.json')
$manager=New-DeployCustomAppsWindow $store $script:builtInBasicApps
$messageFn=${function:Show-DeployMessage}
function Show-DeployMessage([string]$message){throw ('Native UI action failed: '+$message)}
try{
    Assert ($manager -is [Windows.Window] -and $manager.FindName('Apps').Items.Count -eq 0) 'Custom-app manager opens without writing a catalog'
    $manager.Show();$manager.UpdateLayout()
    $manager.FindName('AppName').Text='Demo package';$manager.FindName('PackageId').Text='Example.Package'
    $manager.FindName('Save').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    Assert ((Test-Path -LiteralPath $store) -and @(Get-DeployCustomApps $store).Count -eq 1 -and $manager.Tag.Changed) 'Saving in the manager writes only the supplied local catalog'
    $manager.FindName('Provider').SelectedIndex=1
    Assert ($manager.FindName('LocalFields').Visibility -eq 'Visible') 'Choosing local installers shows the EXE/MSI fields'
}finally{Set-Item Function:Show-DeployMessage $messageFn;$manager.Close();if(Test-Path -LiteralPath (Split-Path -Parent $store)){Remove-Item -LiteralPath (Split-Path -Parent $store) -Recurse -Force}}
Set-DeployUpdateAvailability $true '9.0.0.0'
Assert ($main.FindName('UpdateBadge').Visibility -eq 'Visible' -and $main.FindName('headerUpdate').ToolTip -match '9.0.0.0') 'New update is represented by a red badge and accessible tooltip'
Set-DeployUpdateAvailability $false
Assert ($main.FindName('UpdateBadge').Visibility -eq 'Collapsed') 'Latest state hides the badge'
$window=$updater
$script:updateCompletionClosed=$false
$updater.Add_Closed({$script:updateCompletionClosed=$true})
Assert (-not $script:session.OpenApplication) 'Completion remains visible without automatically launching an app'
$updater.FindName('Primary').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($script:updateCompletionClosed -and $script:session.OpenApplication) 'Completion button closes the updater before requesting application launch'
$main.Close()
Write-Host "PASS: $checks native WPF assertions; nine tabs, control binding, layout, Office defaults and updater states."
