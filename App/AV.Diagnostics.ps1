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

function Get-AvThreatStatusText([int]$id) {
    # MPTHREAT_STATUS (MpClient.h): 0-6 normal outcomes, 102-107 failed / abandoned.
    switch ($id) {
        0 { 'Không rõ (0)' } 1 { 'Mới phát hiện, chưa xử lý (1)' } 2 { 'Đã diệt (2)' } 3 { 'Đã cách ly (3)' }
        4 { 'Đã xoá (4)' } 5 { 'Đã cho phép lúc phát hiện (5)' } 6 { 'Đã chặn (6)' }
        102 { 'DIỆT THẤT BẠI (102)' } 103 { 'CÁCH LY THẤT BẠI (103)' } 104 { 'XOÁ THẤT BẠI (104)' }
        105 { 'CHO PHÉP THẤT BẠI (105)' } 106 { 'BỎ DỞ (106)' } 107 { 'CHẶN THẤT BẠI (107)' }
        default { 'Mã ' + $id + ' (không có trong tài liệu Microsoft)' }
    }
}

function Get-AvDriveTypes {
    # One bounded query. Disconnected network drives can otherwise block for minutes.
    $types = @{}
    try { foreach ($disk in @(Get-CimInstance -ClassName Win32_LogicalDisk -OperationTimeoutSec 10 -ErrorAction Stop)) { $types[([string]$disk.DeviceID).ToUpperInvariant()] = [int]$disk.DriveType } } catch { }
    $types
}

function Test-AvLocalPath([string]$path, [hashtable]$types) {
    # Only touch fixed (3) and removable (2) drives that are present; never wait on network / missing drives.
    if ($path -notmatch '^([A-Za-z]:)\\') { return $false }
    $drive = $Matches[1].ToUpperInvariant()
    if ($types.Count -and $types[$drive] -notin 2, 3) { return $false }
    [bool](Test-Path -LiteralPath $path)
}

function Get-AvDriveSummary($detections, [hashtable]$types) {
    if (-not $types) { $types = Get-AvDriveTypes }
    $paths = @($detections | ForEach-Object { $_.Files } | ForEach-Object { $_.Path } | Where-Object { $_ -match '^[A-Za-z]:' } | Sort-Object -Unique)
    @($paths | Group-Object { $_.Substring(0, 2).ToUpperInvariant() } | Sort-Object Name | ForEach-Object {
        $kind = switch ($types[$_.Name]) { 2 { 'ổ di động / USB' } 3 { 'ổ trong máy' } 4 { 'ổ mạng' } 5 { 'đĩa CD/DVD' } default { 'không rõ loại / đã rút' } }
        [pscustomobject]@{ Drive = $_.Name; Count = $_.Count; Kind = $kind; Removable = (($types[$_.Name] -eq 2) -or ((-not $types.ContainsKey($_.Name)) -and ($_.Name -ne 'C:'))) }
    })
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

function Set-AvProgress($Progress, [int]$Step, [int]$Percent, [string]$Stage) {
    # $Progress is a synchronized hashtable shared with the UI thread; optional.
    if ($null -eq $Progress) { return }
    $Progress.Step = $Step; $Progress.Steps = 6; $Progress.Percent = $Percent; $Progress.Stage = $Stage
}

function Get-AvDiagnostic([string[]]$Roots, [int]$MaxFiles = 4000, [int]$Days = 30, [hashtable]$Progress, [switch]$Deep) {
    $notes = New-Object System.Collections.Generic.List[string]
    Set-AvProgress $Progress 1 3 'Đang đọc phần mềm diệt virus trong Security Center…'

    # 1. Antivirus registered with Windows Security Center.
    $products = @(try {
        Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            $state = ConvertFrom-AvProductState ([long]$_.productState)
            [pscustomobject]@{ Name = [string]$_.displayName; Enabled = $state.Enabled; UpToDate = $state.UpToDate; State = $state.Hex }
        }
    } catch { $notes.Add('Không đọc được Security Center: ' + $_.Exception.Message) })

    # 2. Microsoft Defender status, detections and exclusions.
    Set-AvProgress $Progress 2 10 'Đang đọc lịch sử phát hiện và ngoại lệ của Defender…'
    $defender = $null
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $defender = [pscustomobject]@{
            Mode = [string]$status.AMRunningMode; RealTime = [bool]$status.RealTimeProtectionEnabled
            Signatures = [string]$status.AntivirusSignatureLastUpdated
        }
    } catch { $notes.Add('Không đọc được trạng thái Defender (có thể Defender đang bị AV khác thay thế).') }

    $names = @{}; $executed = @{}
    try {
        foreach ($threat in @(Get-MpThreat -ErrorAction Stop)) {
            $names[[string]$threat.ThreatID] = [string]$threat.ThreatName
            if ($threat.DidThreatExecute) { $executed[[string]$threat.ThreatID] = $true }
        }
    } catch { }

    $exclusions = @(); $allowedIds = @{}
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $exclusions = @(@($pref.ExclusionPath) + @($pref.ExclusionProcess) | Where-Object { $_ -and $_ -notmatch '^N/A' })
        # @($null).Count is 1 on Windows PowerShell 5.1: drop empty entries before indexing.
        $ids = @($pref.ThreatIDDefaultAction_Ids | Where-Object { $null -ne $_ }); $actions = @($pref.ThreatIDDefaultAction_Actions | Where-Object { $null -ne $_ })
        for ($i = 0; $i -lt $ids.Count; $i++) { if ($i -lt $actions.Count -and [int]$actions[$i] -eq 6) { $allowedIds[[string]$ids[$i]] = $true } }
    } catch { }

    $since = (Get-Date).AddDays(-$Days)
    $driveTypes = Get-AvDriveTypes
    $detections = @(try {
        Get-MpThreatDetection -ErrorAction Stop | Where-Object { -not $_.InitialDetectionTime -or [datetime]$_.InitialDetectionTime -ge $since } | ForEach-Object {
            $id = [string]$_.ThreatID
            $statusId = if ($null -ne $_.ThreatStatusID) { [int]$_.ThreatStatusID } else { 0 }
            $files = @($_.Resources | Where-Object { ([string]$_) -match '^(file|containerfile):_' } | ForEach-Object {
                $path = ([string]$_) -replace '^[a-z]+:_', ''
                [pscustomobject]@{ Path = $path; Present = (Test-AvLocalPath $path $driveTypes) }
            })
            [pscustomobject]@{
                Time = $(if ($_.InitialDetectionTime) { [datetime]$_.InitialDetectionTime } else { [datetime]::MinValue })
                ThreatID = $id
                Threat = $(if ($names.ContainsKey($id)) { $names[$id] } else { 'ThreatID ' + $id })
                StatusId = $statusId; Status = (Get-AvThreatStatusText $statusId)
                Failed = ($statusId -eq 1 -or $statusId -ge 100 -or $statusId -notin 0,1,2,3,4,5,6)
                Allowed = $allowedIds.ContainsKey($id)
                Executed = $executed.ContainsKey($id)
                Files = $files
            }
        } | Sort-Object Time -Descending
    } catch { })
    $drives = @(Get-AvDriveSummary $detections $driveTypes)

    # 3. Kaspersky / other vendor event logs (names only from the log, trimmed).
    Set-AvProgress $Progress 3 20 'Đang đọc nhật ký Kaspersky…'
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
    Set-AvProgress $Progress 4 25 'Đang kiểm tra dấu hiệu virus lây file (Neshta, Floxif)…'
    $infector = New-Object System.Collections.Generic.List[string]
    foreach ($kind in 'exefile','comfile') {
        try {
            $command = [string](Get-ItemProperty -LiteralPath ('Registry::HKEY_CLASSES_ROOT\{0}\shell\open\command' -f $kind) -ErrorAction Stop).'(default)'
            if ($command -and $command.Trim() -notmatch '^"%1"\s*%\*$') { $infector.Add(('{0} mở bằng: {1}' -f $kind, $command)) }
        } catch { }
    }
    foreach ($marker in 'svchost.com','directx.sys') {
        $path = '{0}\{1}' -f $env:windir, $marker
        if (Test-Path -LiteralPath $path) { $infector.Add('Có tệp lạ (Neshta): ' + $path) }
    }
    # Floxif drops its infection module into Common Files\System and may load it through AppInit_DLLs.
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Sort-Object -Unique) {
        foreach ($marker in 'symsrv.dll','ffff.dll') {
            $path = '{0}\Common Files\System\{1}' -f $base, $marker
            if (Test-Path -LiteralPath $path) { $infector.Add('Có tệp lạ (Floxif): ' + $path) }
        }
    }
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $dlls = ([string]$item.AppInit_DLLs).Trim()
            if ($dlls -and [int]$item.LoadAppInit_DLLs -eq 1) { $infector.Add('AppInit_DLLs đang nạp: ' + $dlls + '  (' + $key + ')') }
        } catch { }
    }

    # 5. Authenticode check of Office / Zalo binaries.
    if (-not $Roots) { $Roots = @(Get-AvDiagnosticRoots) }
    $modified = New-Object System.Collections.Generic.List[object]
    $untrusted = New-Object System.Collections.Generic.List[object]
    $unsignedExe = New-Object System.Collections.Generic.List[string]
    $unsignedDll = 0; $scanned = 0; $truncated = $false
    $office = @()
    Set-AvProgress $Progress 5 30 'Đang liệt kê tệp Office / Zalo…'
    # -Include is ignored together with -LiteralPath on Windows PowerShell 5.1; filter the extension here.
    # Light mode (default) checks only .exe: reading every .dll makes Defender rescan hundreds of files.
    $extensions = if ($Deep) { @('.exe', '.dll') } else { @('.exe') }
    $binaries = @(foreach ($root in $Roots) { Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in $extensions } })
    if ($binaries.Count -gt $MaxFiles) { $truncated = $true; $binaries = @($binaries | Select-Object -First $MaxFiles) }
    $total = [Math]::Max(1, $binaries.Count)
    foreach ($file in $binaries) {
        $scanned++
        if ($scanned -eq 1 -or $scanned % 10 -eq 0 -or $scanned -eq $binaries.Count) {
            Set-AvProgress $Progress 5 (30 + [int](60 * $scanned / $total)) ('Đang kiểm tra chữ ký số: {0} / {1} tệp' -f $scanned, $binaries.Count)
        }
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

    # 6. Traces of external activation tools (reported only; KMS can be a legitimate organisation setup).
    Set-AvProgress $Progress 6 93 'Đang tìm dấu vết công cụ kích hoạt…'
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
        Products = $products; Defender = $defender; Detections = $detections; Drives = $drives; AllowedIds = @($allowedIds.Keys); Exclusions = $exclusions; VendorEvents = $vendorEvents
        Infector = $infector.ToArray(); Roots = [string[]]@($Roots); Scanned = $scanned; Truncated = $truncated; Deep = [bool]$Deep
        Modified = $modified.ToArray(); Untrusted = $untrusted.ToArray(); UnsignedExe = $unsignedExe.ToArray(); UnsignedDll = $unsignedDll
        Office = @($office); Activation = $activation.ToArray(); Notes = $notes.ToArray()
    }
}

function Get-AvConclusion($report) {
    $result = New-Object System.Collections.Generic.List[string]
    $threats = @($report.Detections | ForEach-Object Threat) + @($report.VendorEvents | ForEach-Object Message)
    $virusNames = @($threats | Where-Object { $_ -match '(?i)\bVirus[:.]|Neshta|Virut|Sality|Ramnit|Expiro' })
    $current = (@($report.Infector).Count -or @($report.Modified).Count)
    if ($current) {
        $result.Add('[NGHIÊM TRỌNG] ĐANG có dấu hiệu virus lây file .exe (xem mục Dấu hiệu virus lây file / tệp bị sửa). Rút mạng, không cắm USB sang máy khác; quét offline (Microsoft Defender Offline / Kaspersky Rescue Disk), sau đó cài lại các ứng dụng bị sửa. Không khôi phục tệp từ vùng cách ly.')
    } elseif ($virusNames.Count) {
        $result.Add('[NGHIÊM TRỌNG] Máy ĐÃ TỪNG nhiễm virus lây file trong ' + $report.Days + ' ngày qua (' + (@($virusNames | Sort-Object -Unique) -join ', ') + '). Hiện không thấy module thường trú hay tệp bị sửa ở các vị trí đã kiểm tra; vẫn nên quét toàn bộ / quét offline và quét mọi USB đã cắm vào máy.')
    }
    $ran = @($report.Detections | Where-Object Executed | ForEach-Object Threat | Sort-Object -Unique)
    if ($ran.Count) {
        $result.Add('[NGHIÊM TRỌNG] Mã độc đã từng CHẠY trên máy (' + ($ran -join ', ') + '). Diệt xong chưa đủ để tin máy sạch: chép dữ liệu (không chép .exe / .dll / bộ cài), cài lại Windows, đổi mật khẩu email / ngân hàng / GitHub từ một máy sạch.')
    }
    # "Allowed" is urgent only while it is still in force: the ID is in Defender's allow list,
    # or an allowed file is still on disk. An old status-5 record for a file cleaned later is history.
    $allowedNow = @($report.Detections | Where-Object { ($report.AllowedIds -contains $_.ThreatID) -or ($_.StatusId -eq 5 -and @($_.Files | Where-Object Present).Count) } | ForEach-Object Threat | Sort-Object -Unique)
    $allowedPast = @($report.Detections | Where-Object { $_.StatusId -eq 5 } | ForEach-Object Threat | Sort-Object -Unique | Where-Object { $_ -notin $allowedNow })
    if ($allowedNow.Count -or @($report.AllowedIds).Count) {
        $result.Add('[KIỂM TRA GẤP] Có mối đe dọa đang được "Cho phép"' + $(if ($allowedNow.Count) { ' (' + ($allowedNow -join ', ') + ')' } else { '' }) + '. Defender sẽ bỏ qua mọi tệp mang cùng mã này. Dùng Sửa lỗi… để gỡ, hoặc Windows Security → Protection history → Allowed threats → Don''t allow.')
    } elseif ($allowedPast.Count) {
        $result.Add('[LƯU Ý] Từng có lần bấm "Cho phép" (' + ($allowedPast -join ', ') + '), nay tệp đã được xử lý và danh sách cho phép của Defender trống. Nên mở Windows Security → Protection history → Allowed threats một lần để chắc chắn.')
    }
    $present = @($report.Detections | Where-Object { $_.StatusId -ne 2 } | ForEach-Object { $_.Files } | Where-Object Present | ForEach-Object Path | Sort-Object -Unique)
    $cleaned = @($report.Detections | Where-Object { $_.StatusId -eq 2 } | ForEach-Object { $_.Files } | Where-Object Present | ForEach-Object Path | Where-Object { $_ -notin $present } | Sort-Object -Unique)
    if ($present.Count) {
        $result.Add('[KIỂM TRA] ' + $present.Count + ' tệp từng bị phát hiện VẪN CÒN trên ổ (đánh dấu [CÒN TRÊN Ổ] bên dưới). Xoá và tải lại bộ cài từ trang hãng, không chạy lại.')
    }
    if ($cleaned.Count) {
        $result.Add('[LƯU Ý] ' + $cleaned.Count + ' tệp Defender báo đã diệt nhưng vẫn để lại trên ổ ([CÒN TRÊN Ổ, ĐÃ DIỆT]). Với bộ cài, nên xoá và tải lại từ trang hãng thay vì dùng bản đã diệt.')
    }
    if (@($report.Detections).Count -and -not (@($report.Detections | ForEach-Object { $_.Files } | Where-Object Present).Count)) {
        $result.Add('[ĐÃ XỬ LÝ] Không còn tệp nào từng bị phát hiện trên ổ.')
    }
    $removable = @($report.Drives | Where-Object Removable | ForEach-Object Drive)
    if ($removable.Count) {
        $result.Add('[KIỂM TRA] Có phát hiện trên ổ ngoài / USB (' + ($removable -join ', ') + '). Virus lây file lan qua USB: quét các ổ này và mọi máy đã cắm chúng.')
    }
    $toolNames = @($threats | Where-Object { $_ -match '(?i)HackTool|RiskTool|KMS|AutoKMS|Keygen|Crack|Patch' })
    if (@($report.Activation).Count -or $toolNames.Count) {
        $result.Add('[KHẢ NĂNG CAO] Có công cụ kích hoạt bên ngoài / bị nhận là HackTool. AV chặn công cụ này có thể làm Office / ứng dụng liên quan không mở được. Gỡ công cụ, quét lại, rồi dùng bản quyền hợp lệ hoặc phần mềm miễn phí thay thế.')
    }
    $mlNames = @($threats | Where-Object { $_ -match '(?i)!ml\b|Wacatac|Heur|PDM:|Generic' })
    if ($mlNames.Count -and -not @($result | Where-Object { $_ -match '^\[(NGHIÊM|KHẢ)' }).Count) {
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

    & $add ''; & $add ('== DEFENDER ĐÃ PHÁT HIỆN ({0} ngày, mới nhất trước) ==' -f $report.Days)
    if (@($report.Drives).Count) { & $add ('Theo ổ: ' + ((@($report.Drives) | ForEach-Object { '{0} {1} tệp ({2})' -f $_.Drive, $_.Count, $_.Kind }) -join ' | ')) }
    foreach ($d in $report.Detections) {
        $flags = @(); if ($d.Executed) { $flags += 'ĐÃ CHẠY' }; if ($d.Allowed) { $flags += 'ĐANG ĐƯỢC CHO PHÉP' } elseif ($d.StatusId -eq 5 -and @($d.Files | Where-Object Present).Count) { $flags += 'ĐÃ CHO PHÉP, TỆP VẪN CÒN' }
        & $add ('{0} | {1} | {2}{3}' -f $(if ($d.Time -ne [datetime]::MinValue) { $d.Time.ToString('yyyy-MM-dd HH:mm') } else { '?' }), $d.Threat, $d.Status, $(if ($flags.Count) { ' | ' + ($flags -join ', ') } else { '' }))
        foreach ($f in $d.Files) { & $add ('    {0}{1}' -f $(if ($f.Present -and $d.StatusId -eq 2) { '[CÒN TRÊN Ổ, ĐÃ DIỆT] ' } elseif ($f.Present) { '[CÒN TRÊN Ổ] ' } else { '' }), $f.Path) }
    }
    if (-not @($report.Detections).Count) { & $add 'Không có. (Nếu máy dùng Kaspersky / AV khác, xem Báo cáo của AV đó.)' }

    & $add ''; & $add '== NHẬT KÝ KASPERSKY (cảnh báo / lỗi) =='
    foreach ($e in $report.VendorEvents) { & $add ($e.Time + ' | ' + $e.Message) }
    if (-not @($report.VendorEvents).Count) { & $add 'Không đọc được hoặc không có. Mở Kaspersky → Báo cáo / Vùng cách ly để xem tên mối đe dọa.' }

    & $add ''; & $add '== DẤU HIỆU VIRUS LÂY FILE .EXE (Neshta, Floxif) =='
    foreach ($i in $report.Infector) { & $add ('[!] ' + $i) }
    if (-not @($report.Infector).Count) { & $add 'Không thấy (lệnh mở .exe chuẩn "%1" %*; không có svchost.com / directx.sys; không có symsrv.dll / ffff.dll trong Common Files\System; AppInit_DLLs không nạp).' }

    & $add ''; & $add ('== CHỮ KÝ SỐ OFFICE / ZALO ({0}: {1} tệp{2}) ==' -f $(if ($report.Deep) { 'quét sâu .exe + .dll' } else { 'chế độ nhẹ, chỉ .exe' }), $report.Scanned, $(if ($report.Truncated) { ', đã dừng ở giới hạn' } else { '' }))
    foreach ($r in $report.Roots) { & $add ('Thư mục: ' + $r) }
    foreach ($o in $report.Office) { & $add ('Word: ' + $o.Path + ' → ' + $o.Edition) }
    & $add ('Bị sửa (HashMismatch): ' + @($report.Modified).Count)
    foreach ($m in $report.Modified) { & $add ('[!] ' + $m.Path) }
    & $add ('Chữ ký không tin cậy / lỗi: ' + @($report.Untrusted).Count)
    foreach ($u in $report.Untrusted) { & $add ('    ' + $u.Status + ' | ' + $u.Path) }
    & $add ('EXE không ký: ' + @($report.UnsignedExe).Count + $(if ($report.Deep) { '   DLL không ký: ' + $report.UnsignedDll + ' (DLL thư viện Qt / ffmpeg của Zalo không ký là bình thường)' } else { '   DLL: không kiểm tra ở chế độ nhẹ (tích Quét sâu khi máy rảnh)' }))
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
