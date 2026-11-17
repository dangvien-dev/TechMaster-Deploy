<#
.SYNOPSIS
    Kiểm tra, gỡ Office 2021/2024 Click-to-Run và dọn key Office.
    Không tự nhận diện hay xoá công cụ crack, tác vụ, dịch vụ hoặc token bản quyền.
#>
param(
    [ValidateSet('Menu', 'Inspect', 'Keys', 'Remove')][string]$Mode = 'Menu',
    [string]$LogPath = '',
    [string]$ProgressPath = ''
)
$ErrorActionPreference = 'Stop'
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit -PathType Leaf) {
    . $consoleInit
    Initialize-TechMasterConsole
}
. (Join-Path $PSScriptRoot 'Office-Cleanup.Core.ps1')
$exitCode = 0
$transcriptStarted = $false
$officeMutex = $null
$ownsMutex = $false
try {
    if (-not $LogPath) {
        $dir = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Office Logs\Cleanup_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $LogPath = Join-Path $dir 'Cleanup.log'
    }
    Start-Transcript -LiteralPath $LogPath -ErrorAction Stop | Out-Null
    $transcriptStarted = $true
    Write-Host 'GỠ / DỌN OFFICE' -ForegroundColor Cyan
    Write-Host '1. Kiểm tra Office và các key hiện có (chỉ đọc)'
    Write-Host '2. Chọn từng key Office cần xoá (giữ key không chọn, gồm cả Retail)'
    Write-Host '3. Gỡ bộ Office 2021/2024 Click-to-Run (có bước chọn key và kiểm tra key giữ lại)'
    Write-Host '0. Thoát'
    if ($Mode -eq 'Menu') {
        switch (Read-Host 'Chọn 0 / 1 / 2 / 3') {
            '1' { $Mode = 'Inspect' }
            '2' { $Mode = 'Keys' }
            '3' { $Mode = 'Remove' }
            default { Write-Host 'Đã huỷ.'; return }
        }
    }
    $inventory = Get-OfficeCleanupInventory
    Write-Host ("`nClick-to-Run: " + ($inventory.Products -join ', '))
    Write-Host 'Key Office đang cài (chỉ 5 ký tự cuối):'
    $inventory.Keys | Select-Object Name, PartialProductKey, LicenseStatus | Format-Table -AutoSize | Out-Host
    Write-Host 'KMS có thể là bản quyền hợp lệ của tổ chức; không thể kết luận active lậu chỉ từ trạng thái này.'
    Write-Host 'Công cụ không xoá tài liệu, key Windows, kho token, tài khoản M365 hay công cụ kích hoạt bên ngoài.'
    if ($Mode -eq 'Inspect') { return }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
    if (-not $admin) { throw 'Hãy mở TechMaster Deploy bằng quyền Administrator.' }
    $plan = Get-OfficeCleanupPlan $inventory $Mode
    if ($Mode -eq 'Remove' -and -not $plan.Products.Count) {
        throw 'Không nhận diện được bộ Office 2021/2024 Click-to-Run hỗ trợ. Không gỡ sản phẩm khác; dùng Settings > Apps nếu cần.'
    }
    if (-not $plan.Products.Count -and -not $plan.Keys.Count) { Write-Host 'Không có key Office để xoá.'; return }
    if ($plan.Keys.Count) {
        Write-Host "`nCHỌN KEY CẦN XOÁ — mặc định không chọn key nào."
        $rows = @(for ($i = 0; $i -lt $plan.Keys.Count; $i++) {
            $license = $plan.Keys[$i]
            [pscustomobject]@{ STT = $i + 1; Loai = (Get-OfficeLicenseKind $license); DuoiKey = $license.PartialProductKey; License = $license.Name }
        })
        $rows | Format-Table -AutoSize -Wrap | Out-Host
        Write-Host 'Chỉ nhập số của key muốn XOÁ, ví dụ 1,3. Key không chọn sẽ được giữ lại.'
        Write-Host 'Muốn giữ Retail: không nhập số của dòng Retail. Enter để không chọn key nào.'
        $choice = Read-Host 'Số thứ tự key cần xoá'
        $plan = Select-OfficeCleanupKeys $plan $choice
    }
    if (-not $plan.Products.Count -and -not $plan.Keys.Count) { Write-Host 'Không chọn key; không thay đổi máy.'; return }
    Write-Host ("`nSẢN PHẨM SẼ GỠ: " + ($plan.Products -join ', ')) -ForegroundColor Yellow
    Write-Host 'KEY ĐÃ CHỌN XOÁ (bao gồm key hợp lệ nếu bạn chọn):' -ForegroundColor Yellow
    $plan.Keys | Select-Object Name, PartialProductKey | Format-Table -AutoSize | Out-Host
    Write-Host 'KEY GIỮ LẠI:' -ForegroundColor Green
    $plan.PreservedKeys | Select-Object Name, PartialProductKey | Format-Table -AutoSize | Out-Host
    Write-Host 'Lưu tài liệu và đóng toàn bộ Office. Sau khi xoá, cần key / tài khoản hợp lệ để kích hoạt lại.'
    Write-Host 'Giữ lại thông tin mua bản quyền trước khi tiếp tục. Nhật ký không sao lưu key đầy đủ.'
    if ((Read-Host 'Gõ XOA OFFICE để xác nhận') -cne 'XOA OFFICE') { Write-Host 'Đã huỷ; không thay đổi máy.'; return }
    $officeMutex = New-Object System.Threading.Mutex($false, 'Global\TechMaster.OfficeDeployment')
    try { $ownsMutex = $officeMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'TechMaster đang cài hoặc dọn Office ở cửa sổ khác. Chờ hoàn tất rồi thử lại.' }
    # Refuse to apply an outdated plan after an install/license change during confirmation.
    $current = Get-OfficeCleanupInventory
    if (($inventory.Products -join ',') -ne ($current.Products -join ',') -or
        (($inventory.Keys | ForEach-Object { "$($_.ID):$($_.PartialProductKey)" } | Sort-Object) -join ',') -ne
        (($current.Keys | ForEach-Object { "$($_.ID):$($_.PartialProductKey)" } | Sort-Object) -join ',')) {
        throw 'Office đã thay đổi trong lúc xác nhận. Chạy lại để xem danh sách mới.'
    }
    Assert-OfficeCleanupAppsClosed
    $setup = ''
    if ($Mode -eq 'Remove') { $setup = Get-OfficeCleanupSetup (Join-Path $PSScriptRoot 'ODT') }
    if ($ProgressPath) { [IO.File]::WriteAllText($ProgressPath, 'Đang gỡ / dọn Office…') }
    Invoke-OfficeCleanupPlan $plan $setup (Split-Path -Parent $LogPath)
} catch {
    $exitCode = 1
    Write-Host ("LỖI: " + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($ownsMutex) { $officeMutex.ReleaseMutex() }
    if ($null -ne $officeMutex) { $officeMutex.Dispose() }
    Write-Host "Nhật ký: $LogPath"
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    if ($Mode -eq 'Menu' -or [Environment]::UserInteractive) { Read-Host 'Nhấn Enter để đóng' | Out-Null }
}
exit $exitCode
