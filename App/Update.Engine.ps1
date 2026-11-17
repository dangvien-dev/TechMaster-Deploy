# Noninteractive update operations shared by the WPF window and tests.
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

function Set-DeployTaskProgress([string]$work, [string]$message, [int]$percent = -1) {
    try { Write-DeployJson ([pscustomobject]@{ message = $message; percent = $percent }) (Join-Path $work 'progress.json') } catch {}
}

function Invoke-DeployUpdateTask {
    param(
        [ValidateSet('Check','PrepareOnline','PrepareLocal','Apply','History','RollbackInfo','Rollback')][string]$Operation,
        [string]$Root, [string]$Work, $Release, [string]$PackagePath = '',
        [int]$ParentId = 0, [string]$CloseRequestPath = '', [string]$Backup = ''
    )
    $ErrorActionPreference = 'Stop'
    $Root = [IO.Path]::GetFullPath($Root)
    Assert-DeployRegularPath $Root
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'App/TechMaster-Deploy.ps1') -PathType Leaf)) { throw 'Thư mục được chọn không có TechMaster Deploy.' }
    New-Item -ItemType Directory -Path $Work -Force | Out-Null
    $payload = Join-Path $Work 'payload'
    switch ($Operation) {
        'Check' {
            Set-DeployTaskProgress $Work 'Đang kiểm tra phiên bản mới…'
            $known = ''
            if (Test-Path -LiteralPath (Join-Path $Root 'update-package.json')) { $known = [string](Read-DeployManifest (Join-Path $Root 'update-package.json')).source.commit }
            $release = Get-DeployOnlineRelease $known
            if ($release.unchanged) { return [pscustomobject]@{ state = 'Latest'; message = 'Bạn đang dùng phiên bản mới nhất.' } }
            if ([version]$release.version -lt (Get-DeployVersion $Root)) { throw 'Bản đang dùng mới hơn bản trên máy chủ. Không hạ cấp tự động.' }
            return [pscustomobject]@{ state = 'Available'; message = ('Đã có phiên bản ' + $release.version); release = $release }
        }
        'PrepareOnline' {
            Set-DeployTaskProgress $Work 'Đang tải và kiểm tra bản cập nhật…' 0
            $null = Save-DeployRepositoryPayload $Release $payload $Root -Progress {
                param($done, $total, $path)
                $message=if($path){"Đang kiểm tra tệp $done / $total — $path"}else{"Đã kiểm tra $done / $total tệp…"}
                Set-DeployTaskProgress $Work $message ([int](90 * $done / [Math]::Max(1, $total)))
            }
            $plan = Get-DeployUpdatePlan $Root $payload
            Set-DeployTaskProgress $Work 'Bản cập nhật đã sẵn sàng.' 100
            return [pscustomobject]@{ state = 'Ready'; message = ('Sẵn sàng cập nhật ' + $plan.from + ' → ' + $plan.to); version = $plan.to }
        }
        'PrepareLocal' {
            Set-DeployTaskProgress $Work 'Đang kiểm tra gói cập nhật…'
            $null = Expand-DeployPackage $PackagePath $payload
            $plan = Get-DeployUpdatePlan $Root $payload
            return [pscustomobject]@{ state = 'Ready'; message = ('Sẵn sàng cập nhật ' + $plan.from + ' → ' + $plan.to); version = $plan.to }
        }
        'History' {
            $rows = @(Get-DeployHistory $Root | ForEach-Object {
                [pscustomobject]@{ Date = $_.Date; From = $_.From; To = $_.To; Status = $(if ($_.Status -eq 'installed') { 'Đã cập nhật' } elseif ($_.Status -eq 'rolled-back') { 'Đã khôi phục' } else { [string]$_.Status }) }
            })
            return [pscustomobject]@{ state = 'History'; message = $(if ($rows.Count) { 'Các lần cập nhật trên máy này.' } else { 'Chưa có lịch sử cập nhật.' }); rows = $rows }
        }
        'RollbackInfo' {
            $current = (Get-DeployVersion $Root).ToString()
            $last = @(Get-DeployHistory $Root | Where-Object { $_.Status -eq 'installed' -and [version]$_.To -eq [version]$current })
            if (-not $last.Count) { return [pscustomobject]@{ state = 'Latest'; message = 'Chưa có bản sao lưu phù hợp để khôi phục.' } }
            return [pscustomobject]@{ state = 'RollbackReady'; message = ('Khôi phục từ ' + $current + ' về ' + $last[0].From); backup = $last[0].Backup }
        }
    }
    # Apply/Rollback are reachable only after the window's explicit confirmation.
    $officeLock = New-Object Threading.Mutex($false, 'Global\TechMaster.OfficeDeployment')
    $owns = $false; $script:parentClosed = $false
    try {
        try { $owns = $officeLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owns = $true }
        if (-not $owns) { throw 'Đang cài / dọn Office. Chờ thao tác đó kết thúc rồi cập nhật.' }
        if ($Operation -eq 'Apply') { $null = Get-DeployUpdatePlan $Root $payload }
        Set-DeployTaskProgress $Work 'Đang đóng app và sao lưu phiên bản hiện tại…'
        Close-DeployForUpdate
        Assert-DeployToolsClosed $Root $ParentId
        $script:parentClosed = $true
        if ($Operation -eq 'Rollback') {
            Undo-DeployUpdate $Root $Backup
            $message = 'Đã khôi phục phiên bản trước.'
        } else {
            $null = Install-DeployUpdate $Root $payload
            $message = 'Đã cập nhật lên ' + (Get-DeployVersion $Root) + '.'
        }
    } finally {
        if ($owns) { $officeLock.ReleaseMutex() }
        $officeLock.Dispose()
    }
    Set-DeployTaskProgress $Work $message 100
    return [pscustomobject]@{ state = 'Complete'; message = $message }
}

# Called only after the updater window closes with explicit user intent.
function Open-DeployUpdatedApplication($session) {
    if($session.State -ne 'Complete' -or -not $session.OpenApplication){return}
    $session.OpenApplication=$false
    Assert-DeployRegularPath $session.Root 'TechMaster Deploy.exe'
    $path=Join-Path $session.Root 'TechMaster Deploy.exe'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Không tìm thấy TechMaster Deploy.exe. Mở ứng dụng trong thư mục đã cập nhật để tiếp tục.'}
    Start-Process -FilePath $path -WorkingDirectory $session.Root -ErrorAction Stop|Out-Null
}

function Get-DeployUpdateView([string]$state) {
    switch ($state) {
        'Available'     { return @{ heading = 'Có bản cập nhật mới'; primary = 'Tải bản cập nhật'; action = 'PrepareOnline'; busy = $false } }
        'Ready'         { return @{ heading = 'Sẵn sàng cài đặt'; primary = 'Cài đặt bản cập nhật'; action = 'Apply'; busy = $false } }
        'RollbackReady' { return @{ heading = 'Khôi phục phiên bản'; primary = 'Khôi phục bản trước'; action = 'Rollback'; busy = $false } }
        'Latest'        { return @{ heading = 'Đã kiểm tra'; primary = 'Kiểm tra lại'; action = 'Retry'; busy = $false } }
        'History'       { return @{ heading = 'Lịch sử cập nhật'; primary = 'Làm mới'; action = 'History'; busy = $false } }
        'Complete'      { return @{ heading = 'Hoàn tất'; primary = 'Đóng và mở ứng dụng'; action = 'OpenApplication'; busy = $false } }
        'Error'         { return @{ heading = 'Chưa hoàn tất'; primary = 'Thử lại'; action = 'Retry'; busy = $false } }
        'Checking'     { return @{ heading = 'Đang kiểm tra'; primary = 'Đang kiểm tra…'; action = ''; busy = $true } }
        'Preparing'    { return @{ heading = 'Đang chuẩn bị'; primary = 'Đang tải…'; action = ''; busy = $true } }
        'Applying'     { return @{ heading = 'Đang cài đặt'; primary = 'Đang cài đặt…'; action = ''; busy = $true } }
        default        { return @{ heading = 'Sẵn sàng'; primary = 'Tiếp tục'; action = 'Retry'; busy = $false } }
    }
}
