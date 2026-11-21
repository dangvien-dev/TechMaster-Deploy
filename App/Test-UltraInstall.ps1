# File/cache transactions are real; network, installer and Windows registry/processes are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'UltraViewer.Install.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Reset-Fixture {
    $script:installed='';$script:running=$false;$script:downloads=0;$script:starts=0
    $script:signature='Valid';$script:publisher='CN=Duc Fabulous Co., Ltd';$script:version='6.6.133.0';$script:exit=0
}
function Get-DeployUltraInstalledVersion{$script:installed}
function Get-Process {if($script:running){[pscustomobject]@{Name='UltraViewer_Desktop'}}}
function Save-DeployUltraInstaller($path){$script:downloads++;[IO.File]::WriteAllText($path,'fixture only; never executable')}
function Get-AuthenticodeSignature {[pscustomobject]@{Status=$script:signature;SignerCertificate=[pscustomobject]@{Subject=$script:publisher}}}
function Get-DeployUltraInstallerInfo {[pscustomobject]@{ProductVersion=$script:version;FileVersion=$script:version}}
function Start-Process($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru){
    $script:starts++;$script:arguments=$ArgumentList;$script:installed='6.6.133'
    $process=[pscustomobject]@{ExitCode=$script:exit};$process|Add-Member ScriptMethod Dispose {};return $process
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-ultra-install-'+[guid]::NewGuid().ToString('N'))
$previous=$env:LOCALAPPDATA
try{
    Reset-Fixture
    $result=Install-DeployUltraViewer (Join-Path $temp 'fresh')
    Assert ($result.Group -eq 'Installed' -and $script:starts -eq 1 -and $script:downloads -eq 1) 'Fresh official install completes only after version readback'
    Assert ($script:arguments -match '/VERYSILENT' -and $script:arguments -match '/NORESTART' -and $result.Details -match 'SHA256:') 'Silent install suppresses reboot and records its verified payload hash'
    Reset-Fixture
    $result=Install-DeployUltraViewer (Join-Path $temp 'fresh')
    Assert ($script:downloads -eq 0 -and $script:starts -eq 1) 'A validated cached installer is reused'
    Reset-Fixture;$script:installed='6.6.133'
    $result=Install-DeployUltraViewer (Join-Path $temp 'existing')
    Assert ($result.Group -eq 'Skipped' -and $script:downloads -eq 0 -and $script:starts -eq 0) 'Existing install remains untouched'
    Reset-Fixture;$script:running=$true
    $result=Install-DeployUltraViewer (Join-Path $temp 'remote')
    Assert ($result.Group -eq 'Skipped' -and $script:starts -eq 0) 'A running remote session never starts an installer'
    foreach($case in 'signature','publisher','version'){
        Reset-Fixture
        switch($case){signature{$script:signature='NotSigned'}publisher{$script:publisher='CN=Other Vendor'}version{$script:version='6.6.124'}}
        $caught='';try{Install-DeployUltraViewer (Join-Path $temp $case)|Out-Null}catch{$caught=$_.Exception.Message}
        Assert ($caught -and $script:starts -eq 0) "Invalid $case is rejected before any installation"
        Assert (@(Get-ChildItem (Join-Path $temp $case) -Filter '*.download' -ErrorAction SilentlyContinue).Count -eq 0) "Invalid $case leaves no partial download"
    }
    Reset-Fixture;$script:exit=3010
    $result=Install-DeployUltraViewer (Join-Path $temp 'reboot')
    Assert ($result.Group -eq 'Restart') 'A reboot request is reported without rebooting automatically'
    # Exercise the actual selection/start flow with WinGet absent.
    function New-DeployTimer {
        $timer=[pscustomobject]@{Active=$false}
        $timer|Add-Member ScriptMethod Add_Tick {param($handler)}
        $timer|Add-Member ScriptMethod Start {$this.Active=$true}
        return $timer
    }
    $env:LOCALAPPDATA=Join-Path $temp 'profile'
    . (Join-Path $PSScriptRoot 'BasicApps.ps1')
    function Get-Command {return $null}
    function Start-DeployWork($code,$arguments){$script:workerArgs=$arguments;return @{Async=[pscustomobject]@{IsCompleted=$false}}}
    $env:LOCALAPPDATA=Join-Path $temp 'profile'
    $basicAppChoices=@([pscustomobject]@{IsChecked=$true;Tag=($basicApps|Where-Object Name -eq 'UltraViewer')})
    $items=[pscustomobject]@{Rows=[Collections.ArrayList]::new()}
    $items|Add-Member ScriptMethod Clear {$this.Rows.Clear()}
    $items|Add-Member ScriptMethod Add {param($row)[void]$this.Rows.Add($row)}
    $items|Add-Member ScriptMethod Refresh {}
    $lvBasicAppResults=[pscustomobject]@{Items=$items}
    $lblBasicAppStatus=[pscustomobject]@{Text=''};$basicAppBar=[pscustomobject]@{Maximum=0;Value=0}
    foreach($name in 'lbBasicApps','btnBasicAppInstall','btnBasicAppLog','btnManageApps'){Set-Variable $name ([pscustomobject]@{IsEnabled=$true})}
    Start-BasicApps
    Assert ($script:basicAppRun.Job -and $basicAppTimer.Active -and -not $btnBasicAppInstall.IsEnabled) 'Official app selection starts a tracked background job even without WinGet'
    Assert ($script:workerArgs[0] -eq (Join-Path $PSScriptRoot 'UltraViewer.Install.ps1') -and $lblBasicAppStatus.Text -match '6.6.133') 'The selection reaches the pinned official installer'
}finally{$env:LOCALAPPDATA=$previous;if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks official UltraViewer assertions; signature/version gates, cache, installed/running preservation and UI launch without WinGet."
