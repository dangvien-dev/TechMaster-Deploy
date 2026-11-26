# Repair actions for the antivirus diagnostic. Every action is explicit, logged and verified afterwards.
# Nothing is deleted: leftover files are moved to <drive>\_CachLy_Virus and renamed *.virus.

function Test-AvBroadExclusion([string]$path) {
    return ($path -match '^[A-Za-z]:\\?$' -or $path -match '(?i)^[A-Za-z]:\\(Windows|Users|Program Files( \(x86\))?|ProgramData)\\?$' -or $path -match '(?i)\\(Temp|AppData)\\?$')
}

function Get-AvRepairPlan($report) {
    $plan = New-Object System.Collections.Generic.List[object]
    $add = {
        param($id, $title, $detail, [bool]$recommended, [bool]$danger, $data)
        $plan.Add([pscustomobject]@{ Id = $id; Title = $title; Detail = $detail; Recommended = $recommended; Danger = $danger; Data = $data; Order = $plan.Count })
    }
    $defenderMain = ($report.Defender -and $report.Defender.Mode -match '(?i)^Normal')
    $passive = if ($report.Defender -and -not $defenderMain) { ' Defender đang ở chế độ ' + $report.Defender.Mode + ' (AV khác là chính) nên có thể không chạy được.' } else { '' }
    $hasVirus = [bool](@($report.Infector).Count -or @($report.Detections | Where-Object { $_.Threat -match '(?i)Virus[:.]|Floxif|Neshta|Sality|Virut|Ramnit' }).Count)

    if ($report.Defender) {
        & $add 'UpdateSignatures' 'Cập nhật định nghĩa virus Defender' ('Tải định nghĩa mới trước khi quét.' + $passive) $defenderMain $false $null
    }
    foreach ($id in @($report.AllowedIds)) {
        & $add 'RemoveAllowed' ('Bỏ "Cho phép" mã mối đe dọa ' + $id) 'Defender sẽ xử lý lại mọi tệp mang mã này.' $true $false ([string]$id)
    }
    foreach ($path in @($report.Exclusions | Where-Object { Test-AvBroadExclusion $_ })) {
        & $add 'RemoveExclusion' ('Gỡ ngoại lệ Defender: ' + $path) 'Ngoại lệ phủ cả vùng rộng, mọi tệp trong đó không được quét. Chỉ bỏ chọn nếu chính bạn đã thêm có chủ đích.' $true $false ([string]$path)
    }
    if (@($report.Infector | Where-Object { $_ -match 'AppInit_DLLs' }).Count) {
        & $add 'DisableAppInit' 'Tắt AppInit_DLLs (sao lưu trước)' 'Đặt LoadAppInit_DLLs = 0 để Windows không nạp DLL lạ vào mọi ứng dụng. Giá trị cũ được lưu trong ProgramData để khôi phục.' $true $false $null
    }
    $present = @($report.Detections | ForEach-Object { $_.Files } | Where-Object Present | ForEach-Object Path | Sort-Object -Unique)
    if ($present.Count) {
        & $add 'Quarantine' ('Cách ly ' + $present.Count + ' tệp còn sót trên ổ') 'Chuyển vào <ổ>\_CachLy_Virus\<ngày giờ>, đổi đuôi .virus và ghi danh sách kèm SHA256. Không xoá.' $true $false $present
    }
    if ($report.Defender) {
        & $add 'QuickScan' 'Quét nhanh (Defender)' ('Vài phút.' + $passive) $defenderMain $false $null
        foreach ($drive in @($report.Drives | Where-Object { $_.Drive -ne 'C:' } | ForEach-Object Drive)) {
            & $add 'CustomScan' ('Quét toàn bộ ổ ' + $drive) ('Ổ này có tệp bị phát hiện. Ổ phải đang cắm.' + $passive) $defenderMain $false ($drive + '\')
        }
        & $add 'FullScan' 'Quét toàn bộ máy (Defender)' ('Có thể mất 30–90 phút.' + $passive) $false $false $null
        if ($hasVirus) {
            & $add 'OfflineScan' 'Quét offline Microsoft Defender — MÁY SẼ KHỞI ĐỘNG LẠI' 'Khởi động lại vào môi trường quét riêng (~15 phút), diệt mã độc không gỡ được khi Windows đang chạy. Lưu hết công việc trước. Luôn chạy sau cùng.' $false $true $null
        }
    }
    $rank = @{ UpdateSignatures = 0; RemoveAllowed = 1; RemoveExclusion = 2; DisableAppInit = 3; Quarantine = 4; QuickScan = 5; CustomScan = 6; FullScan = 7; OfflineScan = 9 }
    @($plan | Sort-Object { $rank[$_.Id] }, Order)
}

function New-AvRepairResult([string]$title, [bool]$ok, [string]$message) {
    [pscustomobject]@{ Title = $title; Ok = $ok; Message = $message; Time = (Get-Date).ToString('HH:mm:ss') }
}

function Get-AvNewDetections([datetime]$since) {
    @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -and [datetime]$_.InitialDetectionTime -ge $since })
}

function Get-AvRunningScan {
    # Defender keeps start/end times per scan type; a start newer than the end means it is still running.
    try { $status = Get-MpComputerStatus -ErrorAction Stop } catch { return $null }
    foreach ($kind in @(@('Full', 'Quét toàn bộ'), @('Quick', 'Quét nhanh'))) {
        $started = $status.($kind[0] + 'ScanStartTime'); $ended = $status.($kind[0] + 'ScanEndTime')
        if ($started -and (-not $ended -or [datetime]$started -gt [datetime]$ended)) {
            return [pscustomobject]@{ Name = $kind[1]; Started = [datetime]$started }
        }
    }
    $null
}

function Test-AvScanBusyError($errorRecord) {
    $text = [string]$errorRecord.Exception.Message
    return ($text -match '(?i)already in progress|scan is in progress|đang (được )?quét')
}

function Start-AvScanWhenFree([scriptblock]$start, [hashtable]$Progress, [string]$title, [int]$WaitSeconds) {
    # Wait for another Defender scan (a manual full scan, the scheduled scan) instead of failing at once.
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        $running = Get-AvRunningScan
        if (-not $running) {
            try { & $start; return $null }
            catch { if (-not (Test-AvScanBusyError $_)) { throw } }
        }
        if ((Get-Date) -ge $deadline) {
            $who = if ($running) { '{0} của Defender (bắt đầu {1:HH:mm dd/MM})' -f $running.Name, $running.Started } else { 'một lượt quét khác của Defender (quét định kỳ hoặc do người dùng mở)' }
            return ('Defender vẫn đang chạy ' + $who + ' sau ' + [int]($WaitSeconds / 60) + ' phút chờ. Để lượt đó chạy xong (xem Windows Security → Virus & threat protection), rồi chạy lại mục này.')
        }
        if ($Progress) {
            $Progress.Current = '{0}: chờ {1} chạy xong…' -f $title, $(if ($running) { ('{0} (từ {1:HH:mm})' -f $running.Name.ToLower(), $running.Started) } else { 'lượt quét khác' })
        }
        Start-Sleep -Seconds 15
    }
}

function Invoke-AvRepairItem($item, [string]$QuarantineRoot, [string]$BackupRoot, [hashtable]$Progress, [int]$ScanWaitSeconds = 900) {
    $title = $item.Title
    try {
        switch ($item.Id) {
            'UpdateSignatures' {
                $before = [string](Get-MpComputerStatus -ErrorAction Stop).AntivirusSignatureVersion
                Update-MpSignature -ErrorAction Stop
                $after = [string](Get-MpComputerStatus -ErrorAction Stop).AntivirusSignatureVersion
                return New-AvRepairResult $title $true $(if ($after -ne $before) { 'Đã cập nhật: ' + $before + ' → ' + $after } else { 'Đã là bản mới nhất: ' + $after })
            }
            'RemoveAllowed' {
                Remove-MpPreference -ThreatIDDefaultAction_Ids ([long]$item.Data) -ErrorAction Stop
                $left = @((Get-MpPreference -ErrorAction Stop).ThreatIDDefaultAction_Ids | Where-Object { $null -ne $_ -and [string]$_ -eq [string]$item.Data })
                return New-AvRepairResult $title (-not $left.Count) $(if ($left.Count) { 'Mã vẫn còn trong danh sách cho phép sau khi gỡ.' } else { 'Đã gỡ, kiểm tra lại không còn.' })
            }
            'RemoveExclusion' {
                Remove-MpPreference -ExclusionPath ([string]$item.Data) -ErrorAction Stop
                $left = @((Get-MpPreference -ErrorAction Stop).ExclusionPath | Where-Object { $_ -eq [string]$item.Data })
                return New-AvRepairResult $title (-not $left.Count) $(if ($left.Count) { 'Ngoại lệ vẫn còn (có thể do Group Policy / phần mềm quản lý đặt).' } else { 'Đã gỡ, kiểm tra lại không còn.' })
            }
            'DisableAppInit' {
                if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop | Out-Null }
                $keys = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows'
                $saved = @(foreach ($key in $keys) {
                    try { $v = Get-ItemProperty -LiteralPath $key -ErrorAction Stop; [ordered]@{ Key = $key; AppInit_DLLs = [string]$v.AppInit_DLLs; LoadAppInit_DLLs = $v.LoadAppInit_DLLs } } catch { }
                })
                $backup = Join-Path $BackupRoot ('AppInit_{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
                [IO.File]::WriteAllText($backup, (ConvertTo-Json @($saved) -Depth 3), [Text.UTF8Encoding]::new($true))
                foreach ($entry in $saved) { if ([int]$entry.LoadAppInit_DLLs -ne 0) { Set-ItemProperty -LiteralPath $entry.Key -Name LoadAppInit_DLLs -Value 0 -Type DWord -ErrorAction Stop } }
                $still = @(foreach ($entry in $saved) { if ([int](Get-ItemProperty -LiteralPath $entry.Key -ErrorAction Stop).LoadAppInit_DLLs -ne 0) { $entry.Key } })
                return New-AvRepairResult $title (-not $still.Count) $(if ($still.Count) { 'Vẫn bật ở: ' + ($still -join ', ') } else { 'Đã tắt. Sao lưu: ' + $backup + '. Khởi động lại máy để có hiệu lực hoàn toàn.' })
            }
            'Quarantine' {
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $moved = 0; $gone = 0; $failed = New-Object System.Collections.Generic.List[string]; $manifestByRoot = @{}
                foreach ($path in @($item.Data)) {
                    if (-not (Test-Path -LiteralPath $path)) { $gone++; continue }
                    $root = if ($QuarantineRoot) { $QuarantineRoot } else { (Split-Path -Qualifier $path) + '\_CachLy_Virus' }
                    $folder = Join-Path $root $stamp
                    try {
                        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null }
                        $hash = try { (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { '' }
                        $leaf = Split-Path -Leaf $path
                        $target = Join-Path $folder ($leaf + '.virus'); $n = 1
                        while (Test-Path -LiteralPath $target) { $target = Join-Path $folder ('{0}.{1}.virus' -f $leaf, $n); $n++ }
                        Move-Item -LiteralPath $path -Destination $target -ErrorAction Stop
                        if ((Test-Path -LiteralPath $path) -or -not (Test-Path -LiteralPath $target)) {
                            # Defender may clean/remove the file while it is being moved.
                            if (Test-Path -LiteralPath $path) { $failed.Add($path); continue }
                            $gone++
                        } else { $moved++ }
                        if (-not $manifestByRoot.ContainsKey($folder)) { $manifestByRoot[$folder] = New-Object System.Collections.Generic.List[string] }
                        $manifestByRoot[$folder].Add((@($path, $target, $hash) -join "`t"))
                    } catch { $failed.Add($path + ' (' + $_.Exception.Message + ')') }
                }
                foreach ($folder in $manifestByRoot.Keys) {
                    $lines = @("Nguồn`tĐích`tSHA256") + @($manifestByRoot[$folder])
                    [IO.File]::WriteAllText((Join-Path $folder 'DanhSach.tsv'), ($lines -join "`r`n"), [Text.UTF8Encoding]::new($true))
                }
                $msg = 'Đã chuyển {0} tệp' -f $moved
                if ($gone) { $msg += '; {0} tệp đã không còn (Defender đã xử lý)' -f $gone }
                if ($failed.Count) { $msg += '; KHÔNG chuyển được: ' + ($failed -join '; ') }
                if ($manifestByRoot.Count) { $msg += '. Thư mục: ' + (@($manifestByRoot.Keys) -join ', ') }
                return New-AvRepairResult $title (-not $failed.Count) $msg
            }
            { $_ -in 'QuickScan','FullScan','CustomScan' } {
                if ($item.Id -eq 'CustomScan' -and -not (Test-Path -LiteralPath ([string]$item.Data))) { return New-AvRepairResult $title $false ('Ổ ' + $item.Data + ' không có trên máy (đã rút?). Cắm lại rồi chạy.') }
                $type = switch ($item.Id) { 'QuickScan' { 'QuickScan' } 'FullScan' { 'FullScan' } default { 'CustomScan' } }
                $path = [string]$item.Data
                $script:avScanStart = Get-Date
                $busy = Start-AvScanWhenFree {
                    $script:avScanStart = Get-Date
                    if ($type -eq 'CustomScan') { Start-MpScan -ScanType CustomScan -ScanPath $path -ErrorAction Stop }
                    else { Start-MpScan -ScanType $type -ErrorAction Stop }
                } $Progress $title $ScanWaitSeconds
                if ($busy) { return New-AvRepairResult $title $false $busy }
                $start = $script:avScanStart
                $found = @(Get-AvNewDetections $start)
                $span = (Get-Date) - $start
                $took = '{0}:{1:00}' -f [int][Math]::Floor($span.TotalMinutes), $span.Seconds
                return New-AvRepairResult $title $true $(if ($found.Count) { 'Xong sau ' + $took + '. Phát hiện mới: ' + $found.Count + ' — chạy Chẩn đoán lại để xem chi tiết.' } else { 'Xong sau ' + $took + '. Không có phát hiện mới.' })
            }
            'OfflineScan' {
                Start-MpWDOScan -ErrorAction Stop
                return New-AvRepairResult $title $true 'Đã yêu cầu quét offline. Windows sẽ khởi động lại trong giây lát.'
            }
            default { return New-AvRepairResult $title $false ('Thao tác không hỗ trợ: ' + $item.Id) }
        }
    } catch {
        return New-AvRepairResult $title $false $_.Exception.Message
    }
}

function Invoke-AvRepair($items, [hashtable]$Progress, [string]$LogPath, [string]$QuarantineRoot, [string]$BackupRoot) {
    if (-not $BackupRoot) { $BackupRoot = Join-Path $env:ProgramData 'TechMaster Deploy\AV Backups' }
    $rank = @{ UpdateSignatures = 0; RemoveAllowed = 1; RemoveExclusion = 2; DisableAppInit = 3; Quarantine = 4; QuickScan = 5; CustomScan = 6; FullScan = 7; OfflineScan = 9 }
    $ordered = @($items | Sort-Object { $rank[$_.Id] }, Order)
    $results = New-Object System.Collections.Generic.List[object]
    $log = { param($line) if ($LogPath) { try { [IO.File]::AppendAllText($LogPath, $line + "`r`n", [Text.UTF8Encoding]::new($true)) } catch { } } }
    & $log ('=== TechMaster — sửa lỗi báo virus · ' + $env:COMPUTERNAME + ' · ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ===')
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $item = $ordered[$i]
        if ($Progress) { $Progress.Index = $i + 1; $Progress.Total = $ordered.Count; $Progress.Current = $item.Title; $Progress.Percent = [int](100 * $i / [Math]::Max(1, $ordered.Count)) }
        & $log ('[{0}] BẮT ĐẦU  {1}' -f (Get-Date).ToString('HH:mm:ss'), $item.Title)
        $result = Invoke-AvRepairItem $item $QuarantineRoot $BackupRoot $Progress
        $results.Add($result)
        & $log ('[{0}] {1}  {2} — {3}' -f $result.Time, $(if ($result.Ok) { 'XONG ' } else { 'LỖI  ' }), $result.Title, $result.Message)
        if ($Progress) { $Progress.Lines.Add(('{0} {1}: {2}' -f $(if ($result.Ok) { '✓' } else { '✗' }), $result.Title, $result.Message)) | Out-Null }
    }
    if ($Progress) { $Progress.Percent = 100; $Progress.Current = 'Hoàn tất' }
    $results.ToArray()
}
