# Loaded by the main WinForms app after its existing task controls.
$deployVersionText = 'chưa có số phiên bản'
try { $deployVersionText = ([IO.File]::ReadAllText((Join-Path $Root 'version.txt'))).Trim() } catch {}
$lblTitle.Text = 'TechMaster Deploy v' + $deployVersionText
$updateTab = New-Tab 'Cập nhật'
$headerUpdate = New-Button 'Cập nhật' 650 8 104 30 -secondary
$headerUpdate.Add_Click({ $tabs.SelectedTab = $updateTab })
$header.Controls.Add($headerUpdate)
$updateTab.Controls.Add((New-Label ('Phiên bản đang dùng: ' + $deployVersionText) 28 20 780 28 $fTitle))
$updateNote = New-Label 'Lấy cập nhật trực tiếp từ dangvien-dev/TechMaster-Deploy (nhánh main). Chỉ tải tệp đã thay đổi; giữ cấu hình, logo, biên bản, kho Office và Reinstall. Có sao lưu và quay lại.' 28 60 790 60
$updateNote.ForeColor = $cMuted
$updateTab.Controls.Add($updateNote)
$script:updateProcess = $null
$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 500
$updateTimer.Add_Tick({
    if ($script:updateProcess -and $script:updateProcess.HasExited) {
        $updateTimer.Stop()
        $script:updateProcess.Dispose()
        $script:updateProcess = $null
        $form.Enabled = $true
        $form.Activate()
        Set-Status 'Đã đóng công cụ cập nhật.'
    }
})
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
        $command = "& '{0}' -Root '{1}' -Mode {2} -ParentId {3}" -f ((Join-Path $runner 'Update-App.ps1').Replace("'", "''")), $Root.Replace("'", "''"), $mode, $PID
        if ($zipPath) { $command += " -PackagePath '{0}'" -f $zipPath.Replace("'", "''") }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $powerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $script:updateProcess = Start-Process -FilePath $powerShell -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -WorkingDirectory $runner -PassThru -ErrorAction Stop
        try { $null = $script:updateProcess.Handle } catch [InvalidOperationException] {}
        $form.Enabled = $false
        Set-Status 'Tiếp tục trong cửa sổ cập nhật. App chỉ đóng khi bạn xác nhận cài hoặc quay lại.'
        $updateTimer.Start()
    } catch {
        $form.Enabled = $true
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Không mở được công cụ cập nhật', 'OK', 'Error')
    }
}
$checkUpdate = New-Button 'Cập nhật từ repo' 28 140 235 44
$checkUpdate.Add_Click({ Start-DeployUpdater 'Online' }); $updateTab.Controls.Add($checkUpdate)
$localUpdate = New-Button 'Cập nhật từ ZIP…' 288 140 235 44
$localUpdate.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'Chọn ZIP cập nhật TechMaster Deploy'
        $dialog.Filter = 'TechMaster Deploy ZIP (*.zip)|*.zip'
        if ($dialog.ShowDialog($form) -eq 'OK') { Start-DeployUpdater 'Local' $dialog.FileName }
    } finally { $dialog.Dispose() }
}); $updateTab.Controls.Add($localUpdate)
$changeLogUpdate = New-Button 'Nội dung phiên bản' 548 140 235 44 -secondary
$changeLogUpdate.Add_Click({
    $path = Join-Path $Root 'CHANGELOG.md'
    if (Test-Path -LiteralPath $path) { Start-Process notepad.exe ('"{0}"' -f $path) }
}); $updateTab.Controls.Add($changeLogUpdate)
$historyUpdate = New-Button 'Lịch sử cập nhật' 28 208 235 40 -secondary
$historyUpdate.Add_Click({ Start-DeployUpdater 'History' }); $updateTab.Controls.Add($historyUpdate)
$rollbackUpdate = New-Button 'Quay lại bản trước' 288 208 235 40 -secondary
$rollbackUpdate.Add_Click({ Start-DeployUpdater 'Rollback' }); $updateTab.Controls.Add($rollbackUpdate)
$accessUpdate = New-Button 'Quyền truy cập repo' 548 208 235 40 -secondary
$accessUpdate.Add_Click({ Start-DeployUpdater 'Access' }); $updateTab.Controls.Add($accessUpdate)
$updateTab.Controls.Add((New-Label 'Không cần GitHub Release hoặc tải ZIP bằng tay. Nếu repo riêng tư, mở Quyền truy cập repo để nhập token chỉ đọc, lưu mã hoá trên máy này. Cập nhật từ ZIP vẫn dùng được khi cần chuyển bản offline.' 28 280 790 76))
