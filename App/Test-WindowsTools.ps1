# Registry, processes, elevation and cleaner are mocked; no Windows settings change.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Windows.Tools.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$code,$m){$caught=$false;try{&$code|Out-Null}catch{$caught=$true};Assert $caught $m}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('tm-win-tools-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
try{
    $script:build=26100;$script:ubr=0;$script:state=[pscustomobject]@{KeyExists=$false;DefaultPresent=$false;Value=$null;Kind=''};$script:writes=0
    function Get-DeployWindowsToolsIdentity {[pscustomobject]@{Build=$script:build;Ubr=$script:ubr;Sid='current';User='Test user';Session=8}}
    function Get-DeployExplorerMenuSnapshot {$script:state.PSObject.Copy()}
    function Write-DeployExplorerMenuOverride([bool]$Legacy){$script:writes++;$script:state=[pscustomobject]@{KeyExists=$Legacy;DefaultPresent=$Legacy;Value=$(if($Legacy){''}else{$null});Kind=$(if($Legacy){'String'}else{''})}}
    $log=Join-Path $dir 'menu.jsonl'
    $r=Set-DeployExplorerMenu Legacy $log
    Assert ($r.Changed -and $script:state.DefaultPresent -and $script:writes -eq 1) 'Windows 11 can store the classic override and verify it'
    Assert ([IO.File]::ReadAllText($log) -match 'backup-before' -and [IO.File]::ReadAllText($log) -match 'verified-after') 'Before/after preference states are logged'
    $r=Set-DeployExplorerMenu Legacy $log
    Assert (-not $r.Changed -and $script:writes -eq 1) 'Applying the same preference is idempotent'
    $r=Set-DeployExplorerMenu Default $log
    Assert ($r.Changed -and -not $script:state.DefaultPresent) 'Windows 11 default removes the classic override'
    foreach($case in @(
        @{Build=26100;Ubr=99999;Warn=$false},
        @{Build=26200;Ubr=9973;Warn=$false},
        @{Build=26200;Ubr=9974;Warn=$true},
        @{Build=26200;Ubr=10000;Warn=$true},
        @{Build=26300;Ubr=0;Warn=$true},
        @{Build=26200;Ubr=$null;Warn=$true}
    )){
        $script:build=$case.Build;$script:ubr=$case.Ubr
        $script:state=[pscustomobject]@{KeyExists=$false;DefaultPresent=$false;Value=$null;Kind=''}
        $before=$script:writes;$r=Set-DeployExplorerMenu Legacy $log
        Assert ($r.Changed -and $script:writes -eq $before+1 -and $script:state.DefaultPresent) 'All build/revision ranges still write and verify the empty classic key'
        Assert ($r.Compatibility.MayIgnore -eq $case.Warn -and -not $r.DisplayVerified) "Compatibility warning uses build plus UBR, not build alone: $($case.Build).$($case.Ubr)"
        if($case.Warn){
            Assert ($r.Message -match 'Shift' -and $r.Message -match 'Arrange primary actions inline' -and $r.Message -match 'triển khai dần') 'New builds receive alternatives without assuming the rollout is active'
            Assert ((Get-DeployExplorerMenuRestartMessage $r) -match 'Arrange primary actions inline') 'Restart completion retains warning and alternatives'
        }else{
            Assert ($r.Message -notmatch 'Arrange primary actions inline') 'Older builds retain ordinary apply/restart guidance'
        }
        $before=$script:writes;$again=Set-DeployExplorerMenu Legacy $log
        Assert (-not $again.Changed -and $script:writes -eq $before -and $again.Compatibility.MayIgnore -eq $case.Warn) 'An already-present key preserves compatibility warning without rewriting'
        $restored=Set-DeployExplorerMenu Default $log
        Assert ($restored.Changed -and -not $script:state.DefaultPresent -and $restored.Message -notmatch 'Arrange primary actions inline') 'Windows 11 restore remains available on new builds'
        Assert ((Get-DeployExplorerMenuRestartMessage $restored) -notmatch 'Arrange primary actions inline') 'Restore completion does not suggest re-enabling a classic-menu alternative'
    }
    $entries=@(Get-Content -LiteralPath $log | ForEach-Object {$_ | ConvertFrom-Json})
    $record=$entries | Where-Object Event -eq 'menu-display-unverified' | Select-Object -Last 1
    Assert ($record.Data.Compatibility.Build -eq 26200 -and $null -eq $record.Data.Compatibility.Ubr -and -not $record.Data.DisplayVerified) 'Persistent log distinguishes registry verification from unknown visual result'
    $unknown=Get-DeployExplorerMenuCompatibility ([pscustomobject]@{Build=26200})
    Assert ($unknown.MayIgnore -and $unknown.BuildLabel -match 'UBR') 'Missing UBR is marked unknown, not silently treated as revision zero'
    $invalid=Get-DeployExplorerMenuCompatibility ([pscustomobject]@{Build=26200;Ubr='bad'})
    Assert ($invalid.MayIgnore -and $null -eq $invalid.Ubr) 'Invalid UBR conservatively warns without a hard unsupported verdict'
    $script:build=26100;$script:ubr=0
    $script:state=[pscustomobject]@{KeyExists=$true;DefaultPresent=$true;Value='other-extension.dll';Kind='String'};$before=$script:writes
    Throws {Set-DeployExplorerMenu Default $log} 'Unknown existing COM configuration is not overwritten or removed'
    Assert ($script:writes -eq $before) 'Refused configuration change makes no registry write'
    $script:build=19045;$r=Set-DeployExplorerMenu Default $log
    Assert (-not $r.Changed -and $script:writes -eq $before) 'Windows 10 does not pretend it supports the Windows 11 menu'
    $script:build=26100;$script:stopped=@();$script:started=0;$script:cimCalls=0
    function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)
        $script:cimCalls++
        if($script:cimCalls -eq 1){@([pscustomobject]@{ProcessId=101;Owner='current'},[pscustomobject]@{ProcessId=102;Owner='other'})}else{[pscustomobject]@{ProcessId=103;Owner='current'}}
    }
    function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction)[pscustomobject]@{ReturnValue=0;Sid=$InputObject.Owner}}
    function Stop-Process {param($Id,$ErrorAction)$script:stopped+=$Id}
    function Start-Sleep {param($Seconds)}
    function Start-Process {param($FilePath,$ArgumentList,$Verb,$WindowStyle,[switch]$Wait,[switch]$PassThru,$ErrorAction)$script:started++;$script:launch=@{File=$FilePath;Args=$ArgumentList;Verb=$Verb};$p=[pscustomobject]@{ExitCode=0};$p|Add-Member ScriptMethod Dispose {};return $p}
    Restart-DeployCurrentExplorer $log
    Assert ($script:stopped.Count -eq 1 -and $script:stopped[0] -eq 101 -and $script:started -eq 0) 'Explorer restart targets only the confirmed current owner and reuses the restarted shell'
    $script:cimCalls=0
    function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction)[pscustomobject]@{ReturnValue=0;Sid='other'}}
    Throws {Restart-DeployCurrentExplorer $log} 'No current-owner Explorer produces an honest non-success instead of killing another user'
    $previousDrive=$env:SystemDrive;$previousWindir=$env:WINDIR
    try{
        $env:SystemDrive='C:';$env:WINDIR='C:\Windows';$script:oldExists=$false;$script:reparse=$false
        function Test-Path {param($LiteralPath,$PathType)if($LiteralPath -like '*Windows.old'){return $script:oldExists};return $true}
        function Get-Item {param($LiteralPath,[switch]$Force,$ErrorAction)[pscustomobject]@{Attributes=$(if($script:reparse){[IO.FileAttributes]::ReparsePoint}else{[IO.FileAttributes]::Directory})}}
        # On non-Windows test hosts, Windows paths need a mocked Join-Path provider.
        function Join-Path($Path,$ChildPath){$Path.TrimEnd('\','/')+'\'+$ChildPath}
        $r=Invoke-DeployWindowsOldCleanup $log
        Assert ($r.Missing -and $script:started -eq 0) 'No Windows.old means no cleaner launch'
        $script:oldExists=$true;$r=Invoke-DeployWindowsOldCleanup $log
        Assert ($r.Remaining -and $script:launch.Verb -eq 'RunAs' -and $script:launch.File -like '*cleanmgr.exe' -and $script:launch.Args -eq '/d C:') 'Only the native cleaner is elevated for the Windows system drive'
        Assert (-not $r.Empty) 'A Windows.old with content goes to Disk Cleanup, never to direct removal'
        function Get-DeployDirectoryEntryState([string]$Path){$script:entryState}
        $script:entryState='Empty';$r=Invoke-DeployWindowsOldCleanup $log
        Assert ($r.Empty -and $script:launch.Verb -eq 'RunAs' -and $script:launch.File -like '*cmd.exe' -and $script:launch.Args -eq '/d /c rd "C:\Windows.old"') 'An empty Windows.old is removed with non-recursive rd instead of an empty Disk Cleanup'
        $script:entryState='Unknown';$r=Invoke-DeployWindowsOldCleanup $log
        Assert (-not $r.Empty -and $script:launch.File -like '*cleanmgr.exe') 'An unreadable Windows.old is never treated as empty'
        $script:reparse=$true;$before=$script:started
        Throws {Invoke-DeployWindowsOldCleanup $log} 'A linked Windows.old directory is rejected'
        Assert ($script:started -eq $before) 'Reparse rejection launches no cleanup process'
        $env:SystemDrive='bad & command'
        Throws {Invoke-DeployWindowsOldCleanup $log} 'Invalid system drive is never interpolated into native arguments'
    }finally{$env:SystemDrive=$previousDrive;$env:WINDIR=$previousWindir;Remove-Item Function:Join-Path;Remove-Item Function:Test-Path;Remove-Item Function:Get-Item}
    Write-Host "PASS: $checks Windows tools assertions; reversible menu selection, guarded registry, per-user Explorer and native Windows.old cleanup."
}finally{Remove-Item -LiteralPath $dir -Recurse -Force}
