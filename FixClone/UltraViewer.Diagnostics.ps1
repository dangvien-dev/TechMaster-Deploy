# Read-only UltraViewer clone diagnostics. Never stops a remote session or edits identity/network settings.
function Get-UltraViewerDiagnostic {
    $ErrorActionPreference = 'Stop'
    $applications = @(foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^UltraViewer(?:\s|$)' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.DisplayName; Version = $_.DisplayVersion; Location = $_.InstallLocation } }
    })
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='UltraViewer_Desktop.exe' OR Name='UltraViewer_Service.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Id = $_.ProcessId } })
    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object MacAddress |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.InterfaceDescription; Mac = $_.MacAddress; Physical = $_.HardwareInterface; Status = [string]$_.Status } })
    $overrides = @(Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.NetworkAddress } | ForEach-Object { [pscustomobject]@{ Adapter = $_.DriverDesc; MacOverride = $_.NetworkAddress } })
    $fields = @(foreach ($key in 'HKLM:\SOFTWARE\UltraViewer','HKLM:\SOFTWARE\WOW6432Node\UltraViewer','HKCU:\SOFTWARE\UltraViewer') {
        if (Test-Path -LiteralPath $key) {
            $item = Get-Item -LiteralPath $key -ErrorAction Stop
            # Metadata only: neither registry values nor passwords are exported.
            [pscustomobject]@{ Key = $key; ValueNames = @($item.GetValueNames() | Where-Object { $_ -notmatch '(?i)pass|token|secret|credential' }) }
        }
    })
    [pscustomobject]@{ Computer = $env:COMPUTERNAME; Date = (Get-Date).ToString('o'); Applications = $applications; Running = $processes; Adapters = $adapters; MacOverrides = $overrides; RegistryFields = $fields }
}
function Format-UltraViewerDiagnostic($report) {
    $lines = @('TECHMASTER — CHẨN ĐOÁN ULTRAVIEWER', ('Máy: ' + $report.Computer), ('Thời điểm: ' + $report.Date), '', 'Bản đã cài:')
    foreach ($app in $report.Applications) { $lines += $app.Name + ' ' + $app.Version }
    if (-not @($report.Applications).Count) { $lines += 'Không tìm thấy bản cài trong danh sách ứng dụng.' }
    $lines += ''; $lines += 'Tiến trình đang chạy:'
    foreach ($process in $report.Running) { $lines += $process.Name + ' (PID ' + $process.Id + ')' }
    $lines += ''; $lines += 'Card mạng / MAC:'
    foreach ($adapter in $report.Adapters) { $lines += '{0} | {1} | {2} | Physical={3} | {4}' -f $adapter.Name,$adapter.Description,$adapter.Mac,$adapter.Physical,$adapter.Status }
    $lines += ''; $lines += 'MAC đặt thủ công:'
    foreach ($entry in $report.MacOverrides) { $lines += $entry.Adapter + ' | ' + $entry.MacOverride }
    if (-not @($report.MacOverrides).Count) { $lines += 'Không thấy NetworkAddress đặt thủ công.' }
    $lines += ''; $lines += 'Tên trường cấu hình (không xuất giá trị / mật khẩu):'
    foreach ($entry in $report.RegistryFields) { $lines += $entry.Key + ': ' + ($entry.ValueNames -join ', ') }
    $lines += ''; $lines += 'Cần so sánh kết quả từ hai máy đang trùng ID để xác định nguồn trùng. Phiên bản giống nhau không đủ để kết luận.'
    $lines += 'Chẩn đoán chỉ đọc, chưa thay ID, mật khẩu, địa chỉ MAC hoặc dừng UltraViewer.'
    return $lines -join "`r`n"
}
