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
        Show-DeployMessage "Không tìm thấy:`n$file" 'TechMaster Deploy' 'Error'
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
        $lblOfficeProgress.Text = if ($run.Mode -eq 'Download') { 'Đã tải bộ cài về kho.' } elseif ($run.Mode -eq 'Cleanup') { if($run.CleanupMode -eq 'Keys'){'Đã đóng cửa sổ key Office. Xem nhật ký nếu đã thực hiện xoá key.'}else{'Đã kết thúc công cụ gỡ / dọn. Xem nhật ký để biết kết quả.'} } else { 'Đã cài Office.' }
        $lblOfficeProgress.Foreground = $cPrimary
    } else {
        $lblOfficeProgress.Text = if ($null -eq $exitCode) {
            'Không xác nhận được kết quả. Mở nhật ký để xem chi tiết.'
        } else {
            "Office báo lỗi (mã $exitCode). Mở nhật ký để xem chi tiết."
        }
        $lblOfficeProgress.Foreground = $cDanger
    }
    Set-DeployNoticeKind $lblOfficeProgress $(if($null -ne $exitCode -and $exitCode -eq 0){'Success'}else{'Error'})
    Set-Status $lblOfficeProgress.Text
    $bDl.IsEnabled = $true
    $bKho.IsEnabled = $true
    $bNet.IsEnabled = $true
    $bCleanup.IsEnabled = $true
    if($bRemoveOffice){$bRemoveOffice.IsEnabled=$true}
    Update-OffInfo
}

function Start-ODT([string]$mode) {
    if ($script:officeRun) { return }
    $sel = Get-OffSel
    if ($sel.Langs.Count -eq 0) { Show-DeployMessage 'Chọn ít nhất 1 ngôn ngữ.' 'Office'; return }
    $key = $tbOffKey.Text.Trim().ToUpper()
    if ($key -and $key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') {
        Show-DeployMessage 'Key sai định dạng XXXXX-XXXXX-XXXXX-XXXXX-XXXXX' 'Office' 'Warning'; return
    }
    if ($mode -eq 'InstallKho' -and -not (Test-Path (Join-Path $sel.Kho 'Office'))) {
        Show-DeployMessage "Chưa có kho cho lựa chọn này:`n$($sel.Kho)`n`nBấm 'Tải về kho' trước." 'Office' 'Warning'; return
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
        Set-DeployNoticeKind $lblOfficeProgress 'Error'
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
    if($bRemoveOffice){$bRemoveOffice.IsEnabled=$false}
    $bOfficeLog.IsEnabled = $false
    Set-DeployNoticeKind $lblOfficeProgress 'Working'
    $lblOfficeProgress.Text = $script:officeRun.Stage
    $lblOfficeProgress.Foreground = $cPrimary
    $officeBar.Value = 0
    $officeBar.IsIndeterminate = $true

    Set-Status $lblOfficeProgress.Text
    $officeTimer.Start()
}

function Start-OfficeCleanup([ValidateSet('Menu','Keys')][string]$CleanupMode='Menu') {
    if ($script:officeRun) { return }
    $runDir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\Cleanup_' + [guid]::NewGuid().ToString('N'))
    $log = Join-Path $runDir 'Cleanup.log'
    $progress = Join-Path $runDir 'Progress.txt'
    $cleanupArgs = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -LogPath "{1}" -ProgressPath "{2}" -Mode {3}' -f (Join-Path $DirOffice 'Office-Cleanup.ps1'), $log, $progress, $CleanupMode
    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
        $process = Start-Process powershell.exe -ArgumentList $cleanupArgs -WorkingDirectory $DirOffice -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch {
        Show-DeployMessage $_.Exception.Message 'Gỡ / dọn Office' 'Error'
        return
    }
    try { $null = $process.Handle } catch [InvalidOperationException] {}
    $script:officeRun = @{
        Process = $process; Mode = 'Cleanup'; CleanupMode=$CleanupMode; Log = $log; ErrorLog = (Join-Path $runDir 'unused.log')
        Progress = $progress; Started = Get-Date; Stage = $(if($CleanupMode -eq 'Keys'){'Chọn key dùng tạm và xác nhận trong cửa sổ key Office.'}else{'Chọn thao tác và xác nhận trong cửa sổ gỡ / dọn Office.'})
    }
    $bDl.IsEnabled = $false; $bKho.IsEnabled = $false; $bNet.IsEnabled = $false; $bCleanup.IsEnabled = $false
    if($bRemoveOffice){$bRemoveOffice.IsEnabled=$false}
    $bOfficeLog.IsEnabled = $false
    Set-DeployNoticeKind $lblOfficeProgress 'Working'
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
    if($script:uiWork){Set-Status 'Chờ thao tác hiện tại hoàn tất.';return}
    if(-not (Test-Path -LiteralPath (Join-Path ($env:SystemDrive+'\') 'Windows.old') -PathType Container)){Set-Status 'Không tìm thấy Windows.old trên ổ cài Windows.';return}
    if(-not (Confirm-Box 'Mở Disk Cleanup để dọn Windows.old? Kiểm tra dữ liệu cần giữ trong Windows.old trước. Xoá bản cài trước sẽ mất lựa chọn quay lại. Trong công cụ chỉ chọn Previous Windows installation(s), kiểm tra các mục khác như Downloads trước khi xác nhận.' 'Dọn Windows.old' -ConfirmText 'Mở Disk Cleanup' -Danger -Owner $form)){return}
    Start-UiWork @'
param($core)
. $core
$log=Get-DeployWindowsToolsLog 'WindowsOld'
try{Invoke-DeployWindowsOldCleanup $log}catch{Write-DeployWindowsToolsLog $log 'failed' $_.Exception.Message;throw}
'@ @((Join-Path $PSScriptRoot 'Windows.Tools.ps1')) {
        param($result)
        $r=$result[-1];Set-Status ($r.Message+' Nhật ký: '+$r.Log) $(if($r.Remaining){'Attention'}elseif($r.Missing){'Info'}else{'Success'})
    }
    Set-Status 'Trong Disk Cleanup: chọn Dọn tệp hệ thống → Bản cài đặt Windows trước đây. Đóng công cụ để app kiểm tra lại.' 'Working'
}
function Set-ExplorerMenuChoice([ValidateSet('Legacy','Default')][string]$Mode) {
    if($script:uiWork){Set-Status 'Chờ thao tác hiện tại hoàn tất.';return}
    $label=if($Mode -eq 'Legacy'){'menu truyền thống kiểu Windows 10'}else{'menu mặc định Windows 11'}
    if(-not (Confirm-Box ('Lưu lựa chọn '+$label+' cho tài khoản Windows đang chạy app? Nếu mở app bằng tài khoản quản trị khác, cấu hình sẽ thuộc tài khoản đó. App sẽ hỏi riêng trước khi khởi động lại Explorer.') 'Menu chuột phải' -ConfirmText 'Lưu lựa chọn' -Owner $form)){return}
    Start-UiWork @'
param($core,$mode)
. $core
$log=Get-DeployWindowsToolsLog 'ExplorerMenu'
try{Set-DeployExplorerMenu $mode $log}catch{Write-DeployWindowsToolsLog $log 'failed' $_.Exception.Message;throw}
'@ @((Join-Path $PSScriptRoot 'Windows.Tools.ps1'),$Mode) {
        param($result)
        $r=$result[-1];Set-Status ($r.Message+' Nhật ký: '+$r.Log) 'Attention'
        if($r.Changed -and (Confirm-Box 'Khởi động lại Explorer để áp dụng ngay? Các cửa sổ thư mục của tài khoản này có thể đóng. Tác vụ chép tệp đang chạy cần hoàn tất trước.' 'Áp dụng menu chuột phải' -ConfirmText 'Khởi động lại Explorer' -CancelText 'Để sau' -Owner $form)){
            try{. (Join-Path $PSScriptRoot 'Windows.Tools.ps1');Restart-DeployCurrentExplorer $r.Log;Set-Status 'Đã yêu cầu khởi động lại Explorer. Thử lại menu chuột phải; nếu chưa đổi, đăng xuất / đăng nhập lại.' 'Info'}catch{Set-Status ('Đã lưu cấu hình nhưng chưa khởi động lại được Explorer: '+$_.Exception.Message) 'Attention'}
        }
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
