# Windows-only native WPF load/layout smoke; never launches deployment actions.
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this native WPF smoke test on Windows, in STA.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Use powershell.exe -STA -File App/Test-Wpf.ps1.' }
$checks = 0
function Assert($condition, $message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
$main = . (Join-Path $PSScriptRoot 'TechMaster-Deploy.ps1') -ValidateOnly
Assert ($main -is [Windows.Window]) 'Main shell is a native WPF Window'
Assert ($main.FindName('Navigation').Items.Count -eq 8 -and $main.FindName('tabs').Items.Count -eq 8) 'All eight sections are present'
for ($i = 0; $i -lt 8; $i++) {
    $main.FindName('Navigation').SelectedIndex = $i
    Assert ($main.FindName('tabs').SelectedIndex -eq $i) "Navigation $i selects its content"
}
foreach ($scale in 1.0,1.25,1.5) {
    $size = New-Object Windows.Size((1366 / $scale), (768 / $scale))
    $main.Content.Measure($size); $main.Content.Arrange((New-Object Windows.Rect($size))); $main.UpdateLayout()
    Assert ($main.FindName('headerUpdate').ActualHeight -gt 0 -and $main.FindName('headerUpdate').ActualHeight -eq $main.FindName('btnRefresh').ActualHeight) "Aligned header button height at scale $scale"
    foreach ($button in 'btnFormat','btnKeyboard','btnExport','bDl','btnWindowsIso','btnBasicAppInstall','checkUpdate') {
        Assert ($null -ne $main.FindName($button)) "$button exists at scale $scale"
    }
}
$selected = Get-OffSel
Assert ($selected.Id -eq 'HomeBusiness2024Retail' -and $selected.Arch -eq '64' -and $selected.Langs.Count -eq 2) 'Office defaults preserved'
$rb32.IsChecked = $true
Assert ((Get-OffSel).Arch -eq '32') 'WPF architecture choice reaches Office selection'
$languageChoices[0].IsChecked = $false
Assert (((Get-OffSel).Langs -join ',') -eq 'en-us') 'WPF language selection reaches Office options'
Assert ($basicAppChoices.Count -eq 11) 'All existing basic apps retained'
foreach ($node in $markup.SelectNodes('//*[@x:Name and not(ancestor::*[local-name()="ControlTemplate"])]', $ns)) {
    $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    Assert ($null -ne $main.FindName($name)) "XAML control $name resolves"
}
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
$precheck.Close(); $updater.Close(); $main.Close()
Write-Host "PASS: $checks native WPF assertions; eight tabs, control binding, layout, Office defaults and updater states."
