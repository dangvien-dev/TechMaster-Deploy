# Loaded by the main WinForms app after its existing task controls.
$deployVersionText = 'chưa có số phiên bản'
try { $deployVersionText = ([IO.File]::ReadAllText((Join-Path $Root 'version.txt'))).Trim() } catch {}
$lblTitle.Text = 'TechMaster Deploy v' + $deployVersionText
$updateTab = New-Tab 'Cập nhật'
$headerUpdate = New-Button 'Cập nhật' 660 24 96 32 -secondary
$lblInfo.Width = 620
$headerUpdate.Add_Click({ $tabs.SelectedTab = $updateTab })
$header.Controls.Add($headerUpdate)
$updateTab.Controls.Add((New-Label ('Phiên bản đang dùng: ' + $deployVersionText) 28 20 780 28 $fTitle))
$updateNote = New-Label 'Cài phiên bản mới ngay trong ứng dụng. Giữ nguyên cấu hình, biên bản và bộ cài đã tải. Ứng dụng sẽ tự mở lại sau khi hoàn tất.' 28 60 790 60
$updateNote.ForeColor = $cMuted
$updateTab.Controls.Add($updateNote)
$script:updateProcess = $null
$script:updateCloseRequest = $null
$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 500
function Set-DeployUpdateBusy([bool]$busy) {
    # Keep the main window enabled: Process.CloseMainWindow refuses a disabled
    # window. Block only controls that could start work while updating.
    $form.Enabled = $true
    $tabs.Enabled = -not $busy
    $header.Enabled = -not $busy
}
function Update-DeployUpdaterState {
    if (-not $script:updateProcess) { return }
    if ($script:updateProcess.HasExited) {
        $updateTimer.Stop()
        $script:updateProcess.Dispose()
        $script:updateProcess = $null
        if ($script:updateCloseRequest -and (Test-Path -LiteralPath $script:updateCloseRequest -PathType Leaf)) {
            Remove-Item -LiteralPath $script:updateCloseRequest -Force -ErrorAction SilentlyContinue
        }
        $script:updateCloseRequest = $null
        Set-DeployUpdateBusy $false
        $form.Activate()
        Set-Status 'Đã đóng công cụ cập nhật.'
        return
    }
    if ($script:updateCloseRequest -and (Test-Path -LiteralPath $script:updateCloseRequest -PathType Leaf)) {
        try { $request = [IO.File]::ReadAllText($script:updateCloseRequest) } catch [IO.IOException] { return }
        if ($request -ceq 'close') {
            # This timer runs on the WinForms UI thread. No process-window
            # discovery or forced termination is needed, even in a modal form.
            $updateTimer.Stop()
            $form.Close()
        }
    }
}
$updateTimer.Add_Tick({ Update-DeployUpdaterState })
function Start-DeployUpdater([string]$mode, [string]$zipPath = '') {
    if ($script:officeRun -or $script:basicAppRun.Process -or $script:mediaDownload -or $script:updateProcess) {
        [void][System.Windows.Forms.MessageBox]::Show('Chờ các thao tác cài / tải đang chạy kết thúc rồi cập nhật.', 'Cập nhật', 'OK', 'Information')
        return
    }
    try {
        $runner = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Update Runner\' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $runner -Force -ErrorAction Stop | Out-Null
        foreach ($file in 'Update-App.ps1', 'Update.Core.ps1', 'Console.ps1', 'ConsoleFont.cs') {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $runner -ErrorAction Stop
        }
        $script:updateCloseRequest = Join-Path $runner 'close.request'
        $command = "& '{0}' -Root '{1}' -Mode {2} -ParentId {3} -CloseRequestPath '{4}'" -f ((Join-Path $runner 'Update-App.ps1').Replace("'", "''")), $Root.Replace("'", "''"), $mode, $PID, $script:updateCloseRequest.Replace("'", "''")
        if ($zipPath) { $command += " -PackagePath '{0}'" -f $zipPath.Replace("'", "''") }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $powerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $script:updateProcess = Start-Process -FilePath $powerShell -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -WorkingDirectory $runner -PassThru -ErrorAction Stop
        try { $null = $script:updateProcess.Handle } catch [InvalidOperationException] {}
        Set-DeployUpdateBusy $true
        Set-Status 'Tiếp tục trong cửa sổ cập nhật. App chỉ đóng khi bạn xác nhận cài hoặc quay lại.'
        $updateTimer.Start()
    } catch {
        $script:updateCloseRequest = $null
        Set-DeployUpdateBusy $false
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Không mở được công cụ cập nhật', 'OK', 'Error')
    }
}
$checkUpdate = New-Button 'Kiểm tra cập nhật' 28 140 235 44
$checkUpdate.Add_Click({ Start-DeployUpdater 'Online' }); $updateTab.Controls.Add($checkUpdate)
$localUpdate = New-Button 'Cài từ tệp…' 288 140 235 44
$localUpdate.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'Chọn ZIP cập nhật TechMaster Deploy'
        $dialog.Filter = 'TechMaster Deploy ZIP (*.zip)|*.zip'
        if ($dialog.ShowDialog($form) -eq 'OK') { Start-DeployUpdater 'Local' $dialog.FileName }
    } finally { $dialog.Dispose() }
}); $updateTab.Controls.Add($localUpdate)
$changeLogUpdate = New-Button 'Có gì mới?' 548 140 235 44 -secondary
$changeLogUpdate.Add_Click({
    $path = Join-Path $Root 'CHANGELOG.md'
    if (Test-Path -LiteralPath $path) { Start-Process notepad.exe ('"{0}"' -f $path) }
}); $updateTab.Controls.Add($changeLogUpdate)
$historyUpdate = New-Button 'Lịch sử cập nhật' 28 208 235 40 -secondary
$historyUpdate.Add_Click({ Start-DeployUpdater 'History' }); $updateTab.Controls.Add($historyUpdate)
$rollbackUpdate = New-Button 'Khôi phục bản trước' 288 208 235 40 -secondary
$rollbackUpdate.Add_Click({ Start-DeployUpdater 'Rollback' }); $updateTab.Controls.Add($rollbackUpdate)
$updateTab.Controls.Add((New-Label 'Ứng dụng luôn sao lưu trước khi cập nhật. Bạn có thể khôi phục bản trước nếu cần.' 28 280 790 50))
