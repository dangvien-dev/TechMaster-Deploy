# WPF business actions; deployment scripts remain the source of installation behavior.
$offProducts = @(
    @('HomeBusiness2024Retail', 'Office Home & Business 2024 (bán lẻ)', 'Retail'),
    @('HomeBusiness2021Retail', 'Office Home & Business 2021 (bán lẻ)', 'Retail'),
    @('O365BusinessRetail',     'Microsoft 365 Apps for business',       'M365'),
    @('O365ProPlusRetail',      'Microsoft 365 Apps for enterprise',     'M365'),
    @('ProPlus2024Volume',      'Office LTSC Professional Plus 2024 (Volume)', 'Volume'),
    @('Standard2024Volume',     'Office LTSC Standard 2024 (Volume)',    'Volume'),
    @('ProPlus2021Volume',      'Office LTSC Professional Plus 2021 (Volume)', 'Volume')
)

function Start-Tool([string]$file, [string]$label) {
    if (-not (Test-Path $file)) {
        [Windows.MessageBox]::Show("Không tìm thấy:`n$file", 'TechMaster Deploy', 'OK', 'Error') | Out-Null
        return
    }
    # Mỗi công cụ chạy trong cửa sổ console riêng (các script có bước hỏi / xác nhận)
    Start-Process -FilePath 'cmd.exe' -ArgumentList ('/d /s /c ""{0}""' -f $file) -WorkingDirectory (Split-Path $file)
    Set-Status "Đã mở: $label  ($([IO.Path]::GetFileName($file)))"
}

function Get-OffSel {
    $pr = $offProducts[$cbProduct.SelectedIndex]
    $langs = @($languageChoices | Where-Object IsChecked | ForEach-Object { [string]$_.Tag })
    $excl  = @($excludeChoices | Where-Object IsChecked | ForEach-Object { [string]$_.Tag })
    $arch  = if ($rb32.IsChecked) { '32' } else { '64' }
    $dir   = Join-Path $KhoOffice ("{0}_x{1}_{2}" -f $pr[0], $arch, ($langs -join '_'))
    return @{ Id = $pr[0]; Name = $pr[1]; Kind = $pr[2]; Langs = $langs; Excl = $excl; Arch = $arch; Kho = $dir }
}

function Update-OffInfo {
    $sel = Get-OffSel
    switch ($sel.Kind) {
        'Retail' { $lblOffNote.Text = 'Bản lẻ: nhập key đã mua (hoặc nhập sau trong Word). Kênh cập nhật Current.' }
        'M365'   { $lblOffNote.Text = 'Microsoft 365: không cần key, kích hoạt bằng cách đăng nhập tài khoản có bản quyền M365.' }
        'Volume' { $lblOffNote.Text = 'Bản Volume (LTSC): cần key Volume (MAK) / KMS của tổ chức. Không có thì cài xong sẽ chưa kích hoạt.' }
    }
    if ($sel.Langs.Count -eq 0) { $lblKho.Text = 'Chọn ít nhất 1 ngôn ngữ'; $lblKho.Foreground = $cDanger; return }
    if (Test-Path (Join-Path $sel.Kho 'Office')) {
        $lblKho.Text = "Kho: ĐÃ CÓ`n$([IO.Path]::GetFileName($sel.Kho))"; $lblKho.Foreground = '#166534'
    } else {
        $lblKho.Text = "Kho: chưa có`n(bấm Tải về kho)"; $lblKho.Foreground = $cMuted
    }
}

function Finish-ODT([Nullable[int]]$exitCode) {
    $officeTimer.Stop()
    $run = $script:officeRun
    $script:officeRun = $null
    $run.Process.Dispose()
    $script:officeLog = $run.Log
    if ($exitCode -ne 0 -and (Get-Item -LiteralPath $run.ErrorLog -ErrorAction SilentlyContinue).Length -gt 0) {
        $script:officeLog = $run.ErrorLog
    }
    $bOfficeLog.IsEnabled = Test-Path -LiteralPath $script:officeLog -PathType Leaf

    $officeBar.IsIndeterminate = $false
    $officeBar.Value = 0
    if ($exitCode -eq 0) {
        $officeBar.Value = 100
        $lblOfficeProgress.Text = if ($run.Mode -eq 'Download') { 'Đã tải bộ cài về kho.' } elseif ($run.Mode -eq 'Cleanup') { 'Đã kết thúc công cụ gỡ / dọn. Xem nhật ký để biết kết quả.' } else { 'Đã cài Office.' }
        $lblOfficeProgress.Foreground = $cPrimary
    } else {
        $lblOfficeProgress.Text = if ($null -eq $exitCode) {
            'Không xác nhận được kết quả. Mở nhật ký để xem chi tiết.'
        } else {
            "Office báo lỗi (mã $exitCode). Mở nhật ký để xem chi tiết."
        }
        $lblOfficeProgress.Foreground = $cDanger
    }
    Set-Status $lblOfficeProgress.Text
    $bDl.IsEnabled = $true
    $bKho.IsEnabled = $true
    $bNet.IsEnabled = $true
    $bCleanup.IsEnabled = $true
    Update-OffInfo
}

function Start-ODT([string]$mode) {
    if ($script:officeRun) { return }
    $sel = Get-OffSel
    if ($sel.Langs.Count -eq 0) { [Windows.MessageBox]::Show('Chọn ít nhất 1 ngôn ngữ.', 'Office') | Out-Null; return }
    $key = $tbOffKey.Text.Trim().ToUpper()
    if ($key -and $key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') {
        [Windows.MessageBox]::Show('Key sai định dạng XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', 'Office', 'OK', 'Warning') | Out-Null; return
    }
    if ($mode -eq 'InstallKho' -and -not (Test-Path (Join-Path $sel.Kho 'Office'))) {
        [Windows.MessageBox]::Show("Chưa có kho cho lựa chọn này:`n$($sel.Kho)`n`nBấm 'Tải về kho' trước.", 'Office', 'OK', 'Warning') | Out-Null; return
    }
    if ($mode -ne 'Download') {
        $msg = "Cài $($sel.Name) ($($sel.Arch)-bit, $($sel.Langs -join ', ')) lên máy này?"
        if ($chkMsi.IsChecked) { $msg += "`n`nSẽ GỠ Office cũ dạng MSI trước khi cài." }
        if (-not (Confirm-Box $msg 'Cài Office')) { return }
    }
    $excl = if ($sel.Excl.Count) { $sel.Excl -join ',' } else { 'none' }
    $runDir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N'))
    $log = Join-Path $runDir 'Office.log'
    $errorLog = Join-Path $runDir 'Office-errors.log'
    $progress = Join-Path $runDir 'Progress.txt'
    $a = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$(Join-Path $DirOffice 'Office-ODT.ps1')`" -Mode $mode -Product $($sel.Id) -Languages $($sel.Langs -join ',') -Arch $($sel.Arch) -Exclude $excl -KhoRoot `"$KhoOffice`" -ProgressPath `"$progress`""
    if ($key -and $mode -ne 'Download') { $a += " -PidKey $key" }
    if ($chkMsi.IsChecked -and $mode -ne 'Download') { $a += ' -RemoveMSI' }

    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $process = Start-Process powershell.exe -ArgumentList $a -WorkingDirectory $DirOffice -WindowStyle Hidden `
            -RedirectStandardOutput $log -RedirectStandardError $errorLog -PassThru -ErrorAction Stop
    } catch {
        $officeBar.IsIndeterminate = $false
        $officeBar.Value = 0
        $lblOfficeProgress.Text = "Không mở được Office Deployment Tool. $($_.Exception.Message)"
        $lblOfficeProgress.Foreground = $cDanger
        Set-Status 'Không khởi chạy được Office Deployment Tool.'
        return
    }
    # Giữ handle để Windows PowerShell đọc được mã thoát của tiến trình.
    try { $null = $process.Handle } catch [InvalidOperationException] {}
    $script:officeRun = @{
        Process = $process; Mode = $mode; Log = $log; ErrorLog = $errorLog
        Progress = $progress; Started = Get-Date; Stage = 'Đang chuẩn bị Office Deployment Tool…'
    }
    $bDl.IsEnabled = $false
    $bKho.IsEnabled = $false
    $bNet.IsEnabled = $false
    $bCleanup.IsEnabled = $false
    $bOfficeLog.IsEnabled = $false
    $lblOfficeProgress.Text = $script:officeRun.Stage
    $lblOfficeProgress.Foreground = $cPrimary
    $officeBar.Value = 0
    $officeBar.IsIndeterminate = $true

    Set-Status $lblOfficeProgress.Text
    $officeTimer.Start()
}

function Start-OfficeCleanup {
    if ($script:officeRun) { return }
    $runDir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\Cleanup_' + [guid]::NewGuid().ToString('N'))
    $log = Join-Path $runDir 'Cleanup.log'
    $progress = Join-Path $runDir 'Progress.txt'
    $cleanupArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -LogPath "{1}" -ProgressPath "{2}"' -f (Join-Path $DirOffice 'Office-Cleanup.ps1'), $log, $progress
    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $process = Start-Process powershell.exe -ArgumentList $cleanupArgs -WorkingDirectory $DirOffice -PassThru -ErrorAction Stop
    } catch {
        [Windows.MessageBox]::Show($_.Exception.Message, 'Gỡ / dọn Office', 'OK', 'Error') | Out-Null
        return
    }
    try { $null = $process.Handle } catch [InvalidOperationException] {}
    $script:officeRun = @{
        Process = $process; Mode = 'Cleanup'; Log = $log; ErrorLog = (Join-Path $runDir 'unused.log')
        Progress = $progress; Started = Get-Date; Stage = 'Chọn thao tác và xác nhận trong cửa sổ gỡ / dọn Office.'
    }
    $bDl.IsEnabled = $false; $bKho.IsEnabled = $false; $bNet.IsEnabled = $false; $bCleanup.IsEnabled = $false
    $bOfficeLog.IsEnabled = $false
    $lblOfficeProgress.Text = $script:officeRun.Stage
    $lblOfficeProgress.Foreground = $cPrimary
    $officeBar.Value = 0; $officeBar.IsIndeterminate = $true
    Set-Status $lblOfficeProgress.Text
    $officeTimer.Start()
}

function Assert-MicrosoftSignature([string]$path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Không xác minh được chữ ký Microsoft của $([IO.Path]::GetFileName($path)) ($($signature.Status))."
    }
}

function Start-MediaCreationTool([ValidateSet('10', '11')][string]$version) {
    if ($script:mediaDownload) { return }

    $link = if ($version -eq '11') { 'https://go.microsoft.com/fwlink/?linkid=2156295' }
            else { 'https://go.microsoft.com/fwlink/?LinkId=2265055' }
    $name = 'TechMaster-MediaCreationTool-{0}-{1}.exe' -f $version, [guid]::NewGuid().ToString('N')
    $file = Join-Path ([IO.Path]::GetTempPath()) $name
    $client = New-Object System.Net.WebClient
    try {
        $task = $client.DownloadFileTaskAsync([uri]$link, $file)
        $script:mediaDownload = @{ Client = $client; Task = $task; File = $file; Version = $version }
        $btnUsb11.IsEnabled = $false
        $btnUsb10.IsEnabled = $false
        Set-Status "Đang tải Media Creation Tool cho Windows $version…"
        $mediaTimer.Start()
    } catch {
        $client.Dispose()
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
        Set-Status "Không tải được Media Creation Tool. $($_.Exception.Message)"
    }
}

function Complete-MediaCreationTool($download) {
    $download.Task.GetAwaiter().GetResult()
    Assert-MicrosoftSignature $download.File
    Start-Process -FilePath $download.File -WorkingDirectory ([IO.Path]::GetDirectoryName($download.File)) -ErrorAction Stop
}

function Open-WindowsOldCleanup {
    $oldInstall = Join-Path ($env:SystemDrive + '\') 'Windows.old'
    if (-not (Test-Path -LiteralPath $oldInstall -PathType Container)) {
        Set-Status 'Không tìm thấy Windows.old trên ổ cài Windows.'
        return
    }
    try {
        Start-Process 'ms-settings:storagesense' -ErrorAction Stop
        Set-Status 'Chọn Tệp tạm thời → Bản cài đặt Windows trước đây → Xóa tệp.'
    } catch {
        Set-Status 'Mở Cài đặt → Hệ thống → Lưu trữ → Tệp tạm thời để dọn Windows.old.'
    }
}

function Start-WindowsSetup([string]$isoPath) {
    $mountedHere = $false
    try {
        $disk = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop
        if (-not $disk.Attached) {
            $disk = Mount-DiskImage -ImagePath $isoPath -StorageType ISO -PassThru -ErrorAction Stop
            $mountedHere = $true
        }
        $volume = Get-Volume -DiskImage $disk -ErrorAction Stop |
            Where-Object DriveLetter | Select-Object -First 1
        if (-not $volume) { throw 'Windows chưa gán ký tự ổ cho ISO. Hãy gắn ISO trong File Explorer rồi thử lại.' }
        $drive = '{0}:\' -f $volume.DriveLetter
        $setup = Join-Path $drive 'setup.exe'
        if (-not (Test-Path -LiteralPath $setup -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $drive 'sources\boot.wim') -PathType Leaf)) {
            throw 'ISO không có bộ cài Windows hoàn chỉnh.'
        }

        Assert-MicrosoftSignature $setup
        Start-Process -FilePath $setup -WorkingDirectory $drive -ErrorAction Stop
    } catch {
        if ($mountedHere) {
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
}
