param(
    [Parameter(Mandatory = $true)][string]$Root,
    [ValidateSet('Online', 'Local', 'History', 'Rollback', 'Access')][string]$Mode = 'Online',
    [string]$PackagePath = '',
    [int]$ParentId = 0,
    [string]$CloseRequestPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
if (Test-Path (Join-Path $PSScriptRoot 'Console.ps1')) {
    . (Join-Path $PSScriptRoot 'Console.ps1')
    Initialize-TechMasterConsole
}
$work = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy\Update Downloads\' + [guid]::NewGuid().ToString('N'))
$exitCode = 0
$parentClosed = $false
$officeLock = $null
$ownsOfficeLock = $false
function Close-DeployForUpdate {
    Write-Host 'Đang đóng cửa sổ TechMaster để thay tệp chương trình…'
    if ($ParentId -gt 0) {
        $parent = Get-Process -Id $ParentId -ErrorAction SilentlyContinue
        if ($null -ne $parent) {
            try {
                if ($CloseRequestPath) {
                    $expected = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'close.request'))
                    if ([IO.Path]::GetFullPath($CloseRequestPath) -ne $expected) { throw 'Đường dẫn yêu cầu đóng app không hợp lệ.' }
                    Assert-DeployRegularPath $PSScriptRoot 'close.request'
                    [IO.File]::WriteAllText($CloseRequestPath, 'close', [Text.UTF8Encoding]::new($false))
                } elseif (-not $parent.CloseMainWindow()) {
                    throw 'Chưa đóng được TechMaster. Chưa thay tệp; đóng app và dùng công cụ nâng cấp riêng để nhận bản sửa.'
                }
                if (-not $parent.WaitForExit(15000)) { throw 'TechMaster chưa thoát hẳn. Chưa thay tệp; đóng app và dùng công cụ nâng cấp riêng để thử lại.' }
            } finally {
                if ($CloseRequestPath -and (Test-Path -LiteralPath $CloseRequestPath -PathType Leaf)) {
                    # Remove only this runner's request, including on timeout.
                    if ([IO.Path]::GetFullPath($CloseRequestPath) -eq [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'close.request'))) {
                        Remove-Item -LiteralPath $CloseRequestPath -Force -ErrorAction SilentlyContinue
                    }
                }
                $parent.Dispose()
            }
        }
    }
    if ($ParentId -gt 0) { $script:parentClosed = $true }
}
try {
    $Root = [IO.Path]::GetFullPath($Root)
    Assert-DeployRegularPath $Root
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'App/TechMaster-Deploy.ps1') -PathType Leaf)) { throw 'Thư mục được chọn không có ứng dụng TechMaster Deploy.' }
    Write-Host ('TECHMASTER DEPLOY — CẬP NHẬT | Hiện tại: ' + (Get-DeployVersion $Root)) -ForegroundColor Cyan
    Write-Host 'Giữ cấu hình biên bản, logo, kho Office, bộ ODT, nhật ký và Reinstall.'
    if ($Mode -eq 'Access') {
        Write-Host ('Repo: ' + $script:DeployRepository + ' / ' + $script:DeployBranch)
        Write-Host 'Repo công khai không cần token. Repo riêng tư: dùng fine-grained token chỉ có Contents: Read cho repo này.'
        Write-Host 'Token chỉ lưu mã hoá bằng Windows DPAPI dưới user đang dùng; không đưa vào thư mục app, ZIP hoặc repo.'
        $choice = Read-Host '[1] Lưu token  [2] Xoá token đã lưu  [0] Bỏ qua'
        if ($choice -eq '1') {
            $token = Read-Host 'Nhập token GitHub (nội dung được ẩn)' -AsSecureString
            try { Save-DeployGitHubToken $token } finally { if ($token) { $token.Dispose() } }
            Write-Host 'Đã lưu quyền đọc repo cho user Windows này.'
        } elseif ($choice -eq '2') {
            $credentialPath = Get-DeployCredentialPath
            if (Test-Path -LiteralPath $credentialPath -PathType Leaf) { Remove-Item -LiteralPath $credentialPath -Force }
            Write-Host 'Đã xoá token cục bộ.'
        }
        return
    }
    if ($Mode -eq 'History') {
        @(Get-DeployHistory $Root) | Select-Object Date, From, To, Status | Format-Table -AutoSize | Out-Host
        return
    }
    if ($Mode -eq 'Rollback') {
        $current = (Get-DeployVersion $Root).ToString()
        $last = @(Get-DeployHistory $Root | Where-Object { $_.Status -eq 'installed' -and [version]$_.To -eq [version]$current })
        if (-not $last.Count) { Write-Host 'Không có bản sao lưu phù hợp để quay lại.'; return }
        Write-Host ("Quay lại $($last[0].From) từ $current. Dữ liệu cá nhân và cấu hình vẫn được giữ.")
        if ((Read-Host 'Gõ QUAY LAI để xác nhận') -cne 'QUAY LAI') { Write-Host 'Đã huỷ.'; return }
    } else {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $release = $null
        $payload = Join-Path $work 'payload'
        if ($Mode -eq 'Online') {
            Write-Host 'Đang kiểm tra phiên bản mới…'
            $knownCommit = ''
            $installedManifest = Join-Path $Root 'update-package.json'
            if (Test-Path -LiteralPath $installedManifest -PathType Leaf) { $knownCommit = [string](Read-DeployManifest $installedManifest).source.commit }
            $release = Get-DeployOnlineRelease $knownCommit
            if ($release.unchanged) { Write-Host 'Bạn đang dùng phiên bản mới nhất.' -ForegroundColor Green; return }
            if ([version]$release.version -lt (Get-DeployVersion $Root)) { throw 'Phiên bản trên repo cũ hơn bản đang dùng; không hạ cấp tự động.' }
            Write-Host ("Đã có phiên bản mới: $($release.version)")
            if ((Read-Host 'Tải bản cập nhật? [y/N]') -notin 'y', 'Y') { Write-Host 'Đã huỷ.'; return }
            $package = Save-DeployRepositoryPayload $release $payload $Root
        } else {
            if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw 'Không tìm thấy ZIP. Hãy chọn gói cập nhật TechMaster Deploy.' }
            $package = Expand-DeployPackage $PackagePath $payload
        }
        $plan = Get-DeployUpdatePlan $Root $payload
        Write-Host ("Phiên bản: $($plan.from) -> $($plan.to)")
        if ($plan.firstUpdate) { Write-Host 'Đây là lần nâng cấp đầu tiên: toàn bộ tệp chương trình sắp thay sẽ được sao lưu.' -ForegroundColor Yellow }
        Write-Host 'Đóng các công cụ TechMaster đang mở riêng. Bản hiện tại sẽ được sao lưu để khôi phục khi cần.'
        if ((Read-Host 'Gõ CAP NHAT để cài và mở lại ứng dụng') -cne 'CAP NHAT') { Write-Host 'Đã huỷ; không thay đổi ứng dụng.'; return }
    }
    $officeLock = New-Object Threading.Mutex($false, 'Global\TechMaster.OfficeDeployment')
    try { $ownsOfficeLock = $officeLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsOfficeLock = $true }
    if (-not $ownsOfficeLock) { throw 'TechMaster đang cài / dọn Office. Chờ thao tác đó kết thúc trước khi cập nhật.' }
    Close-DeployForUpdate
    Assert-DeployToolsClosed $Root $ParentId
    $parentClosed = $true
    if ($Mode -eq 'Rollback') {
        Undo-DeployUpdate $Root $last[0].Backup
        Write-Host 'Đã quay lại bản trước.' -ForegroundColor Green
    } else {
        $backup = Install-DeployUpdate $Root $payload
        Write-Host ("Đã cập nhật lên $($plan.to). Bạn có thể khôi phục bản trước trong ứng dụng.") -ForegroundColor Green
    }
} catch {
    $exitCode = 1
    Write-Host ('LỖI: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($ownsOfficeLock) { $officeLock.ReleaseMutex() }
    if ($null -ne $officeLock) { $officeLock.Dispose() }
    if ($parentClosed -and (Test-Path (Join-Path $Root 'TechMaster Deploy.exe'))) {
        try { Start-Process -FilePath (Join-Path $Root 'TechMaster Deploy.exe') -WorkingDirectory $Root -ErrorAction Stop }
        catch { Write-Host 'Không tự mở lại được. Mở TechMaster Deploy.exe từ thư mục chương trình.' }
    }
    # Failed staging data is left for diagnosis; successful downloads can be discarded.
    if ($exitCode -eq 0 -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Read-Host 'Nhấn Enter để đóng' | Out-Null
}
exit $exitCode
