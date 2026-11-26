# Read-only diagnostics for applications blocked by antivirus ("bị báo virus, không mở được").
# Never restores quarantine, adds exclusions, deletes files, stops services or changes settings.

function ConvertFrom-AvProductState([long]$state) {
    # SecurityCenter2 productState: byte 2 = real-time state (0x10 on), byte 3 = signatures (0x00 up to date).
    $realtime = ($state -shr 8) -band 0xFF
    [pscustomobject]@{
        Enabled  = (($realtime -band 0x10) -ne 0)
        UpToDate = (($state -band 0xFF) -eq 0)
        Hex      = ('0x{0:X6}' -f $state)
    }
}

function Get-AvOfficeEdition([string]$path) {
    switch -Regex ($path) {
        '\\Office12\\' { return 'Office 2007 (hết hỗ trợ)' }
        '\\Office14\\' { return 'Office 2010 (hết hỗ trợ từ 10/2020)' }
        '\\Office15\\' { return 'Office 2013 (hết hỗ trợ từ 04/2023)' }
        '\\Office16\\' { return 'Office 2016 trở lên / Microsoft 365' }
        default        { return 'Không xác định' }
    }
}

function Get-AvDiagnosticRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { $roots.Add((Join-Path $base 'Microsoft Office')) }
    }
    $profiles = @(Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue)
    foreach ($profile in $profiles) { $roots.Add((Join-Path $profile.FullName 'AppData\Local\Programs\Zalo')) }
    if ($env:LOCALAPPDATA) { $roots.Add((Join-Path $env:LOCALAPPDATA 'Programs\Zalo')) }
    @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
}

function Get-AvDiagnostic([string[]]$Roots, [int]$MaxFiles = 4000, [int]$Days = 30) {
    $notes = New-Object System.Collections.Generic.List[string]

    # 1. Antivirus registered with Windows Security Center.
    $products = @(try {
        Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            $state = ConvertFrom-AvProductState ([long]$_.productState)
            [pscustomobject]@{ Name = [string]$_.displayName; Enabled = $state.Enabled; UpToDate = $state.UpToDate; State = $state.Hex }
        }
    } catch { $notes.Add('Không đọc được Security Center: ' + $_.Exception.Message) })

    # 2. Microsoft Defender status, detections and exclusions.
    $defender = $null
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $defender = [pscustomobject]@{
            Mode = [string]$status.AMRunningMode; RealTime = [bool]$status.RealTimeProtectionEnabled
            Signatures = [string]$status.AntivirusSignatureLastUpdated
        }
    } catch { $notes.Add('Không đọc được trạng thái Defender (có thể Defender đang bị AV khác thay thế).') }

    $names = @{}
    try { foreach ($threat in @(Get-MpThreat -ErrorAction Stop)) { $names[[string]$threat.ThreatID] = [string]$threat.ThreatName } } catch { }
    $since = (Get-Date).AddDays(-$Days)
    $detections = @(try {
        Get-MpThreatDetection -ErrorAction Stop | Where-Object { -not $_.InitialDetectionTime -or [datetime]$_.InitialDetectionTime -ge $since } | ForEach-Object {
            $id = [string]$_.ThreatID
            [pscustomobject]@{
                Time = [string]$_.InitialDetectionTime
                Threat = $(if ($names.ContainsKey($id)) { $names[$id] } else { 'ThreatID ' + $id })
                Resources = @($_.Resources | ForEach-Object { ([string]$_) -replace '^[a-z]+:_', '' })
            }
        }
    } catch { })

    $exclusions = @(try {
        $pref = Get-MpPreference -ErrorAction Stop
        @($pref.ExclusionPath) + @($pref.ExclusionProcess) | Where-Object { $_ -and $_ -notmatch '^N/A' }
    } catch { })

    # 3. Kaspersky / other vendor event logs (names only from the log, trimmed).
    $vendorEvents = @(try {
        foreach ($log in @(Get-WinEvent -ListLog '*Kaspersky*' -ErrorAction Stop | Where-Object RecordCount)) {
            Get-WinEvent -LogName $log.LogName -MaxEvents 200 -ErrorAction Stop | Where-Object { $_.Level -in 1,2,3 -and $_.TimeCreated -ge $since } |
                Select-Object -First 20 | ForEach-Object {
                    $text = ([string]$_.Message) -replace '\s+', ' '
                    if ($text.Length -gt 240) { $text = $text.Substring(0, 240) + '…' }
                    [pscustomobject]@{ Time = [string]$_.TimeCreated; Log = $log.LogName; Message = $text }
                }
        }
    } catch { })

    # 4. Classic file-infector markers (Neshta and similar change how .exe files open).
    $infector = New-Object System.Collections.Generic.List[string]
    foreach ($kind in 'exefile','comfile') {
        try {
            $command = [string](Get-ItemProperty -LiteralPath ('Registry::HKEY_CLASSES_ROOT\{0}\shell\open\command' -f $kind) -ErrorAction Stop).'(default)'
            if ($command -and $command.Trim() -notmatch '^"%1"\s*%\*$') { $infector.Add(('{0} mở bằng: {1}' -f $kind, $command)) }
        } catch { }
    }
    foreach ($marker in 'svchost.com','directx.sys') {
        $path = '{0}\{1}' -f $env:windir, $marker
        if (Test-Path -LiteralPath $path) { $infector.Add('Có tệp lạ: ' + $path) }
    }

    # 5. Authenticode check of Office / Zalo binaries.
    if (-not $Roots) { $Roots = @(Get-AvDiagnosticRoots) }
    $modified = New-Object System.Collections.Generic.List[object]
    $untrusted = New-Object System.Collections.Generic.List[object]
    $unsignedExe = New-Object System.Collections.Generic.List[string]
    $unsignedDll = 0; $scanned = 0; $truncated = $false
    $office = @()
    foreach ($root in $Roots) {
        # -Include is ignored together with -LiteralPath on Windows PowerShell 5.1; filter the extension here.
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.exe','.dll' })) {
            if ($scanned -ge $MaxFiles) { $truncated = $true; break }
            $scanned++
            if ($file.Name -ieq 'WINWORD.EXE') { $office += [pscustomobject]@{ Path = $file.FullName; Edition = (Get-AvOfficeEdition $file.FullName) } }
            try { $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName -ErrorAction Stop } catch { continue }
            $status = [string]$signature.Status
            switch ($status) {
                'Valid' { }
                'HashMismatch' { $modified.Add([pscustomobject]@{ Path = $file.FullName; Status = $status }) }
                'NotSigned' { if ($file.Extension -ieq '.exe') { $unsignedExe.Add($file.FullName) } else { $unsignedDll++ } }
                default { $untrusted.Add([pscustomobject]@{ Path = $file.FullName; Status = $status }) }
            }
        }
    }

    # 6. Traces of external activation tools (reported only; KMS can be a legitimate organisation setup).
    $activation = New-Object System.Collections.Generic.List[string]
    $pattern = 'AutoKMS|AutoPico|KMSAuto|KMSpico|KMS_VL|KMSEmulator|Office\s*20\d\d\s*Toolkit|Microsoft Toolkit|AAct'
    try { foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match $pattern -or $_.TaskPath -match $pattern })) { $activation.Add('Tác vụ: ' + $task.TaskPath + $task.TaskName) } } catch { }
    try { foreach ($service in @(Get-Service -ErrorAction Stop | Where-Object { $_.Name -match $pattern -or $_.DisplayName -match $pattern -or $_.Name -eq 'Service_KMS' })) { $activation.Add('Dịch vụ: ' + $service.Name + ' (' + $service.Status + ')') } } catch { }
    $folders = @(($env:windir + '\AutoKMS'), ($env:windir + '\KMSAutoS'), ($env:ProgramData + '\KMSAutoS'),
        ($env:windir + '\System32\SECOH-QAD.dll'), ($env:windir + '\System32\SECOH-QAD.exe'))
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($base) { $folders += ($base + '\KMSpico'); $folders += ($base + '\Microsoft Toolkit') } }
    foreach ($path in $folders) { if ($path -and (Test-Path -LiteralPath $path)) { $activation.Add('Đường dẫn: ' + $path) } }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SppExtComObj.exe') {
        $activation.Add('Registry: Image File Execution Options\SppExtComObj.exe (hook kích hoạt KMS)')
    }

    [pscustomobject]@{
        Computer = $env:COMPUTERNAME; Date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Days = $Days
        Products = $products; Defender = $defender; Detections = $detections; Exclusions = $exclusions; VendorEvents = $vendorEvents
        Infector = $infector.ToArray(); Roots = [string[]]@($Roots); Scanned = $scanned; Truncated = $truncated
        Modified = $modified.ToArray(); Untrusted = $untrusted.ToArray(); UnsignedExe = $unsignedExe.ToArray(); UnsignedDll = $unsignedDll
        Office = @($office); Activation = $activation.ToArray(); Notes = $notes.ToArray()
    }
}

function Get-AvConclusion($report) {
    $result = New-Object System.Collections.Generic.List[string]
    $threats = @($report.Detections | ForEach-Object Threat) + @($report.VendorEvents | ForEach-Object Message)
    $virusNames = @($threats | Where-Object { $_ -match '(?i)\bVirus[:.]|Neshta|Virut|Sality|Ramnit|Expiro' })
    if (@($report.Infector).Count -or @($report.Modified).Count -or $virusNames.Count) {
        $result.Add('[NGHIÊM TRỌNG] Có dấu hiệu virus lây file .exe. Rút mạng, không cắm USB sang máy khác; quét offline (Kaspersky Rescue Disk / Microsoft Defender Offline), sau đó cài lại các ứng dụng bị sửa. Không khôi phục tệp từ vùng cách ly.')
    }
    $toolNames = @($threats | Where-Object { $_ -match '(?i)HackTool|RiskTool|KMS|AutoKMS|Keygen|Crack|Patch' })
    if (@($report.Activation).Count -or $toolNames.Count) {
        $result.Add('[KHẢ NĂNG CAO] Có công cụ kích hoạt bên ngoài / bị nhận là HackTool. AV chặn công cụ này có thể làm Office / ứng dụng liên quan không mở được. Gỡ công cụ, quét lại, rồi dùng bản quyền hợp lệ hoặc phần mềm miễn phí thay thế.')
    }
    $mlNames = @($threats | Where-Object { $_ -match '(?i)!ml\b|Wacatac|Heur|PDM:|Generic' })
    if ($mlNames.Count -and -not $result.Count) {
        $result.Add('[CÓ THỂ BÁO NHẦM] Tên phát hiện dạng heuristic / máy học. Nếu tệp bị báo có chữ ký số Valid của hãng: cập nhật định nghĩa virus, gửi mẫu báo nhầm cho hãng AV, cài lại ứng dụng từ trang chính thức.')
    }
    if (@($report.Office | Where-Object { $_.Edition -match 'hết hỗ trợ' }).Count) {
        $result.Add('[LƯU Ý] Office trên máy đã hết hỗ trợ, không còn bản vá bảo mật; nên thay bằng bản được hỗ trợ.')
    }
    $active = @($report.Products | Where-Object Enabled)
    if (@($report.Products).Count -and -not $active.Count) {
        $result.Add('[LƯU Ý] Security Center báo không có AV nào đang bật bảo vệ thời gian thực. Kiểm tra AV có bị tắt / hết hạn không.')
    }
    $broad = @($report.Exclusions | Where-Object { $_ -match '^[A-Za-z]:\\?$' -or $_ -match '(?i)^[A-Za-z]:\\(Windows|Users|Program Files( \(x86\))?|ProgramData)\\?$' -or $_ -match '(?i)\\(Temp|AppData)\\?$' })
    if ($broad.Count) {
        $result.Add('[KIỂM TRA GẤP] Defender đang bỏ qua cả vùng rộng: ' + ($broad -join ', ') + '. Mọi tệp trong đó không được quét. Nếu không phải bạn chủ động thêm, xoá ngoại lệ này trong Windows Security rồi quét lại toàn bộ.')
    }
    elseif (@($report.Exclusions).Count) {
        $result.Add('[KIỂM TRA] Defender có ngoại lệ. Mã độc và công cụ crack hay tự thêm ngoại lệ; đối chiếu danh sách bên dưới.')
    }
    if (-not $result.Count) {
        $result.Add('Chưa thấy dấu hiệu nhiễm hoặc công cụ kích hoạt ở các vị trí đã quét. Mở Báo cáo / Vùng cách ly của AV đang dùng để lấy tên mối đe dọa và đường dẫn tệp bị chặn.')
    }
    $result.ToArray()
}

function Format-AvDiagnostic($report) {
    $lines = New-Object System.Collections.Generic.List[string]
    $add = { param($text) $lines.Add([string]$text) }
    & $add 'TECHMASTER — CHẨN ĐOÁN ỨNG DỤNG BỊ BÁO VIRUS (chỉ đọc)'
    & $add ('Máy: ' + $report.Computer + '   Thời điểm: ' + $report.Date)
    & $add ''
    & $add '== KẾT LUẬN SƠ BỘ =='
    foreach ($line in (Get-AvConclusion $report)) { & $add ('• ' + $line) }

    & $add ''; & $add '== PHẦN MỀM DIỆT VIRUS (Security Center) =='
    foreach ($p in $report.Products) { & $add ('{0} | Bảo vệ: {1} | Định nghĩa: {2} | {3}' -f $p.Name, $(if ($p.Enabled) { 'BẬT' } else { 'TẮT' }), $(if ($p.UpToDate) { 'mới' } else { 'CŨ' }), $p.State) }
    if (-not @($report.Products).Count) { & $add 'Không đọc được danh sách AV.' }
    if ($report.Defender) { & $add ('Defender: chế độ {0}, thời gian thực {1}, định nghĩa {2}' -f $report.Defender.Mode, $(if ($report.Defender.RealTime) { 'bật' } else { 'tắt' }), $report.Defender.Signatures) }

    & $add ''; & $add ('== DEFENDER ĐÃ PHÁT HIỆN ({0} ngày) ==' -f $report.Days)
    foreach ($d in $report.Detections) { & $add ($d.Time + ' | ' + $d.Threat); foreach ($r in $d.Resources) { & $add ('    ' + $r) } }
    if (-not @($report.Detections).Count) { & $add 'Không có. (Nếu máy dùng Kaspersky / AV khác, xem Báo cáo của AV đó.)' }

    & $add ''; & $add '== NHẬT KÝ KASPERSKY (cảnh báo / lỗi) =='
    foreach ($e in $report.VendorEvents) { & $add ($e.Time + ' | ' + $e.Message) }
    if (-not @($report.VendorEvents).Count) { & $add 'Không đọc được hoặc không có. Mở Kaspersky → Báo cáo / Vùng cách ly để xem tên mối đe dọa.' }

    & $add ''; & $add '== DẤU HIỆU VIRUS LÂY FILE .EXE =='
    foreach ($i in $report.Infector) { & $add ('[!] ' + $i) }
    if (-not @($report.Infector).Count) { & $add 'Không thấy (lệnh mở .exe chuẩn "%1" %*, không có svchost.com / directx.sys trong Windows).' }

    & $add ''; & $add ('== CHỮ KÝ SỐ OFFICE / ZALO (đã quét {0} tệp{1}) ==' -f $report.Scanned, $(if ($report.Truncated) { ', đã dừng ở giới hạn' } else { '' }))
    foreach ($r in $report.Roots) { & $add ('Thư mục: ' + $r) }
    foreach ($o in $report.Office) { & $add ('Word: ' + $o.Path + ' → ' + $o.Edition) }
    & $add ('Bị sửa (HashMismatch): ' + @($report.Modified).Count)
    foreach ($m in $report.Modified) { & $add ('[!] ' + $m.Path) }
    & $add ('Chữ ký không tin cậy / lỗi: ' + @($report.Untrusted).Count)
    foreach ($u in $report.Untrusted) { & $add ('    ' + $u.Status + ' | ' + $u.Path) }
    & $add ('EXE không ký: ' + @($report.UnsignedExe).Count + '   DLL không ký: ' + $report.UnsignedDll + ' (DLL thư viện Qt / ffmpeg của Zalo không ký là bình thường)')
    foreach ($x in $report.UnsignedExe) { & $add ('    ' + $x) }

    & $add ''; & $add '== DẤU VẾT CÔNG CỤ KÍCH HOẠT BÊN NGOÀI =='
    foreach ($a in $report.Activation) { & $add ('[?] ' + $a) }
    if (-not @($report.Activation).Count) { & $add 'Không thấy ở các vị trí thường gặp (tác vụ, dịch vụ, thư mục, IFEO).' }
    & $add 'Công cụ chỉ báo dấu vết, không kết luận bản quyền và không tự xoá.'

    & $add ''; & $add '== NGOẠI LỆ DEFENDER =='
    foreach ($e in $report.Exclusions) { & $add ('    ' + $e) }
    if (-not @($report.Exclusions).Count) { & $add 'Không có hoặc không đọc được.' }

    foreach ($n in $report.Notes) { & $add ('Ghi chú: ' + $n) }
    ($lines -join "`r`n")
}
