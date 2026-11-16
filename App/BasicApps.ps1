$basicApps = @(
    @{ Name = 'Google Chrome'; Id = 'Google.Chrome'; Description = 'Duyệt web' }
    @{ Name = '7-Zip'; Id = '7zip.7zip'; Description = 'Nén và giải nén' }
    @{ Name = 'VLC'; Id = 'VideoLAN.VLC'; Description = 'Phát video và nhạc' }
    @{ Name = 'SumatraPDF'; Id = 'SumatraPDF.SumatraPDF'; Description = 'Đọc PDF' }
    @{ Name = 'Notepad++'; Id = 'Notepad++.Notepad++'; Description = 'Soạn thảo văn bản' }
)

$script:basicAppRun = $null
$script:basicAppLog = $null
$basicAppTimer = New-Object System.Windows.Forms.Timer
$basicAppTimer.Interval = 400

function Get-BasicAppResult([int]$code) {
    switch ($code.ToString('X8')) {
        '00000000' { return @{ Status = 'Đã cài'; Group = 'Installed' } }
        { $_ -in '8A150061', '8A15010D' } { return @{ Status = 'Đã có sẵn'; Group = 'Skipped' } }
        { $_ -in '8A150109', '8A15010B' } { return @{ Status = 'Cần khởi động lại'; Group = 'Restart' } }
        default { return @{ Status = 'Lỗi 0x' + $code.ToString('X8'); Group = 'Failed' } }
    }
}

function Finish-BasicApp($run, $result, [string]$details) {
    $run.Rows[$run.Index].SubItems[1].Text = $result.Status
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
        $run.Rows[$run.Index].SubItems[1].Text = 'Đang cài…'
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
    $lbBasicApps.Enabled = $true
    $btnBasicAppInstall.Enabled = $true
    $lblBasicAppStatus.Text = "$($run.Counts.Installed) đã cài · $($run.Counts.Skipped) đã có · $($run.Counts.Failed) lỗi"
    if ($run.Counts.Restart) { $lblBasicAppStatus.Text += " · $($run.Counts.Restart) cần khởi động lại" }
    if ($run.LogFailed) { $lblBasicAppStatus.Text += ' · Nhật ký ghi chưa đủ' }
    Set-Status $lblBasicAppStatus.Text
}

function Start-BasicApps {
    if ($script:basicAppRun) { return }
    $items = @($lbBasicApps.CheckedIndices | ForEach-Object { $basicApps[$_] })
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
        $row = $lvBasicAppResults.Items.Add($app.Name)
        [void]$row.SubItems.Add('Đang chờ')
        $run.Rows += $row
    }
    $basicAppBar.Maximum = $items.Count
    $basicAppBar.Value = 0
    $lbBasicApps.Enabled = $false
    $btnBasicAppInstall.Enabled = $false
    $btnBasicAppLog.Enabled = $true
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

$t7 = New-Tab 'Cài ứng dụng'
$appsHeading = New-Label 'Ứng dụng cơ bản' 22 20 810 26 $fBold
$t7.Controls.Add($appsHeading)
$appsHint = New-Label 'Chọn app để WinGet tải và cài. Nút cài chấp nhận điều khoản của nguồn và các gói đã chọn.' 22 51 810 39
$appsHint.ForeColor = $cMuted
$t7.Controls.Add($appsHint)

$choiceCard = New-Object TechMaster.RoundedCard
$choiceCard.Location = New-Object Drawing.Point(12, 96)
$choiceCard.Size = New-Object Drawing.Size(408, 235)
$choiceHeading = New-Label 'Chọn ứng dụng' 15 12 378 25 $fBold
$choiceHeading.BackColor = [Drawing.Color]::Transparent
$choiceCard.Controls.Add($choiceHeading)
$lbBasicApps = New-Object Windows.Forms.CheckedListBox
$lbBasicApps.Location = New-Object Drawing.Point(15, 44)
$lbBasicApps.Size = New-Object Drawing.Size(378, 171)
$lbBasicApps.BorderStyle = 'None'
$lbBasicApps.BackColor = $choiceCard.SurfaceColor
$lbBasicApps.CheckOnClick = $true
$lbBasicApps.IntegralHeight = $false
$lbBasicApps.AccessibleName = 'Chọn ứng dụng để cài'
foreach ($app in $basicApps) { [void]$lbBasicApps.Items.Add("$($app.Name)  ·  $($app.Description)") }
$choiceCard.Controls.Add($lbBasicApps)
$t7.Controls.Add($choiceCard)

$resultsCard = New-Object TechMaster.RoundedCard
$resultsCard.Location = New-Object Drawing.Point(434, 96)
$resultsCard.Size = New-Object Drawing.Size(422, 235)
$resultsHeading = New-Label 'Kết quả' 15 12 390 25 $fBold
$resultsHeading.BackColor = [Drawing.Color]::Transparent
$resultsCard.Controls.Add($resultsHeading)
$lvBasicAppResults = New-Object Windows.Forms.ListView
$lvBasicAppResults.Location = New-Object Drawing.Point(15, 44)
$lvBasicAppResults.Size = New-Object Drawing.Size(390, 171)
$lvBasicAppResults.View = 'Details'
$lvBasicAppResults.BorderStyle = 'None'
$lvBasicAppResults.BackColor = $resultsCard.SurfaceColor
$lvBasicAppResults.FullRowSelect = $true
[void]$lvBasicAppResults.Columns.Add('Ứng dụng', 174)
[void]$lvBasicAppResults.Columns.Add('Trạng thái', 196)
$resultsCard.Controls.Add($lvBasicAppResults)
$t7.Controls.Add($resultsCard)

$basicAppBar = New-Object Windows.Forms.ProgressBar
$basicAppBar.Location = New-Object Drawing.Point(22, 343)
$basicAppBar.Size = New-Object Drawing.Size(824, 13)
$basicAppBar.AccessibleName = 'Số ứng dụng đã xử lý'
$t7.Controls.Add($basicAppBar)

$lblBasicAppStatus = New-Label 'Sẵn sàng' 22 362 824 23
$t7.Controls.Add($lblBasicAppStatus)
$btnBasicAppHelp = New-Button 'Hướng dẫn WinGet' 22 390 160 36 -secondary
$btnBasicAppHelp.Add_Click({ Start-Process 'https://learn.microsoft.com/vi-vn/windows/package-manager/winget/' })
$t7.Controls.Add($btnBasicAppHelp)
$btnBasicAppLog = New-Button 'Xem nhật ký' 491 390 150 36 -secondary
$btnBasicAppLog.Enabled = $false
$btnBasicAppLog.Add_Click({ Start-Process notepad.exe ('"{0}"' -f $script:basicAppLog) })
$t7.Controls.Add($btnBasicAppLog)
$btnBasicAppInstall = New-Button 'Cài ứng dụng đã chọn' 655 390 191 36
$btnBasicAppInstall.Add_Click({ Start-BasicApps })
$t7.Controls.Add($btnBasicAppInstall)
