# Windows process/timer regression. Only HTTP transport is replaced by a local fixture.
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Write-Host 'SKIP: native notification process test requires Windows.';return}
$main=. (Join-Path $PSScriptRoot 'TechMaster-Deploy.ps1') -ValidateOnly
$temp=Join-Path ([IO.Path]::GetTempPath()) ("tm-probe-O'Brien-"+[guid]::NewGuid().ToString('N'))
$script:probeTestTimer=$null
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    [IO.File]::WriteAllText((Join-Path $temp 'version.txt'),'2.1.5.0')
    foreach($file in 'Update.Core.ps1','Update.Notification.Core.ps1','Update.Notifications.UI.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $temp}
    $worker=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Update.Notification.ps1'))
    $worker=$worker.Replace('Write-DeployJson (Get-DeployUpdateAvailability', "function Get-DeployNotificationVersion { [version]'9.0.0.0' }`r`nWrite-DeployJson (Get-DeployUpdateAvailability")
    [IO.File]::WriteAllText((Join-Path $temp 'Update.Notification.ps1'),$worker,[Text.UTF8Encoding]::new($true))
    . (Join-Path $temp 'Update.Notifications.UI.ps1')
    $Root=$temp
    $frame=[Windows.Threading.DispatcherFrame]::new();$deadline=[DateTime]::UtcNow.AddSeconds(25)
    $script:probeTestTimer=New-DeployTimer 50 {
        if($UpdateBadge.Visibility -eq 'Visible' -or [DateTime]::UtcNow -gt $deadline){$frame.Continue=$false}
    }
    $script:probeTestTimer.Start();Start-DeployUpdateNotifications
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    if($UpdateBadge.Visibility -ne 'Visible' -or $headerUpdate.ToolTip -notmatch '9.0.0.0'){throw 'The actual notification child process and timer failed to light the header badge.'}
    if($script:updateProbe){throw 'A completed child process was not cleaned up.'}
    Write-Host 'PASS: real hidden notification worker, apostrophe in path, JSON handoff and dispatcher timer show the red badge without opening updater.'
}finally{
    if($script:probeTestTimer){$script:probeTestTimer.Stop()};$availabilityTimer.Stop();Stop-DeployUpdateProbe;$main.Close()
    if(Test-Path $temp){Remove-Item $temp -Recurse -Force}
}
