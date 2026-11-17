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
    $marker=Join-Path $work 'UltraViewer-Clone.json'
    $receipt='';$completed=$false
    try {
        # Save Word Normal.dotm / ribbon / options before touching trial licenses.
        Invoke-MasterPreparation
        Invoke-MasterPreCheck
        if(-not (Confirm-Box 'Thiết lập máy gốc đã lưu. Bước tiếp theo sẽ dọn key dùng thử đã nhận diện, chuẩn bị ID UltraViewer theo lựa chọn và chạy Sysprep. Máy sẽ tự tắt. Không mở lại máy gốc trước khi clone.' 'Sẵn sàng tạo ảnh' -ConfirmText 'Chuẩn bị và tắt máy' -Danger)){return $false}
        $config=[pscustomobject]@{Schema=1;CleanOfficeTrial=[bool]$options.CleanOfficeTrial;PrepareUltra=[bool]$options.PrepareUltra}
        Write-UltraJson $config (Join-Path $work 'CloneOptions.json')
        if($options.CleanOfficeTrial){Invoke-MasterTemporaryOfficeCleanup (Join-Path $work 'Logs')}
        if($options.PrepareUltra){
            $backup=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TechMaster Deploy/UltraViewer Backups'
            $receipt=Prepare-UltraForClone $marker $backup
        }
        Invoke-MasterSysprep $systemDirectory $unattendPath
        $completed=$true
        return $true
    } finally {
        if(-not $completed -and $receipt){
            Restore-UltraReceipt $receipt
            Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        }
    }
}
function Invoke-ClonePreparedCleanup([string]$work) {
    $path=Join-Path $work 'CloneOptions.json'
    if(-not (Test-Path -LiteralPath $path)){return}
    $config=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($config.Schema -ne 1 -or $config.CleanOfficeTrial -isnot [bool] -or $config.PrepareUltra -isnot [bool]){throw 'Cấu hình chuẩn bị clone không hợp lệ.'}
    if($config.CleanOfficeTrial){Invoke-MasterTemporaryOfficeCleanup (Join-Path $work 'Logs')}
    if($config.PrepareUltra){
        $backup=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TechMaster Deploy/UltraViewer Backups'
        $result=Complete-UltraAfterClone (Join-Path $work 'UltraViewer-Clone.json') $backup
        Write-Host $result.Message
    }
}
