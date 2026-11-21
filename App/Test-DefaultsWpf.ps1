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
try{
    $apps=@([pscustomobject]@{Name='Browser';Scope='Machine';Display='Browser';Http='WebHTTP';Https='WebHTTPS';Pdf='WebPDF'},[pscustomobject]@{Name='Reader';Scope='User';Display='Reader';Http='';Https='';Pdf='ReaderPDF'})
    $snapshot=[pscustomobject]@{User='TEST';Printers=@([pscustomobject]@{Name='Printer A'});DefaultPrinter='Printer A';Management=$null;PrinterError='';Apps=$apps;AppError='';Associations=@{http=[pscustomobject]@{Readable=$true;ProgId='WebHTTP'};https=[pscustomobject]@{Readable=$true;ProgId='WebHTTPS'};'.pdf'=[pscustomobject]@{Readable=$true;ProgId='ReaderPDF'}}}
    Set-DeployDefaultsView $view $snapshot
    Assert ($view.FindName('Printer').SelectedItem.Name -ceq 'Printer A' -and $view.FindName('Browser').SelectedItem.Name -ceq 'Browser' -and $view.FindName('Pdf').SelectedItem.Name -ceq 'Reader') 'Installed defaults are selected from effective associations'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
        Assert ($view.FindName('Refresh').ActualHeight -gt 0 -and $view.FindName('Close').ActualWidth -gt 0) "Footer actions remain laid out at $scale"
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
    $snapshot.Printers=@();$snapshot.Apps=@();Set-DeployDefaultsView $view $snapshot
    Assert (-not $view.FindName('ApplyPrinter').IsEnabled -and -not $view.FindName('OpenBrowser').IsEnabled -and -not $view.FindName('OpenPdf').IsEnabled) 'Missing queues/apps disable their actions'
}finally{Set-Item Function:Start-DeployWork $originalWorker;$view.Tag.Job=$null;$view.Close();$view.Tag.Timer.Stop()}
Write-Host "PASS: $checks native defaults UI assertions; layout, rounded selectors, actual button routing and safe worker arguments."
