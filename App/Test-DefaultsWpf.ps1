# Native WPF controller/layout tests. Worker startup is intercepted; never changes printers/default apps.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Defaults.Core.ps1')
. (Join-Path $PSScriptRoot 'Defaults.UI.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
Initialize-DeployDefaultsNative
Assert ([bool]('TechMaster.DefaultsNative' -as [type])) 'Native printer/default-association interop compiles on Windows PowerShell'
$view=New-DeployDefaultsWindow
$originalWorker=${function:Start-DeployWork}
$originalConfirm=${function:Confirm-Box}
try{
    $apps=@([pscustomobject]@{Name='Browser';Scope='Machine';Display='Browser';Http='WebHTTP';Https='WebHTTPS';Pdf='WebPDF'},[pscustomobject]@{Name='Reader';Scope='User';Display='Reader';Http='';Https='';Pdf='ReaderPDF'})
    $offline=@([pscustomobject]@{Name='USB old';Kind='USB';PortName='USB002';Selected=$true;IsDefault=$false;Shared=$false;JobCount=0;Detail='USB · cổng USB002'},[pscustomobject]@{Name='Network off';Kind='Network';PortName='IP_10.0.0.9';Selected=$false;IsDefault=$false;Shared=$false;JobCount=0;Detail='Mạng · cổng IP_10.0.0.9'})
    $snapshot=[pscustomobject]@{User='TEST';Printers=@([pscustomobject]@{Name='Printer A'});DefaultPrinter='Printer A';Management=$null;PrinterError='';OfflinePrinters=$offline;OfflineError='';Apps=$apps;AppError='';Associations=@{http=[pscustomobject]@{Readable=$true;ProgId='WebHTTP'};https=[pscustomobject]@{Readable=$true;ProgId='WebHTTPS'};'.pdf'=[pscustomobject]@{Readable=$true;ProgId='ReaderPDF'}}}
    Set-DeployDefaultsView $view $snapshot
    Assert ($view.FindName('Printer').SelectedItem.Name -ceq 'Printer A' -and $view.FindName('Browser').SelectedItem.Name -ceq 'Browser' -and $view.FindName('Pdf').SelectedItem.Name -ceq 'Reader') 'Installed defaults are selected from effective associations'
    $boxes=@($view.Tag.CleanupBoxes)
    Assert ($boxes.Count -eq 2 -and $view.FindName('CleanupItems').Children.Count -eq 2 -and $boxes[0].IsChecked -eq $true -and $boxes[1].IsChecked -eq $false -and $view.FindName('RemoveOffline').IsEnabled) 'Offline printers are listed with USB preselected and network unticked'
    Assert ($view.FindName('CleanupCurrent').Text -match '2 máy in') 'Cleanup summary counts offline printers'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
        Assert ($view.FindName('Refresh').ActualHeight -gt 0 -and $view.FindName('Close').ActualWidth -gt 0) "Footer actions remain laid out at $scale"
        Assert ($view.FindName('RemoveOffline').ActualHeight -gt 0 -and $view.FindName('CleanupItems').ActualHeight -gt 0) "Offline printer list and remove action are laid out at $scale"
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
    Assert (-not $view.Tag.Job -and $null -eq $script:capturedDefaults -and $script:cleanupPrompt -match 'USB old' -and -not ($script:cleanupPrompt -match 'Network off') -and $script:cleanupDanger) 'Cancelled confirmation lists only ticked printers and removes nothing'
    $script:cleanupAnswer=$true
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $sent=@($script:capturedDefaults.Args[6])
    Assert ($view.Tag.Job -and $script:capturedDefaults.Args[1] -ceq 'Cleanup' -and $sent.Count -eq 1 -and $sent[0] -ceq 'USB old' -and -not $view.FindName('Choices').IsEnabled) 'Confirmed removal sends only ticked printers to the worker and locks the window'
    $view.Tag.Timer.Stop();$view.Tag.Job=$null;$view.FindName('Choices').IsEnabled=$true
    foreach($name in 'Close','Refresh','DefaultsSettings'){$view.FindName($name).IsEnabled=$true}
    $view.FindName('CleanupAll').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (@($view.Tag.CleanupBoxes | Where-Object {$_.IsChecked -eq $true}).Count -eq 2) 'Select all ticks every offline printer'
    $view.FindName('CleanupNone').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $script:capturedDefaults=$null
    $view.FindName('RemoveOffline').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (-not $view.Tag.Job -and $null -eq $script:capturedDefaults) 'Nothing ticked starts no removal'
    Set-DeployDefaultsView $view $snapshot
    Assert (@($view.Tag.CleanupBoxes | Where-Object {$_.IsChecked -eq $true}).Count -eq 0 -and @($view.Tag.CleanupBoxes).Count -eq 2) 'Refresh keeps the ticks chosen by the user'
    $snapshot.OfflinePrinters=@()
    $snapshot.Printers=@();$snapshot.Apps=@();Set-DeployDefaultsView $view $snapshot
    Assert (-not $view.FindName('ApplyPrinter').IsEnabled -and -not $view.FindName('OpenBrowser').IsEnabled -and -not $view.FindName('OpenPdf').IsEnabled) 'Missing queues/apps disable their actions'
    Assert (-not $view.FindName('RemoveOffline').IsEnabled -and -not $view.FindName('CleanupAll').IsEnabled -and $view.FindName('CleanupItems').Children.Count -eq 0) 'No offline printers disables cleanup actions'
}finally{Set-Item Function:Start-DeployWork $originalWorker;Set-Item Function:Confirm-Box $originalConfirm;$view.Tag.Job=$null;$view.Close();$view.Tag.Timer.Stop()}
Write-Host "PASS: $checks native defaults UI assertions; layout, rounded selectors, actual button routing, offline printer cleanup and safe worker arguments."
