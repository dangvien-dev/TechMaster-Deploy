# Windows-only two-process regression: a legacy updater holds the new window hidden until it exits.
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Write-Host 'SKIP: native process ownership test requires Windows.';return}
. (Join-Path $PSScriptRoot 'Startup.UI.ps1')
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ("tm-legacy-O'Brien-"+[guid]::NewGuid().ToString('N'))
$process=$null;$job=$null
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    $scriptPath=Join-Path $temp 'Update-App.ps1';$alive=Join-Path $temp 'alive';$release=Join-Path $temp 'release';$done=Join-Path $temp 'done'
    [IO.File]::WriteAllText($scriptPath,@'
param([string]$Root)
[IO.File]::WriteAllText((Join-Path $Root 'alive'),'ready')
while(-not (Test-Path -LiteralPath (Join-Path $Root 'release'))){Start-Sleep -Milliseconds 20}
[IO.File]::WriteAllText((Join-Path $Root 'done'),'closed')
'@,[Text.UTF8Encoding]::new($true))
    $command="& '{0}' -Root '{1}'" -f $scriptPath.Replace("'","''"),$temp.Replace("'","''")
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=(Get-Process -Id $PID).Path
    $start.Arguments='-NoProfile -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$process=[Diagnostics.Process]::Start($start)
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    while(-not (Test-Path -LiteralPath $alive) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 20}
    if(-not (Test-Path $alive)){throw 'Legacy fixture did not start'}
    $job=Start-DeployWork 'param($path) Start-Sleep -Milliseconds 1500;[IO.File]::WriteAllText($path,"go")' @($release)
    Wait-DeployUpdaterBeforeShow $temp
    if(-not (Test-Path -LiteralPath $done) -or -not $process.HasExited){throw 'New window would appear before the legacy updater closes.'}
    while(-not $job.Async.IsCompleted){Start-Sleep -Milliseconds 10};Receive-DeployWork $job|Out-Null;$job=$null
    Write-Host 'PASS: real legacy updater process exits before the new app is allowed to show; same-user/root ownership checked.'
}finally{
    if($process){if(-not $process.HasExited){$process.Kill();[void]$process.WaitForExit(1000)};$process.Dispose()}
    if($job){Request-DeployWorkCancel $job;while(-not $job.Async.IsCompleted){Start-Sleep -Milliseconds 10};try{Receive-DeployWork $job|Out-Null}catch{}}
    if(Test-Path $temp){Remove-Item $temp -Recurse -Force}
}
