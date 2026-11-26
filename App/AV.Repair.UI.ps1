# WPF window for the antivirus repair actions. Engine: AV.Repair.ps1 (runs in a background runspace).

function New-DeployAvRepairWindow($report, $Owner = $null) {
    . (Join-Path $PSScriptRoot 'AV.Repair.ps1')
    $window = Import-DeployWindow (Join-Path $PSScriptRoot 'RepairWindow.xml')
    if ($Owner) { $window.Owner = $Owner }
    $plan = @(Get-AvRepairPlan $report)
    $state = @{ Plan = $plan; Boxes = @(); Work = $null; Progress = $null; LogPath = $null; Shown = 0; Started = $null }
    $window.Tag = $state
    $list = $window.FindName('Items')
    foreach ($item in $plan) {
        $box = New-Object Windows.Controls.CheckBox
        $box.Margin = '0,6,0,6'; $box.IsChecked = [bool]$item.Recommended; $box.Tag = $item; $box.VerticalContentAlignment = 'Top'
        $panel = New-Object Windows.Controls.StackPanel
        $title = New-Object Windows.Controls.TextBlock
        $title.Text = $item.Title + $(if ($item.Recommended) { '  · khuyến nghị' } else { '' }); $title.FontWeight = 'SemiBold'; $title.TextWrapping = 'Wrap'
        if ($item.Danger) { $title.Foreground = '#B91C1C' }
        $detail = New-Object Windows.Controls.TextBlock
        $detail.Text = $item.Detail; $detail.Foreground = '#526880'; $detail.TextWrapping = 'Wrap'; $detail.Margin = '0,2,0,0'
        [void]$panel.Children.Add($title); [void]$panel.Children.Add($detail)
        $box.Content = $panel
        [void]$list.Children.Add($box)
        $state.Boxes += $box
    }
    if (-not $plan.Count) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = 'Không có thao tác sửa phù hợp với kết quả chẩn đoán này (Defender không đọc được hoặc không có gì cần sửa). Với Kaspersky / AV khác, dùng chức năng quét của phần mềm đó.'
        $empty.TextWrapping = 'Wrap'; $empty.Foreground = '#526880'
        [void]$list.Children.Add($empty)
        $window.FindName('Run').IsEnabled = $false; $window.FindName('Recommended').IsEnabled = $false
    }

    $window.FindName('Recommended').Add_Click({
        param($sender, $e)
        $win = [Windows.Window]::GetWindow($sender)
        foreach ($box in $win.Tag.Boxes) { $box.IsChecked = [bool]$box.Tag.Recommended }
    })
    $window.FindName('OpenLog').Add_Click({
        param($sender, $e)
        $path = [Windows.Window]::GetWindow($sender).Tag.LogPath
        if ($path -and (Test-Path -LiteralPath $path)) { Start-Process notepad.exe ('"{0}"' -f $path) }
    })
    $window.FindName('Close').Add_Click({ param($sender, $e) [Windows.Window]::GetWindow($sender).Close() })
    $window.Add_Closing({
        param($sender, $e)
        if ($sender.Tag.Work -and -not $sender.Tag.Work.Async.IsCompleted) {
            $e.Cancel = $true
            Show-DeployMessage 'Đang chạy thao tác sửa (quét có thể mất nhiều phút). Chờ hoàn tất rồi đóng cửa sổ.' 'Sửa lỗi báo virus' 'Warning'
        }
    })

    $timer = New-DeployTimer 400 {}
    $timer.Tag = $window
    $state.Timer = $timer
    $timer.Add_Tick({
        param($sender, $e)
        # No closures: WPF handlers resolve the window through the timer, functions from script scope.
        $timer = $sender; $window = $sender.Tag
        $s = $window.Tag; $p = $s.Progress
        if (-not $s.Work) { $timer.Stop(); return }
        while ($s.Shown -lt $p.Lines.Count) { $window.FindName('Log').AppendText([string]$p.Lines[$s.Shown] + "`r`n"); $s.Shown++ }
        $window.FindName('Log').ScrollToEnd()
        $span = (Get-Date) - $s.Started
        $elapsed = '{0}:{1:00}' -f [int][Math]::Floor($span.TotalMinutes), $span.Seconds
        if (-not $s.Work.Async.IsCompleted) {
            $bar = $window.FindName('Bar'); $bar.IsIndeterminate = $false; $bar.Value = [double]$p.Percent
            Set-DeployNotice ($window.FindName('Status')) ('Mục {0}/{1} · {2} · {3}' -f $p.Index, $p.Total, $p.Current, $elapsed) 'Working'
            return
        }
        $timer.Stop()
        $results = @()
        try { $results = @(Receive-DeployWork $s.Work) } catch { $results = @([pscustomobject]@{ Ok = $false; Title = 'Tiến trình sửa'; Message = $_.Exception.GetBaseException().Message }) }
        $s.Work = $null
        while ($s.Shown -lt $p.Lines.Count) { $window.FindName('Log').AppendText([string]$p.Lines[$s.Shown] + "`r`n"); $s.Shown++ }
        $failed = @($results | Where-Object { -not $_.Ok })
        $window.FindName('Bar').Value = 100
        $kind = if ($failed.Count) { 'Attention' } else { 'Success' }
        Set-DeployNotice ($window.FindName('Status')) ('Xong sau {0}: {1} thành công, {2} lỗi. Bấm Chẩn đoán lại trong thẻ để kiểm tra kết quả.' -f $elapsed, ($results.Count - $failed.Count), $failed.Count) $kind
        foreach ($box in $s.Boxes) { $box.IsEnabled = $true }
        $window.FindName('Run').IsEnabled = $true; $window.FindName('Recommended').IsEnabled = $true; $window.FindName('Close').IsEnabled = $true
        $window.FindName('OpenLog').IsEnabled = [bool]$s.LogPath
        if ($s.OnFinished) { & $s.OnFinished $results }
    })

    $window.FindName('Run').Add_Click({
        param($sender, $e)
        $win = [Windows.Window]::GetWindow($sender); $s = $win.Tag
        $selected = @($s.Boxes | Where-Object { $_.IsChecked } | ForEach-Object Tag)
        if (-not $selected.Count) { Show-DeployMessage 'Chưa chọn thao tác nào.' 'Sửa lỗi báo virus' 'Warning'; return }
        $names = ($selected | ForEach-Object { '• ' + $_.Title }) -join "`n"
        $running = $null
        try { $running = Get-AvRunningScan } catch { }
        if ($running) {
            $wait = "Defender đang {0} (từ {1:HH:mm}). Các mục quét sẽ chờ tối đa 15 phút cho lượt đó xong; trong lúc này máy có thể chậm.`n`nTiếp tục?" -f $running.Name.ToLower(), $running.Started
            if (-not (Confirm-Box $wait 'Defender đang quét' 'Tiếp tục' 'Để sau' -Owner $win)) { return }
        }
        if (-not (Confirm-Box ("Chạy các thao tác sau trên máy này?`n`n" + $names) 'Sửa lỗi báo virus' 'Chạy' -Owner $win)) { return }
        if (@($selected | Where-Object Id -eq 'OfflineScan').Count) {
            if (-not (Confirm-Box "Quét offline sẽ KHỞI ĐỘNG LẠI máy ngay sau khi các mục khác chạy xong.`n`nLưu và đóng mọi tài liệu đang mở, ngắt phiên điều khiển từ xa nếu cần, rồi mới xác nhận." 'Khởi động lại để quét offline' 'Khởi động lại khi xong' -Danger -Owner $win)) { return }
        }
        $dir = Join-Path $env:LOCALAPPDATA 'TechMaster Deploy\AV Repair Logs'
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
        $s.LogPath = Join-Path $dir ('SuaLoi-BaoVirus_{0}_{1}.log' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $s.Progress = [hashtable]::Synchronized(@{ Index = 0; Total = $selected.Count; Current = 'Đang khởi động…'; Percent = 0; Lines = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)) })
        $s.Shown = 0; $s.Started = Get-Date
        $win.FindName('Log').Clear()
        foreach ($box in $s.Boxes) { $box.IsEnabled = $false }
        $win.FindName('Run').IsEnabled = $false; $win.FindName('Recommended').IsEnabled = $false; $win.FindName('OpenLog').IsEnabled = $false
        $bar = $win.FindName('Bar'); $bar.Value = 0; $bar.IsIndeterminate = $true
        Set-DeployNotice ($win.FindName('Status')) 'Đang khởi động…' 'Working'
        try {
            $s.Work = Start-DeployWork 'param($engine, $items, $progress, $log) . $engine; Invoke-AvRepair $items -Progress $progress -LogPath $log' @((Join-Path $PSScriptRoot 'AV.Repair.ps1'), $selected, $s.Progress, $s.LogPath)
            $s.Timer.Start()
        } catch {
            foreach ($box in $s.Boxes) { $box.IsEnabled = $true }
            $win.FindName('Run').IsEnabled = $true; $win.FindName('Recommended').IsEnabled = $true
            $bar.IsIndeterminate = $false
            Set-DeployNotice ($win.FindName('Status')) ('Không khởi chạy được: ' + $_.Exception.Message) 'Error'
        }
    })
    return $window
}
