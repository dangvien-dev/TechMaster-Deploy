$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Update.Notification.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Get-DeployVersion{[version]'2.1.2.0'}
function Read-DeployManifest{[pscustomobject]@{source=[pscustomobject]@{commit=('a'*40)}}}
function Get-DeployOnlineRelease{if($script:fail){throw 'offline'};return $script:release}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-notify-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    $script:fail=$false;$script:release=[pscustomobject]@{unchanged=$false;version='2.1.3.0';commit=('b'*40)}
    $result=Get-DeployUpdateAvailability $temp
    Assert ($result.Success -and $result.Available) 'Newer release is advertised without downloading a payload'
    $script:release.version='2.1.2.0';$result=Get-DeployUpdateAvailability $temp
    Assert (-not $result.Available) 'Same version without an installed revision is not advertised'
    [IO.File]::WriteAllText((Join-Path $temp 'update-package.json'),'fixture')
    $result=Get-DeployUpdateAvailability $temp
    Assert ($result.Available) 'A new commit at the same version is offered when the installed commit is known'
    $script:release.unchanged=$true;$result=Get-DeployUpdateAvailability $temp
    Assert ($result.Success -and -not $result.Available) 'An unchanged revision clears availability'
    $script:fail=$true;$result=Get-DeployUpdateAvailability $temp
    Assert (-not $result.Success) 'Network failure is distinct from already up to date'
    function New-DeployTimer{[pscustomobject]@{}}
    . (Join-Path $PSScriptRoot 'Update.Notifications.UI.ps1')
    $UpdateBadge=[pscustomobject]@{Visibility='Collapsed'};$headerUpdate=[pscustomobject]@{ToolTip=''}
    Set-DeployUpdateAvailability $true '9.0.0.0'
    Assert ($UpdateBadge.Visibility -eq 'Visible' -and $headerUpdate.ToolTip -match '9.0.0.0') 'Available result enables the badge without a dialog'
    $dir=Join-Path $temp 'owned-probe';New-Item -ItemType Directory -Path $dir|Out-Null
    $process=[pscustomobject]@{HasExited=$false;Killed=$false;Disposed=$false}
    $process|Add-Member ScriptMethod Kill {$this.Killed=$true;$this.HasExited=$true}
    $process|Add-Member ScriptMethod WaitForExit {param($timeout)return $true}
    $process|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    $script:updateProbe=@{Process=$process;Directory=$dir}
    Stop-DeployUpdateProbe
    Assert ($process.Killed -and $process.Disposed -and -not (Test-Path $dir) -and -not $script:updateProbe) 'Closing/updating cleans up only its dedicated read-only probe'

}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks read-only update notification assertions; newer/same revision and offline behavior."
