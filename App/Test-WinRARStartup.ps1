# First-launch flow only: no real WinRAR, installer or Explorer changes on the test host.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinRAR.Startup.ps1')
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('tm-rar-start-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir|Out-Null
try{
    . (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
    $read=Start-DeployWork 'param($module,$path) . $module; [pscustomobject]@{Running=(Get-DeployWinRarRunning $path)}' @((Join-Path $PSScriptRoot 'WinRAR.Startup.ps1'),(Join-Path $dir 'no-installed-WinRAR.exe'))
    while(-not $read.Async.IsCompleted){Start-Sleep -Milliseconds 10}
    Assert (-not $read.Pipeline.HadErrors) 'No running WinRAR does not poison the worker error state'
    $readResult=@(Receive-DeployWork $read)[-1]
    Assert (-not $readResult.Running) 'The real background process lookup returns a clean false without requiring WinRAR'
    $log=Join-Path $dir 'launch.log';$script:rarPath=Join-Path $dir "WinRAR user's app/WinRAR.exe";$script:running=$false;$script:starts=0;$script:throwStart=$false
    function Get-DeployWinRarPath {return $script:rarPath}
    function Get-DeployWinRarRunning($Path){return $script:running}
    function Start-Process($FilePath,[switch]$PassThru,$ErrorAction){
        if($script:throwStart){throw 'Mock launch refused'}
        $script:starts++;$script:lastPath=$FilePath
        $p=[pscustomobject]@{};$p|Add-Member ScriptMethod Dispose {};return $p
    }
    foreach($group in 'Installed','Skipped','Restart'){
        $before=$script:starts
        $result=Complete-DeployWinRarStartup @{Status='Native result';Group=$group} 'Native output' $log
        Assert ($script:starts -eq $before+1 -and $script:lastPath -ceq $script:rarPath) "$group starts the exact existing EXE, including spaces and apostrophes"
        Assert ($result.Group -eq $group -and $result.Status -match 'Đã mở WinRAR') "$group preserves the actual install outcome and reports first launch"
        Assert ($result.Details -match 'chưa tự xác nhận' -and $result.Details -match 'Native output') 'Opening WinRAR does not falsely claim the Explorer menu is repaired'
    }
    Assert ([IO.File]::ReadAllText($log) -match 'WinRAR first launch:') 'Launch is logged before execution'
    $script:running=$true;$before=$script:starts
    $result=Complete-DeployWinRarStartup @{Status='Đã có';Group='Skipped'} '' $log
    Assert ($script:starts -eq $before -and $result.Status -match 'đang mở') 'Already-running WinRAR is not launched again or interrupted'
    $script:running=$false;$script:rarPath='';$result=Complete-DeployWinRarStartup @{Status='Đã có';Group='Skipped'} '' $log
    Assert ($result.Group -eq 'Failed' -and $result.Details -match 'Start' -and $script:starts -eq $before) 'An unlocatable EXE is reported, never passed to Start-Process'
    $script:rarPath='WinRAR.exe';$script:throwStart=$true
    $result=Complete-DeployWinRarStartup @{Status='Đã có';Group='Skipped'} '' $log
    Assert ($result.Group -eq 'Failed' -and $result.Details -match 'Mock launch refused') 'A launch failure is returned to the app list and log'
    $result=Complete-DeployWinRarStartup @{Status='WinGet failure';Group='Failed'} 'error output' $log
    Assert ($result.Status -eq 'WinGet failure' -and $result.Details -eq 'error output' -and $script:starts -eq $before) 'Failed installer never starts an application'
    # Exercise the actual timer branch: only the built-in WinRAR package opens after a skip.
    $oldProfile=$env:LOCALAPPDATA
    try{
        $env:LOCALAPPDATA=Join-Path $dir 'profile'
        function New-DeployTimer {
            $timer=[pscustomobject]@{Tick=$null;Active=$false}
            $timer|Add-Member ScriptMethod Add_Tick {param($handler)$this.Tick=$handler}
            $timer|Add-Member ScriptMethod Start {$this.Active=$true}
            $timer|Add-Member ScriptMethod Stop {$this.Active=$false}
            return $timer
        }
        . (Join-Path $PSScriptRoot 'BasicApps.ps1')
        function Start-DeployWork($Code,$Arguments){$script:workerArguments=$Arguments;return @{Async=[pscustomobject]@{IsCompleted=$false}}}
        function Start-NextBasicApp($Run){$script:nextCalled=$true}
        function Finish-BasicApp($Run,$Result,$Details){$script:finished=$Result}
        $script:finished=$null;$script:nextCalled=$false;$script:basicAppLog=$log
        $items=[pscustomobject]@{};$items|Add-Member ScriptMethod Refresh {}
        $lvBasicAppResults=[pscustomobject]@{Items=$items};$lblBasicAppStatus=[pscustomobject]@{Text=''}
        function New-ExitedFixture([int]$Code){$p=[pscustomobject]@{ExitCode=$Code;HasExited=$true};$p|Add-Member ScriptMethod Dispose {};return $p}
        $script:basicAppRun=@{Items=@(@{Id='RARLab.WinRAR';Name='WinRAR'});Index=0;Process=(New-ExitedFixture ([int]-1978335135));Job=$null;Output=[pscustomobject]@{IsCompleted=$true;Result='already installed'};ErrorOutput=[pscustomobject]@{IsCompleted=$true;Result=''}}
        & $basicAppTimer.Tick
        Assert ($script:basicAppRun.Job -and -not $script:finished -and -not $script:nextCalled) 'WinGet already-installed result enters the tracked first-launch job'
        Assert ($script:workerArguments[0] -eq (Join-Path $PSScriptRoot 'WinRAR.Startup.ps1') -and $script:workerArguments[1].Group -eq 'Skipped') 'UI routes skipped WinRAR to the startup module without reinstalling'
        $script:basicAppRun=@{Items=@(@{Id='7zip.7zip';Name='7-Zip'});Index=0;Process=(New-ExitedFixture 0);Job=$null;Output=[pscustomobject]@{IsCompleted=$true;Result='ok'};ErrorOutput=[pscustomobject]@{IsCompleted=$true;Result=''}}
        & $basicAppTimer.Tick
        Assert ($script:finished -and $script:nextCalled -and -not $script:basicAppRun.Job) 'Other applications preserve their original completion flow'
    }finally{$env:LOCALAPPDATA=$oldProfile}
    Write-Host "PASS: $checks WinRAR startup assertions; existing/fresh/reboot paths, duplicate prevention, honest menu status and actual WinGet/UI routing."
}finally{if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force}}
