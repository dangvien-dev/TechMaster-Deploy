# Native Windows-only WPF validation. ValidateOnly never elevates, scans or installs.
$ErrorActionPreference='Stop'
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++}
$view=. (Join-Path $PSScriptRoot 'DriverFix.ps1') -ValidateOnly
Assert ($view -is [Windows.Window]) 'Fix Driver loads as a native WPF window'
foreach($name in 'Devices','DeviceDetails','CatalogLinks','Scan','Rescan','CopyIds','InstallCab','InstallFolder','Repository','ProfileDetails','PowerChoices','ApplyPower','Disable','Report','OpenLogs','OpenProfiles','Cancel','Close','Help'){
    Assert ($null -ne $view.FindName($name)) "$name is bound"
}
Assert (-not $script:driverFix.Session -and -not $script:driverFix.Work -and -not $driverTimer.IsEnabled) 'ValidateOnly does not scan, elevate or start native commands'
$d=[pscustomobject]@{Name='Thiết bị thử';ErrorCode=28;Description='Chưa có driver';HardwareIds=@('PCI\VEN_8086&DEV_51C8&SUBSYS_72708086','PCI\VEN_8086&DEV_51C8');InstanceId='PCI\TEST\A';PnpClass='MEDIA';Service=''}
$snapshot=[pscustomobject]@{Problems=@($d);All=@($d);Time='test'}
$script:driverFix.Session=[pscustomobject]@{Machine=[pscustomobject]@{ComputerName='UI-TEST';Manufacturer='Any OEM';Model='Any main';Bios='1.0'};Current=$snapshot;Profile=$null;MatchedCount=0;Profiles=[pscustomobject]@{Errors=@()}}
Update-DriverFixView
Assert ($view.FindName('Devices').Items.Count -eq 1 -and $view.FindName('DeviceDetails').Text.Contains('PCI\TEST\A')) 'Generic machine displays inventory without a profile'
Assert ($view.FindName('CatalogLinks').Items.Count -eq 2 -and $view.FindName('DeviceDetails').Text.Contains($d.HardwareIds[1])) 'All IDs and Catalog links are available'
Assert (-not $view.FindName('Disable').IsEnabled -and -not $view.FindName('ApplyPower').IsEnabled) 'Unmatched profile does not enable model-specific modifications'
foreach($size in @([Windows.Size]::new(1100,780),[Windows.Size]::new(760,540))){
    $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
    Assert ($view.FindName('Devices').ActualWidth -gt 400 -and $view.FindName('Close').ActualHeight -gt 0) "Inventory and footer lay out at $size"
}
$profile=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json
$script:driverFix.Session.Profile=$profile;$script:driverFix.Session.MatchedCount=1
Update-DriverFixView
Assert ($view.FindName('PowerChoices').Children.Count -eq 4 -and @($script:driverFix.PowerBoxes|Where-Object IsChecked).Count -eq 0) 'All profile power settings start unchecked'
Set-DriverFixBusy $true
Assert (-not $view.FindName('InstallControls').IsEnabled -and -not $view.FindName('Close').IsEnabled) 'Busy state blocks parallel installs and closing'
Set-DriverFixBusy $false
Assert ($view.FindName('InstallControls').IsEnabled -and $view.FindName('ApplyPower').IsEnabled) 'Controls recover after worker completion'
$view.Close();$driverTimer.Stop()
Write-Host "PASS: $checks native Fix Driver WPF assertions; no system changes."
