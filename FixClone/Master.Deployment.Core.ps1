# Deployment orchestration. Only the final stage changes Office keys/UltraViewer.
function Get-MasterOfficeDirectory {
    $project=Join-Path (Split-Path -Parent $PSScriptRoot) 'Office'
    if(Test-Path -LiteralPath (Join-Path $project 'Office-Cleanup.Core.ps1')){return $project}
    return $PSScriptRoot
}
function Invoke-MasterTemporaryOfficeCleanup([string]$logRoot) {
    $directory=Get-MasterOfficeDirectory
    . (Join-Path $directory 'Office-Cleanup.Core.ps1')
    . (Join-Path $directory 'Office-Cleanup.Engine.ps1')
    $null=Invoke-OfficeCleanupTask -Operation Temporary -LogPath (Join-Path $logRoot ('TrialOffice-'+[guid]::NewGuid().ToString('N')+'.log'))
}
function Get-MasterWindowsCleanupChoice($options) {
    if(-not $options.PSObject.Properties['CleanWindowsSetupKey']){return $false}
    if($options.CleanWindowsSetupKey -isnot [bool]){throw 'Lựa chọn dọn key chung Windows không hợp lệ.'}
    return [bool]$options.CleanWindowsSetupKey
}
function Invoke-MasterWindowsSetupCleanup([string]$receiptPath) {
    . (Join-Path $PSScriptRoot 'Windows.License.Core.ps1')
    $null=Invoke-WindowsSetupKeyCleanup -ReceiptPath $receiptPath
}
function Restore-MasterWindowsSetupCleanup([string]$receiptPath) {
    . (Join-Path $PSScriptRoot 'Windows.License.Core.ps1')
    $null=Restore-WindowsSetupKeyCleanup $receiptPath
}
function Invoke-MasterPreparation { & (Join-Path $PSScriptRoot 'Prepare-Master.ps1') }
function Invoke-MasterPreCheck {
    & (Join-Path $PSScriptRoot 'Fix-SysprepErrors.ps1') -PreCheck
    if($LASTEXITCODE -ne 0){throw 'Còn lỗi Sysprep. Sửa lỗi trước khi tạo ảnh.'}
}
function Invoke-MasterSysprep([string]$systemDirectory,[string]$unattendPath) {
    $process=Start-Process -FilePath (Join-Path $systemDirectory 'Sysprep/sysprep.exe') -ArgumentList ('/generalize /oobe /shutdown /unattend:"{0}"' -f $unattendPath) -PassThru -Wait -ErrorAction Stop
    try {if($null -eq $process.ExitCode -or $process.ExitCode -ne 0){throw ('Sysprep thất bại (mã '+$process.ExitCode+').')}}finally{$process.Dispose()}
}
function Invoke-MasterDeployment($options,[string]$work,[string]$systemDirectory,[string]$unattendPath) {
    if($options.Schema -ne 1 -or $options.CleanOfficeTrial -isnot [bool] -or $options.PrepareUltra -isnot [bool]){throw 'Lựa chọn chuẩn bị Sysprep không hợp lệ.'}
    $cleanWindows=Get-MasterWindowsCleanupChoice $options
    $windowsReceipt=''
    $marker=Join-Path $work 'UltraViewer-Clone.json'
    $receipt='';$completed=$false
    try {
        # Save Word Normal.dotm / ribbon / options before touching trial licenses.
        Invoke-MasterPreparation
        Invoke-MasterPreCheck
        if(-not (Confirm-Box 'Thiết lập máy gốc đã lưu. Bước tiếp theo sẽ dọn key Office dùng thử / key chung Windows chưa kích hoạt theo lựa chọn, chuẩn bị ID UltraViewer theo lựa chọn và chạy Sysprep. Máy sẽ tự tắt. Không mở lại máy gốc trước khi clone.' 'Sẵn sàng tạo ảnh' -ConfirmText 'Chuẩn bị và tắt máy' -Danger)){return $false}
        $config=[pscustomobject]@{Schema=1;CleanOfficeTrial=[bool]$options.CleanOfficeTrial;PrepareUltra=[bool]$options.PrepareUltra;CleanWindowsSetupKey=$cleanWindows}
        Write-UltraJson $config (Join-Path $work 'CloneOptions.json')
        if($options.CleanOfficeTrial){Invoke-MasterTemporaryOfficeCleanup (Join-Path $work 'Logs')}
        if($cleanWindows){
            $windowsReceipt=Join-Path $work ('Logs/WindowsSetup-'+[guid]::NewGuid().ToString('N')+'.json')
            Invoke-MasterWindowsSetupCleanup $windowsReceipt
        }
        if($options.PrepareUltra){
            $backup=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TechMaster Deploy/UltraViewer Backups'
            $receipt=Prepare-UltraForClone $marker $backup
        }
        Invoke-MasterSysprep $systemDirectory $unattendPath
        $completed=$true
        return $true
    } finally {
        if(-not $completed){
            try{if($windowsReceipt -and (Test-Path -LiteralPath $windowsReceipt)){Restore-MasterWindowsSetupCleanup $windowsReceipt}}
            finally{if($receipt){Restore-UltraReceipt $receipt;Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue}}
        }
    }
}
function Invoke-ClonePreparedCleanup([string]$work) {
    $path=Join-Path $work 'CloneOptions.json'
    if(-not (Test-Path -LiteralPath $path)){return}
    $config=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($config.Schema -ne 1 -or $config.CleanOfficeTrial -isnot [bool] -or $config.PrepareUltra -isnot [bool]){throw 'Cấu hình chuẩn bị clone không hợp lệ.'}
    $cleanWindows=Get-MasterWindowsCleanupChoice $config
    if($cleanWindows){Invoke-MasterWindowsSetupCleanup (Join-Path $work ('Logs/WindowsSetup-'+[guid]::NewGuid().ToString('N')+'.json'))}
    if($config.CleanOfficeTrial){Invoke-MasterTemporaryOfficeCleanup (Join-Path $work 'Logs')}
    if($config.PrepareUltra){
        $backup=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TechMaster Deploy/UltraViewer Backups'
        $result=Complete-UltraAfterClone (Join-Path $work 'UltraViewer-Clone.json') $backup
        Write-Host $result.Message
    }
}
