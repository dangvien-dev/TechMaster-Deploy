# A separate read-only process keeps slow network requests from delaying app exit.
$script:updateProbe=$null;$script:updateProbeNext=[DateTime]::UtcNow.AddSeconds(3);$script:updateBadgeAvailable=$false
function Set-DeployUpdateAvailability([bool]$available,[string]$version='') {
    $script:updateBadgeAvailable=$available
    $UpdateBadge.Visibility=if($available){'Visible'}else{'Collapsed'}
    $headerUpdate.ToolTip=if($available){'Có bản cập nhật mới'+$(if($version){' '+$version}else{''})+'. Bấm để mở mục Cập nhật.'}else{'Mở mục Cập nhật'}
}
function Stop-DeployUpdateProbe {
    $probe=$script:updateProbe;$script:updateProbe=$null
    if(-not $probe){return}
    try{if(-not $probe.Process.HasExited){$probe.Process.Kill();[void]$probe.Process.WaitForExit(1000)}}catch{}
    finally{$probe.Process.Dispose();if(Test-Path -LiteralPath $probe.Directory){Remove-Item -LiteralPath $probe.Directory -Recurse -Force -ErrorAction SilentlyContinue}}
}
function Start-DeployUpdateProbe {
    if($script:updateProbe -or $script:updateProcess){return}
    $dir=Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Update Checks/'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Path $dir -Force|Out-Null
        $path=Join-Path $dir 'result.json'
        $command="& '{0}' -Root '{1}' -ResultPath '{2}'" -f (Join-Path $PSScriptRoot 'Update.Notification.ps1').Replace("'","''"),$Root.Replace("'","''"),$path.Replace("'","''")
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $process=[Diagnostics.Process]::Start($start)
        if(-not $script:updateBadgeAvailable){$headerUpdate.ToolTip='Đang kiểm tra bản cập nhật…'}
        $script:updateProbe=@{Process=$process;Directory=$dir;Path=$path;Started=[DateTime]::UtcNow}
    }catch{Set-DeployUpdateNotificationFailure;if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}}
}
function Set-DeployUpdateNotificationFailure {
    $script:updateProbeNext=[DateTime]::UtcNow.AddMinutes(1)
    if(-not $script:updateBadgeAvailable){$headerUpdate.ToolTip='Chưa kiểm tra được cập nhật. Sẽ thử lại sau 1 phút; bấm Làm mới để thử ngay.'}
}
function Request-DeployUpdateNotification {
    $script:updateProbeNext=[DateTime]::UtcNow
    $availabilityTimer.Start()
}
function Update-DeployUpdateNotification {
    $probe=$script:updateProbe
    if($probe){
        if($probe.Process.HasExited){
            try{
                if(-not $script:updateProcess -and (Test-Path -LiteralPath $probe.Path)){
                    $result=Get-Content -LiteralPath $probe.Path -Raw -Encoding UTF8|ConvertFrom-Json
                    if($result.Success -eq $true){Set-DeployUpdateAvailability ([bool]$result.Available) ([string]$result.Version);$script:updateProbeNext=[DateTime]::UtcNow.AddMinutes(30)}
                    else{Set-DeployUpdateNotificationFailure}
                }elseif(-not $script:updateProcess){Set-DeployUpdateNotificationFailure}
            }catch{Set-DeployUpdateNotificationFailure}finally{Stop-DeployUpdateProbe}
        }elseif(([DateTime]::UtcNow-$probe.Started).TotalSeconds -gt 90){Stop-DeployUpdateProbe;Set-DeployUpdateNotificationFailure}
        return
    }
    if(-not $script:updateProcess -and [DateTime]::UtcNow -ge $script:updateProbeNext){
        $script:updateProbeNext=[DateTime]::UtcNow.AddMinutes(30)
        Start-DeployUpdateProbe
    }
}
$availabilityTimer=New-DeployTimer 1000 {Update-DeployUpdateNotification}
function Start-DeployUpdateNotifications {Request-DeployUpdateNotification}
