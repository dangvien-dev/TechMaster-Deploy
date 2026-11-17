$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Deploy.Actions.ps1')
$checks=0
function Assert($condition,$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Confirm-Box { $true }
function Set-Status($message) { $script:lastStatus=$message }
function Start-Process($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru) {
    $script:launch=@{File=$FilePath;Args=$ArgumentList;Style=$WindowStyle;Directory=$WorkingDirectory}
    return [pscustomobject]@{Handle=1}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-wpf-actions-'+[guid]::NewGuid().ToString('N'))
$saved=$env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA=$temp; $DirOffice=Join-Path $temp 'Office';$KhoOffice=Join-Path $temp 'KhoOffice'
    $cbProduct=[pscustomobject]@{SelectedIndex=0};$rb32=[pscustomobject]@{IsChecked=$false}
    $languageChoices=@([pscustomobject]@{Tag='en-us';IsChecked=$true},[pscustomobject]@{Tag='vi-vn';IsChecked=$false})
    $excludeChoices=@([pscustomobject]@{Tag='Teams';IsChecked=$true})
    $tbOffKey=[pscustomobject]@{Text='AAAAA-BBBBB-CCCCC-DDDDD-EEEEE'};$chkMsi=[pscustomobject]@{IsChecked=$true}
    $officeBar=[pscustomobject]@{IsIndeterminate=$false;Value=0}
    $lblOfficeProgress=[pscustomobject]@{Text='';Foreground=''}
    $cPrimary='#10223F'; $cDanger='#B91C1C'
    foreach ($name in 'bDl','bKho','bNet','bCleanup','bOfficeLog') { Set-Variable -Name $name -Value ([pscustomobject]@{IsEnabled=$true}) }
    $officeTimer=[pscustomobject]@{Active=$false};$officeTimer | Add-Member ScriptMethod Start {$this.Active=$true}
    $script:officeRun=$null
    $selection=Get-OffSel
    Assert ($selection.Arch -eq '64' -and $selection.Langs.Count -eq 1 -and $selection.Excl[0] -eq 'Teams') 'WPF checkbox states become Office options'
    Start-ODT 'Download'
    Assert ($script:launch.Args -match '-Mode Download' -and $script:launch.Args -match '-Languages en-us') 'Download keeps product and selected language'
    Assert ($script:launch.Args -notmatch 'PidKey|RemoveMSI') 'Downloading does not pass activation key or MSI removal'
    Assert ($script:launch.Style -eq 'Hidden' -and $officeBar.IsIndeterminate -and -not $bDl.IsEnabled) 'Office process runs without a console and locks launch actions'
    $script:officeRun=$null
    Start-ODT 'Install'
    Assert ($script:launch.Args -match '-PidKey AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' -and $script:launch.Args -match '-RemoveMSI') 'Explicit install keeps key and MSI-removal selection'
    Assert ($script:officeRun.Mode -eq 'Install' -and $officeTimer.Active) 'Install is tracked by the WPF timer'
} finally { $env:LOCALAPPDATA=$saved; if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
Write-Host "PASS: $checks WPF Office action assertions; selected options, hidden launch, download/install separation and UI locking."
