# Main WPF window's updater integration and close handshake.
$script:updateProcess = $null; $script:updateCloseRequest = $null
function Set-DeployUpdateBusy([bool]$busy) {
    $form.IsEnabled = $true
    $tabs.IsEnabled = -not $busy; $header.IsEnabled = -not $busy; $Navigation.IsEnabled = -not $busy
}
function Update-DeployUpdaterState {
    if (-not $script:updateProcess) { return }
    if ($script:updateProcess.HasExited) {
        $updateTimer.Stop(); $script:updateProcess.Dispose(); $script:updateProcess = $null
        if ($script:updateCloseRequest -and (Test-Path -LiteralPath $script:updateCloseRequest -PathType Leaf)) { Remove-Item -LiteralPath $script:updateCloseRequest -Force -ErrorAction SilentlyContinue }
        $script:updateCloseRequest = $null
        Set-DeployUpdateBusy $false
        $form.Activate() | Out-Null; Set-Status 'Đã đóng cửa sổ cập nhật.'
        return
    }
    if ($script:updateCloseRequest -and (Test-Path -LiteralPath $script:updateCloseRequest -PathType Leaf)) {
        try { $request = [IO.File]::ReadAllText($script:updateCloseRequest) } catch [IO.IOException] { return }
        if ($request -ceq 'close') { $updateTimer.Stop(); $script:updateClosing = $true; $form.Close() }
    }
}
$updateTimer = New-DeployTimer 300 { Update-DeployUpdaterState }
function Start-DeployUpdater([string]$mode, [string]$zipPath = '') {
    if (($script:desktopProcess -and -not $script:desktopProcess.HasExited) -or $script:officeRun -or $script:basicAppRun -or $script:mediaDownload -or $script:uiWork -or $script:updateProcess) {
        Show-DeployMessage 'Chờ các thao tác đang chạy kết thúc rồi cập nhật.' 'Cập nhật'
        return
    }
    try {
        $runner = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Update Runner/' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $runner -Force -ErrorAction Stop | Out-Null
        foreach ($file in 'Update-App.ps1','Update.Core.ps1','Update.Engine.ps1','Wpf.Runtime.ps1','UpdaterWindow.xml') {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $runner -ErrorAction Stop
        }
        $script:updateCloseRequest = Join-Path $runner 'close.request'
        $command = "& '{0}' -Root '{1}' -Mode {2} -ParentId {3} -CloseRequestPath '{4}'" -f (Join-Path $runner 'Update-App.ps1').Replace("'", "''"), $Root.Replace("'", "''"), $mode, $PID, $script:updateCloseRequest.Replace("'", "''")
        if ($zipPath) { $command += " -PackagePath '{0}'" -f $zipPath.Replace("'", "''") }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $powerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $script:updateProcess = Start-Process -FilePath $powerShell -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -WorkingDirectory $runner -WindowStyle Hidden -PassThru -ErrorAction Stop
        try { $null = $script:updateProcess.Handle } catch [InvalidOperationException] {}
        Set-DeployUpdateBusy $true; Set-Status 'Tiếp tục trong cửa sổ cập nhật.'; $updateTimer.Start()
    } catch {
        $script:updateCloseRequest = $null; Set-DeployUpdateBusy $false
        Show-DeployMessage $_.Exception.Message 'Không mở được cập nhật' 'Error'
    }
}
Bind-Click 'checkUpdate' { Start-DeployUpdater 'Online' }
Bind-Click 'localUpdate' { Start-DeployUpdater 'Local' }
Bind-Click 'historyUpdate' { Start-DeployUpdater 'History' }
Bind-Click 'rollbackUpdate' { Start-DeployUpdater 'Rollback' }
Bind-Click 'changeLogUpdate' { Start-Process notepad.exe ('"{0}"' -f (Join-Path $Root 'CHANGELOG.md')) }
