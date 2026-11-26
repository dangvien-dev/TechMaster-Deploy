# Native Windows-only WPF validation. ValidateOnly never elevates, scans or installs.
$ErrorActionPreference='Stop'
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++}
$view=. (Join-Path $PSScriptRoot 'DriverFix.ps1') -ValidateOnly
Assert ($view -is [Windows.Window]) 'Fix Driver loads as a native WPF window'
foreach($name in 'ShowAll','DeviceManager','Devices','DeviceDetails','CatalogLinks','LinkHint','VendorDriver','Scan','Rescan','CopyIds','InstallCab','InstallFolder','Repository','ProfileDetails','PowerChoices','ApplyPower','Disable','Report','OpenLogs','OpenProfiles','Cancel','Close','Help'){
    Assert ($null -ne $view.FindName($name)) "$name is bound"
}
Assert (-not $script:driverFix.Session -and -not $script:driverFix.Work -and -not $driverTimer.IsEnabled) 'ValidateOnly does not scan, elevate or start native commands'
$d=[pscustomobject]@{Name='Thiết bị thử';ErrorCode=28;ErrorCodeText='28';Description='Chưa có driver';HardwareIds=@('PCI\VEN_8086&DEV_51C8&SUBSYS_72708086','PCI\VEN_8086&DEV_51C8');InstanceId='PCI\TEST\A';PnpClass='MEDIA';Service=''}
$snapshot=[pscustomobject]@{Problems=@($d);All=@($d);Time='test'}
$script:driverFix.Session=[pscustomobject]@{Machine=[pscustomobject]@{ComputerName='UI-TEST';Manufacturer='Any OEM';Model='Any main';Bios='1.0'};Current=$snapshot;Profile=$null;MatchedCount=0;Profiles=[pscustomobject]@{Errors=@()}}
Update-DriverFixView
Assert ($view.FindName('Devices').Items.Count -eq 1 -and $view.FindName('DeviceDetails').Text.Contains('PCI\TEST\A')) 'Generic machine displays inventory without a profile'
Assert ($view.FindName('CatalogLinks').Items.Count -eq 2 -and $view.FindName('DeviceDetails').Text.Contains($d.HardwareIds[1])) 'All IDs and Catalog links are available'
Assert (-not $view.FindName('Disable').IsEnabled -and -not $view.FindName('ApplyPower').IsEnabled) 'Unmatched profile does not enable model-specific modifications'
Assert (-not $view.FindName('VendorDriver').IsEnabled -and $view.FindName('LinkHint').Visibility -eq 'Collapsed' -and @($view.FindName('CatalogLinks').Items|Where-Object Kind -ne 'Catalog').Count -eq 0) 'A non-printer device keeps Catalog links and has no maker button or hint'
$printer=[pscustomobject]@{Name='MF240 Series UFRII LT';ErrorCode=28;ErrorCodeText='28';Description='Chưa có driver';HardwareIds=@('USB\VID_04A9&PID_27D2&REV_0100&MI_00','USB\VID_04A9&PID_27D2&MI_00');CompatibleIds=@();InstanceId='USB\VID_04A9&PID_27D2&MI_00\6&34C0488&0&0000';PnpClass='';Service=''}
$snapshot.All=@($d,$printer);$snapshot.Problems=@($d,$printer)
Update-DriverFixView
$view.FindName('Devices').SelectedItem=$printer
$vendorButton=$view.FindName('VendorDriver')
Assert ($vendorButton.IsEnabled -and $vendorButton.Content -ceq 'Mở trang driver Canon' -and ([string]$vendorButton.Tag) -match '^https://www\.google\.com/search\?hl=vi&q=' -and $view.FindName('LinkHint').Visibility -eq 'Visible') 'A Canon printer enables the maker button and shows the hint'
Assert ($view.FindName('CatalogLinks').Items.Count -eq 2 -and @($view.FindName('CatalogLinks').Items|Where-Object Kind -ne 'Vendor').Count -eq 0 -and (Test-DriverFixAllowedLink ([string]$vendorButton.Tag))) 'A printer lists maker links, not VID/PID Catalog links, and the button target is openable'
foreach($size in @([Windows.Size]::new(1100,780),[Windows.Size]::new(760,540))){
    $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
    Assert ($view.FindName('Devices').ActualWidth -gt 400 -and $view.FindName('Close').ActualHeight -gt 0 -and $view.FindName('LinkHint').ActualHeight -gt 0 -and $vendorButton.ActualHeight -gt 0) "Inventory, maker hint and footer lay out at $size"
}
$snapshot.All=@($d);$snapshot.Problems=@($d)
Update-DriverFixView
Assert (-not $vendorButton.IsEnabled -and $view.FindName('LinkHint').Visibility -eq 'Collapsed') 'Selecting a non-printer again disables the maker button'
$profile=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json
$script:driverFix.Session.Profile=$profile;$script:driverFix.Session.MatchedCount=1
Update-DriverFixView
Assert ($view.FindName('PowerChoices').Children.Count -eq 4 -and @($script:driverFix.PowerBoxes|Where-Object IsChecked).Count -eq 0) 'All profile power settings start unchecked'
$healthy=$d.PSObject.Copy();$healthy.InstanceId='HEALTHY';$healthy.ErrorCode=0;$healthy.ErrorCodeText='0';$healthy.HardwareIds=@('INTELAUDIO\CTLR_DEV_51C8&LINKTYPE_06&DEVTYPE_06&VEN_8086&DEV_AE50')
$unknown=$d.PSObject.Copy();$unknown.InstanceId='UNKNOWN';$unknown.ErrorCode=-1;$unknown.ErrorCodeText='?'
$snapshot.All=@($d,$healthy,$unknown);$snapshot.Problems=@($d,$unknown)
Update-DriverFixView
Assert ($view.FindName('Devices').Items.Count -eq 2 -and $view.FindName('MachineInfo').Text -match 'Đã đọc 3 thiết bị') 'Default filter includes problems/unknown and header shows actual read coverage'
$view.FindName('ShowAll').IsChecked=$true
Assert ($view.FindName('Devices').Items.Count -eq 3) 'Actual checkbox event reveals healthy devices'
$view.FindName('Devices').SelectedItem=$healthy
Assert (-not $view.FindName('Disable').IsEnabled) 'Showing all devices never enables profile disable for a healthy matching endpoint'
$view.FindName('Devices').SelectedItem=$unknown
Assert ($view.FindName('DeviceDetails').Text -match 'Code \?' -and -not $view.FindName('Disable').IsEnabled) 'Unknown status is shown as ? and cannot enable profile disable'
$view.FindName('ShowAll').IsChecked=$false
Assert ($view.FindName('Devices').Items.Count -eq 2) 'Toggling back restores problem-only view'
Set-DriverFixBusy $true
Assert (-not $view.FindName('InstallControls').IsEnabled -and -not $view.FindName('Close').IsEnabled) 'Busy state blocks parallel installs and closing'
Set-DriverFixBusy $false
Assert ($view.FindName('InstallControls').IsEnabled -and $view.FindName('ApplyPower').IsEnabled) 'Controls recover after worker completion'
$view.Close();$driverTimer.Stop()
Write-Host "PASS: $checks native Fix Driver WPF assertions; no system changes."
