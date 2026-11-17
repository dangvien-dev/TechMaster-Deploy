$basicApps = @(
    @{ Name = 'Google Chrome'; Id = 'Google.Chrome'; Description = 'Duyệt web' }
    @{ Name = '7-Zip'; Id = '7zip.7zip'; Description = 'Nén và giải nén' }
    @{ Name = 'VLC'; Id = 'VideoLAN.VLC'; Description = 'Phát video và nhạc' }
    @{ Name = 'SumatraPDF'; Id = 'SumatraPDF.SumatraPDF'; Description = 'Đọc PDF' }
    @{ Name = 'Foxit PDF Reader'; Id = 'Foxit.FoxitReader'; Description = 'Đọc PDF' }
    @{ Name = 'ONLYOFFICE Desktop Editors'; Id = 'ONLYOFFICE.DesktopEditors'; Description = 'Bộ ứng dụng văn phòng' }
    @{ Name = 'LibreOffice'; Id = 'TheDocumentFoundation.LibreOffice'; Description = 'Bộ ứng dụng văn phòng' }
    @{ Name = 'Notepad++'; Id = 'Notepad++.Notepad++'; Description = 'Soạn thảo văn bản' }
    @{ Name = 'Zalo'; Id = 'VNGCorp.Zalo'; Description = 'Nhắn tin và gọi điện' }
    @{ Name = 'WinRAR'; Id = 'RARLab.WinRAR'; Description = 'Nén và giải nén' }
    @{ Name = 'EVKey'; Id = 'lamquangminh.EVKey'; Description = 'Bộ gõ tiếng Việt (portable)' }
)

$script:basicAppRun = $null
$script:basicAppLog = $null
$basicAppTimer = New-DeployTimer 400 {}

function Get-BasicAppResult([int]$code) {
    switch ($code.ToString('X8')) {
        '00000000' { return @{ Status = 'Đã cài'; Group = 'Installed' } }
        { $_ -in '8A150061', '8A15010D' } { return @{ Status = 'Đã có sẵn'; Group = 'Skipped' } }
        { $_ -in '8A150109', '8A15010B' } { return @{ Status = 'Cần khởi động lại'; Group = 'Restart' } }
        default { return @{ Status = 'Lỗi 0x' + $code.ToString('X8'); Group = 'Failed' } }
    }
}

function Finish-BasicApp($run, $result, [string]$details) {
    $run.Rows[$run.Index].Status = $result.Status
    $lvBasicAppResults.Items.Refresh()
    $run.Counts[$result.Group]++
    $header = "`r`n=== $($run.Items[$run.Index].Name) ===`r`n$($result.Status)`r`n"
    try { [IO.File]::AppendAllText($script:basicAppLog, $header + $details + "`r`n") }
    catch { $run.LogFailed = $true }
    $run.Index++
    $basicAppBar.Value = $run.Index
}

function Start-NextBasicApp($run) {
    while ($run.Index -lt $run.Items.Count) {
        $app = $run.Items[$run.Index]
        $run.Rows[$run.Index].Status = 'Đang cài…'
        $lvBasicAppResults.Items.Refresh()
        $lblBasicAppStatus.Text = "Đang xử lý $($run.Index + 1)/$($run.Items.Count) · $($app.Name)"
        try {
            $start = New-Object System.Diagnostics.ProcessStartInfo
            $start.FileName = $run.WinGet
            $start.Arguments = "install --id $($app.Id) --exact --source winget --silent --no-upgrade --disable-interactivity --accept-source-agreements --accept-package-agreements"
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $start.StandardOutputEncoding = [Text.Encoding]::UTF8
            $start.StandardErrorEncoding = [Text.Encoding]::UTF8
            $run.Process = [Diagnostics.Process]::Start($start)
            $run.Output = $run.Process.StandardOutput.ReadToEndAsync()
            $run.ErrorOutput = $run.Process.StandardError.ReadToEndAsync()
            return
        } catch {
            if ($run.Process) { $run.Process.Dispose(); $run.Process = $null }
            Finish-BasicApp $run @{ Status = 'Lỗi khởi chạy'; Group = 'Failed' } $_.Exception.Message
        }
    }

    $basicAppTimer.Stop()
    $script:basicAppRun = $null
    $lbBasicApps.IsEnabled = $true
    $btnBasicAppInstall.IsEnabled = $true
    $lblBasicAppStatus.Text = "$($run.Counts.Installed) đã cài · $($run.Counts.Skipped) đã có · $($run.Counts.Failed) lỗi"
    if ($run.Counts.Restart) { $lblBasicAppStatus.Text += " · $($run.Counts.Restart) cần khởi động lại" }
    if ($run.LogFailed) { $lblBasicAppStatus.Text += ' · Nhật ký ghi chưa đủ' }
    Set-Status $lblBasicAppStatus.Text
}

function Start-BasicApps {
    if ($script:basicAppRun) { return }
    $items = @($basicAppChoices | Where-Object IsChecked | ForEach-Object { $_.Tag })
    if (-not $items.Count) {
        $lblBasicAppStatus.Text = 'Chọn ít nhất một ứng dụng.'
        return
    }
    $winget = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        $lblBasicAppStatus.Text = 'Máy chưa có WinGet. Mở Hướng dẫn WinGet để cài App Installer.'
        return
    }

    $run = @{ WinGet = $winget.Source; Items = $items; Rows = @(); Index = 0; Process = $null
        Counts = @{ Installed = 0; Skipped = 0; Restart = 0; Failed = 0 }; LogFailed = $false }
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'TechMaster Deploy\App Logs'
        [void][IO.Directory]::CreateDirectory($logDir)
        $logFile = Join-Path $logDir ('WinGet-{0:yyyyMMdd-HHmmssfff}-{1}.log' -f (Get-Date), $PID)
        [IO.File]::WriteAllText($logFile, "WinGet · $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")
    } catch {
        $lblBasicAppStatus.Text = "Không tạo được nhật ký. $($_.Exception.Message)"
        return
    }
    $script:basicAppLog = $logFile
    $lvBasicAppResults.Items.Clear()
    foreach ($app in $items) {
        $row = [pscustomobject]@{ Name = $app.Name; Status = 'Đang chờ' }
        [void]$lvBasicAppResults.Items.Add($row)
        $run.Rows += $row
    }
    $basicAppBar.Maximum = $items.Count
    $basicAppBar.Value = 0
    $lbBasicApps.IsEnabled = $false
    $btnBasicAppInstall.IsEnabled = $false
    $btnBasicAppLog.IsEnabled = $true
    $script:basicAppRun = $run
    $basicAppTimer.Start()
    Start-NextBasicApp $run
}

$basicAppTimer.Add_Tick({
    $run = $script:basicAppRun
    if (-not $run -or -not $run.Process.HasExited -or -not $run.Output.IsCompleted -or -not $run.ErrorOutput.IsCompleted) { return }
    $code = $run.Process.ExitCode
    try { $details = $run.Output.Result + $run.ErrorOutput.Result }
    catch { $details = $_.Exception.GetBaseException().Message; $run.LogFailed = $true }
    $run.Process.Dispose()
    $run.Process = $null
    Finish-BasicApp $run (Get-BasicAppResult $code) $details
    Start-NextBasicApp $run
})
