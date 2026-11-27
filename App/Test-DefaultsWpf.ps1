# Native WPF controller/layout tests. Worker startup is intercepted; never changes printers/default apps.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Defaults.Core.ps1')
. (Join-Path $PSScriptRoot 'Defaults.UI.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
Initialize-DeployDefaultsNative
Assert ([bool]('TechMaster.DefaultsNative' -as [type])) 'Native printer/default-association interop compiles on Windows PowerShell'
$nodes=@([TechMaster.DefaultsNative]::Devices())
Assert ($nodes.Count -gt 10 -and @($nodes | Where-Object {$_.Present -and $_.InstanceId}).Count -gt 5 -and @($nodes | Where-Object {$_.ContainerId -match '^[0-9a-f]{8}-'}).Count -gt 0 -and @($nodes | Where-Object {$_.Class}).Count -gt 0) 'Native device listing reads instance IDs, presence, classes and containers'
$refused=$false;try{[void][TechMaster.DefaultsNative]::RemovePhantomDevice('HTREE\ROOT\0')}catch{$refused=$_.Exception.GetBaseException().Message -match 'connected'}
Assert $refused 'Removal refuses a connected device (root device node), so only disconnected nodes can be removed'
Assert (-not [TechMaster.DefaultsNative]::RemovePhantomDevice('ROOT\TECHMASTER_TEST_ABSENT\0000')) 'A device node that does not exist is reported as already gone'
$refused=$false;try{[void][TechMaster.DefaultsNative]::RemovePhantomDevice('')}catch{$refused=$true}
Assert $refused 'An empty device ID (which would locate the root) is rejected'
$view=New-DeployDefaultsWindow $null 'Cleanup'
$originalWorker=${function:Start-DeployWork}
$originalConfirm=${function:Confirm-Box}
try{
    $apps=@([pscustomobject]@{Name='Browser';Scope='Machine';Display='Browser';Http='WebHTTP';Https='WebHTTPS';Pdf='WebPDF'},[pscustomobject]@{Name='Reader';Scope='User';Display='Reader';Http='';Https='';Pdf='ReaderPDF'})
    $offline=@([pscustomobject]@{Name='USB old';Kind='USB';PortName='USB002';Selected=$true;IsDefault=$false;Shared=$false;JobCount=0;Detail='USB · cổng USB002'},[pscustomobject]@{Name='Network off';Kind='Network';PortName='IP_10.0.0.9';Selected=$false;IsDefault=$false;Shared=$false;JobCount=0;Detail='Mạng · cổng IP_10.0.0.9'},[pscustomobject]@{Key='device:c9';Name='Ghost LBP';Kind='Device';PortName='USB009';Selected=$true;IsDefault=$false;Shared=$false;JobCount=0;Detail='Thiết bị còn sót'})
    $snapshot=[pscustomobject]@{User='TEST';Printers=@([pscustomobject]@{Name='Printer A'});DefaultPrinter='Printer A';Management=$null;PrinterError='';OfflinePrinters=$offline;OfflineError='';Apps=$apps;AppError='';Associations=@{http=[pscustomobject]@{Readable=$true;ProgId='WebHTTP'};https=[pscustomobject]@{Readable=$true;ProgId='WebHTTPS'};'.pdf'=[pscustomobject]@{Readable=$true;ProgId='ReaderPDF'}}}
    Set-DeployDefaultsView $view $snapshot
    Assert ($view.FindName('Printer').SelectedItem.Name -ceq 'Printer A' -and $view.FindName('Browser').SelectedItem.Name -ceq 'Browser' -and $view.FindName('Pdf').SelectedItem.Name -ceq 'Reader') 'Installed defaults are selected from effective associations'
    $boxes=@($view.Tag.CleanupBoxes)
    Assert ($boxes.Count -eq 3 -and $view.FindName('CleanupItems').Children.Count -eq 3 -and $boxes[0].IsChecked -eq $true -and $boxes[1].IsChecked -eq $false -and $boxes[2].IsChecked -eq $true -and $view.FindName('RemoveOffline').IsEnabled) 'Offline printers and leftover devices are listed; USB and leftovers preselected, network unticked'
    Assert ($view.FindName('CleanupCurrent').Text -match '2 máy in' -and $view.FindName('CleanupCurrent').Text -match '1 thiết bị máy in còn sót') 'Cleanup summary counts offline queues and leftover devices separately'
    Assert ($view.FindName('CleanupRestartSpooler').IsChecked -eq $true -and $view.FindName('CleanupProgress').Visibility -eq 'Collapsed') 'Spooler fallback is on by default and the progress area stays hidden until removal'
    # Each main-window entry shows only its own part: printer cleanup is never mixed with default apps.
    $expectedCards=@{Printer=@('PrinterCard');Cleanup=@('CleanupCard');Apps=@('AppsCard','PdfCard','AppsNote')}
    $titles=@{Printer='Máy in mặc định và khổ A4';Cleanup='Dọn máy in không kết nối';Apps='Trình duyệt và PDF mặc định'}
    foreach($mode in 'Printer','Cleanup','Apps'){
        $modeView=if($mode -eq 'Cleanup'){$view}else{New-DeployDefaultsWindow $null $mode}
        try{
            if($modeView -ne $view){Set-DeployDefaultsView $modeView $snapshot}
            $shown=@('PrinterCard','CleanupCard','AppsCard','PdfCard','AppsNote' | Where-Object {$modeView.FindName($_).Visibility -eq 'Visible'})
            Assert (($shown -join ',') -ceq ($expectedCards[$mode] -join ',') -and $modeView.Title -ceq $titles[$mode] -and $modeView.FindName('Heading').Text -ceq $titles[$mode]) "$mode opens with only its own part and title ($($shown -join ','))"
            Assert (($modeView.FindName('DefaultsSettings').Visibility -eq 'Visible') -eq ($mode -eq 'Apps')) "$mode shows the Windows default-apps button only for browser / PDF"
            Assert (($modeView.FindName('Account').Text -match 'cả máy này') -eq ($mode -eq 'Cleanup')) "$mode explains whether it changes this account or the whole computer"
            foreach($scale in 1.0,1.5){
                $size=[Windows.Size]::new((1024/$scale),(768/$scale))
                $modeView.Content.Measure($size);$modeView.Content.Arrange([Windows.Rect]::new($size));$modeView.UpdateLayout()
                $visible=switch($mode){Printer{@('ApplyPrinter','PrinterSettings')}Cleanup{@('RemoveOffline','CleanupItems','CleanupAll')}Apps{@('OpenBrowser','OpenPdf')}}
                $hidden=switch($mode){Printer{@('RemoveOffline','OpenBrowser')}Cleanup{@('ApplyPrinter','OpenBrowser','OpenPdf')}Apps{@('ApplyPrinter','RemoveOffline')}}
                Assert (@($visible | Where-Object {$modeView.FindName($_).ActualHeight -le 0}).Count -eq 0 -and @($hidden | Where-Object {$modeView.FindName($_).ActualHeight -gt 0}).Count -eq 0 -and $modeView.FindName('Refresh').ActualHeight -gt 0) "$mode lays out its own actions and none of the others at $scale"
            }
        }finally{if($modeView -ne $view){$modeView.Close();$modeView.Tag.Timer.Stop()}}
    }
    Assert ((Test-DeployDefaultsReadProblem 'Cleanup' ([pscustomobject]@{PrinterError='';OfflineError='';OfflineDeviceError='';AppError='no apps';Associations=@{}})) -eq $false -and (Test-DeployDefaultsReadProblem 'Apps' ([pscustomobject]@{PrinterError='';OfflineError='';OfflineDeviceError='';AppError='no apps';Associations=@{}})) -eq $true -and (Test-DeployDefaultsReadProblem 'Printer' ([pscustomobject]@{PrinterError='spooler';AppError='';Associations=@{}})) -eq $true) 'Only problems of the part on screen are reported'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
        Assert ($view.FindName('Refresh').ActualHeight -gt 0 -and $view.FindName('Close').ActualWidth -gt 0) "Footer actions remain laid out at $scale"
        Assert ($view.FindName('RemoveOffline').ActualHeight -gt 0 -and $view.FindName('CleanupItems').ActualHeight -gt 0 -and $view.FindName('ApplyPrinter').ActualHeight -eq 0) "Offline printer list and remove action are laid out at $scale, nothing else"
        Assert ($view.FindName('Printer').Parent.CornerRadius.TopLeft -gt 0 -and $view.FindName('Pdf').Parent.CornerRadius.TopLeft -gt 0) 'Printer/PDF selectors use rounded shared controls'
    }
    function Start-DeployWork([string]$code,[object[]]$arguments){$script:capturedDefaults=@{Code=$code;Args=$arguments};@{Async=[pscustomobject]@{IsCompleted=$false}}}
    foreach($button in 'ApplyPrinter','OpenBrowser','OpenPdf','Refresh'){
        $view.FindName($button).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($view.Tag.Job -and -not $view.FindName('Choices').IsEnabled -and -not $view.FindName('Close').IsEnabled) "$button starts background work and locks mutation controls"
        $expected=switch($button){ApplyPrinter{'Printer'}OpenBrowser{'Browser'}OpenPdf{'Pdf'}Refresh{'Inspect'}}
        Assert ($script:capturedDefaults.Args[1] -ceq $expected) "$button routes to the right operation"
        if($button -eq 'ApplyPrinter'){Assert ($script:capturedDefaults.Args[2] -ceq 'Printer A' -and $script:capturedDefaults.Args[3] -eq $true -and $script:capturedDefaults.Args[4] -eq $true) 'Only selected printer and selected checkboxes are passed to worker'}
        $view.Tag.Timer.Stop();$view.Tag.Job=$null;$view.FindName('Choices').IsEnabled=$true
        foreach($name in 'Close','Refresh','DefaultsSettings'){$view.FindName($name).IsEnabled=$true}
    }
    function Confirm-Box([string]$message,[string]$title='Xác nhận',[string]$ConfirmText='Xác nhận',[string]$CancelText='Huỷ',[switch]$Danger,$Owner=$null){$script:cleanupPrompt=$message;$script:cleanupDanger=[bool]$Danger;$script:cleanupAnswer}
    $script:cleanupAnswer=$false;$script:capturedDefaults=$null
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (-not $view.Tag.Job -and $null -eq $script:capturedDefaults -and $script:cleanupPrompt -match 'USB old' -and $script:cleanupPrompt -match 'Ghost LBP' -and -not ($script:cleanupPrompt -match 'Network off') -and $script:cleanupPrompt -match 'Print Spooler' -and $script:cleanupDanger) 'Cancelled confirmation lists only ticked entries and removes nothing'
    Assert ($view.FindName('CleanupProgress').Visibility -eq 'Collapsed') 'Cancelling does not show progress'
    $script:cleanupAnswer=$true
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $sent=@($script:capturedDefaults.Args[6]);$progress=$script:capturedDefaults.Args[7]
    Assert ($view.Tag.Job -and $script:capturedDefaults.Args[1] -ceq 'Cleanup' -and $sent.Count -eq 2 -and $sent[0] -ceq 'USB old' -and $sent[1] -ceq 'device:c9' -and -not $view.FindName('Choices').IsEnabled) 'Confirmed removal sends the ticked queue names and device keys to the worker and locks the window'
    Assert ($progress -is [hashtable] -and $progress.IsSynchronized -and $progress.Total -eq 2 -and $script:capturedDefaults.Args[8] -eq $true -and $view.FindName('CleanupProgress').Visibility -eq 'Visible' -and $view.FindName('CleanupStatus').Text -match 'Đang chuẩn bị gỡ 2') 'Removal shows progress inside the card and passes the spooler option'
    $progress.Index=1;$progress.Current='USB old';$progress.Step='xoá thiết bị';$progress.Percent=40
    [void]$progress.Lines.Add('✓ USB old — đã xoá hàng đợi và 2 mục thiết bị');[void]$progress.Lines.Add('– Ghost LBP — bỏ qua: thiết bị đang kết nối')
    Update-DeployCleanupProgressView $view
    Update-DeployCleanupProgressView $view
    Assert ($view.FindName('CleanupStatus').Text -match 'Đang gỡ 1/2: USB old' -and $view.FindName('CleanupBar').Value -eq 40 -and ($view.FindName('CleanupLog').Text -split "`n").Count -eq 2 -and $view.FindName('CleanupLog').Text -match 'Ghost LBP') 'Live progress shows the current printer, step and each result line once'
    $view.Tag.Timer.Stop();$view.Tag.Job=$null;$view.Tag.Progress=$null;$view.FindName('Choices').IsEnabled=$true
    foreach($name in 'Close','Refresh','DefaultsSettings'){$view.FindName($name).IsEnabled=$true}
    $view.FindName('CleanupRestartSpooler').IsChecked=$false
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($script:capturedDefaults.Args[8] -eq $false -and -not ($script:cleanupPrompt -match 'Print Spooler')) 'Unticking the spooler option is honoured'
    $view.Tag.Timer.Stop();$view.Tag.Job=$null;$view.Tag.Progress=$null;$view.FindName('Choices').IsEnabled=$true
    foreach($name in 'Close','Refresh','DefaultsSettings'){$view.FindName($name).IsEnabled=$true}
    $view.FindName('CleanupAll').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (@($view.Tag.CleanupBoxes | Where-Object {$_.IsChecked -eq $true}).Count -eq 3) 'Select all ticks every entry'
    $view.FindName('CleanupNone').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $script:capturedDefaults=$null
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (-not $view.Tag.Job -and $null -eq $script:capturedDefaults) 'Nothing ticked starts no removal'
    Set-DeployDefaultsView $view $snapshot
    Assert (@($view.Tag.CleanupBoxes | Where-Object {$_.IsChecked -eq $true}).Count -eq 0 -and @($view.Tag.CleanupBoxes).Count -eq 3) 'Refresh keeps the ticks chosen by the user'
    $snapshot.OfflinePrinters=@()
    $snapshot.Printers=@();$snapshot.Apps=@();Set-DeployDefaultsView $view $snapshot
    Assert (-not $view.FindName('ApplyPrinter').IsEnabled -and -not $view.FindName('OpenBrowser').IsEnabled -and -not $view.FindName('OpenPdf').IsEnabled) 'Missing queues/apps disable their actions'
    Assert (-not $view.FindName('RemoveOffline').IsEnabled -and -not $view.FindName('CleanupAll').IsEnabled -and $view.FindName('CleanupItems').Children.Count -eq 0) 'No offline printers disables cleanup actions'
}finally{Set-Item Function:Start-DeployWork $originalWorker;Set-Item Function:Confirm-Box $originalConfirm;$view.Tag.Job=$null;$view.Close();$view.Tag.Timer.Stop()}
Write-Host "PASS: $checks native defaults UI assertions; layout, rounded selectors, actual button routing, offline printer cleanup and safe worker arguments."
