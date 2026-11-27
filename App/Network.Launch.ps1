# Opened on another computer by \\MÁY\TechMaster$\App\Chay-Tu-Mang.bat: copy TechMaster Deploy from the
# share to C:\TechMaster-Deploy, check every file, then open it with administrator rights.
param([string]$Target='')
$ErrorActionPreference='Stop'
try{
    . (Join-Path $PSScriptRoot 'Network.Sync.ps1')
    $source=Split-Path -Parent $PSScriptRoot
    Write-Host ('TechMaster Deploy — chạy từ máy chia sẻ '+$source)
    $result=Start-DeployNetworkRun $source $Target
    Write-Host ('✓ Đã mở TechMaster Deploy '+$result.Version+' từ '+$result.Target+'. Xoá thư mục này khi không còn dùng.') -ForegroundColor Green
    Start-Sleep -Seconds 3
}catch{
    Write-Host ('✗ '+$_.Exception.GetBaseException().Message) -ForegroundColor Red
    [void](Read-Host 'Nhấn Enter để đóng')
    exit 1
}
