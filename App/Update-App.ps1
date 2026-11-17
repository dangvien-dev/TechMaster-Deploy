# Graphical updater. No Read-Host, console prompts or UI-thread network calls.
param(
    [string]$Root = '',
    [ValidateSet('Online','Local','History','Rollback','Access')][string]$Mode = 'Online',
    [string]$PackagePath = '', [int]$ParentId = 0, [string]$CloseRequestPath = '',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
. (Join-Path $PSScriptRoot 'Update.Engine.ps1')
$window = Import-DeployWindow (Join-Path $PSScriptRoot 'UpdaterWindow.xml')
$controls = @{}
foreach ($name in 'CurrentVersion','Heading','Summary','Progress','Primary','Cancel','RootPicker','RootPath','BrowseRoot','HistoryGrid','AccessPanel','AccessToken','SaveAccess','RemoveAccess','ChoosePackage') { $controls[$name] = $window.FindName($name) }
$script:session = @{ Root = $Root; Mode = $Mode; Package = $PackagePath; Work = ''; Job = $null; Release = $null; Backup = ''; State = 'Idle'; Operation = ''; CloseRequested = $false }
function Set-UpdateView([string]$state, [string]$message) {
    $script:session.State = $state
    $view = Get-DeployUpdateView $state
    $controls.Heading.Text = $view.heading; $controls.Summary.Text = $message
    $controls.Primary.Content = $view.primary; $controls.Primary.IsEnabled = -not $view.busy; $controls.ChoosePackage.IsEnabled = -not $view.busy
    $controls.Progress.IsIndeterminate = $view.busy
    $controls.Cancel.IsEnabled = $state -ne 'Applying'
    $controls.Cancel.Content = if ($view.busy) { 'Huỷ' } else { 'Đóng' }
    if ($state -in 'Complete','Ready') { $controls.Progress.IsIndeterminate = $false; $controls.Progress.Value = 100 }
    if ($state -in 'Error','Latest','Available','Idle') { $controls.Progress.IsIndeterminate = $false; $controls.Progress.Value = 0 }
}
function New-UpdateWork {
    $script:session.Work = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Update Downloads/' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:session.Work -Force | Out-Null
}
function Start-UpdateOperation([string]$operation) {
    if ($script:session.Job) { return }
    if (-not $script:session.Root) { $controls.RootPicker.Visibility = 'Visible'; Set-UpdateView 'Idle' 'Chọn thư mục ứng dụng đang dùng.'; return }
    try {
        $script:session.Root = [IO.Path]::GetFullPath($script:session.Root)
        if (-not (Test-Path -LiteralPath (Join-Path $script:session.Root 'App/TechMaster-Deploy.ps1') -PathType Leaf)) { throw 'Chọn thư mục có App và TechMaster Deploy.exe.' }
        $controls.CurrentVersion.Text = 'Phiên bản đang dùng: ' + (Get-DeployVersion $script:session.Root)
        $controls.RootPicker.Visibility = 'Collapsed'
        if ($operation -in 'Check','PrepareLocal','History','RollbackInfo') { New-UpdateWork }
        $state = if ($operation -in 'Apply','Rollback') { 'Applying' } elseif ($operation -in 'PrepareOnline','PrepareLocal') { 'Preparing' } else { 'Checking' }
        Set-UpdateView $state 'Đang xử lý…'
        $script:session.Operation = $operation
        $script:session.Job = Start-DeployWork @'
param($directory, $operation, $root, $work, $release, $package, $parentId, $closeRequest, $backup)
$ErrorActionPreference = 'Stop'
. (Join-Path $directory 'Update.Core.ps1')
. (Join-Path $directory 'Update.Engine.ps1')
Invoke-DeployUpdateTask -Operation $operation -Root $root -Work $work -Release $release -PackagePath $package -ParentId $parentId -CloseRequestPath $closeRequest -Backup $backup
'@ @($PSScriptRoot, $operation, $script:session.Root, $script:session.Work, $script:session.Release, $script:session.Package, $ParentId, $CloseRequestPath, $script:session.Backup)
        $timer.Start()
    } catch { Set-UpdateView 'Error' $_.Exception.GetBaseException().Message }
}
function Start-InitialUpdate {
    if ($script:session.Mode -eq 'Access') { $controls.AccessPanel.Visibility = 'Visible'; Set-UpdateView 'Idle' 'Quản lý quyền đọc cập nhật.'; $controls.Primary.Visibility = 'Collapsed'; return }
    if (-not $script:session.Root) { $controls.RootPicker.Visibility = 'Visible'; return }
    switch ($script:session.Mode) {
        'Local' {
            if (-not $script:session.Package) { $script:session.Package = Select-DeployFile 'Chọn gói cập nhật' 'TechMaster Deploy ZIP (*.zip)|*.zip' }
            if ($script:session.Package) { Start-UpdateOperation 'PrepareLocal' }
        }
        'History' { Start-UpdateOperation 'History' }
        'Rollback' { Start-UpdateOperation 'RollbackInfo' }
        default { Start-UpdateOperation 'Check' }
    }
}
$timer = New-DeployTimer 150 {
    $job = $script:session.Job
    if (-not $job) { return }
    try {
        $progressFile = Join-Path $script:session.Work 'progress.json'
        if (Test-Path -LiteralPath $progressFile) {
            $progress = [IO.File]::ReadAllText($progressFile) | ConvertFrom-Json
            $controls.Summary.Text = $progress.message
            if ($progress.percent -ge 0) { $controls.Progress.IsIndeterminate = $false; $controls.Progress.Value = $progress.percent }
        }
    } catch {}
    if (-not $job.Async.IsCompleted) { return }
    $timer.Stop(); $script:session.Job = $null
    try {
        $items = @(Receive-DeployWork $job)
        if ($job.Cancelled) { Set-UpdateView 'Idle' 'Đã huỷ. Ứng dụng hiện tại được giữ nguyên.' }
        else {
            $result = $items[-1]
            if ($result.release) { $script:session.Release = $result.release }
            if ($result.backup) { $script:session.Backup = $result.backup }
            Set-UpdateView $result.state $result.message
            if ($result.state -eq 'History') { $controls.HistoryGrid.ItemsSource = @($result.rows); $controls.HistoryGrid.Visibility = 'Visible' }
        }
    } catch {
        if ($job.Cancelled) { Set-UpdateView 'Idle' 'Đã huỷ. Ứng dụng hiện tại được giữ nguyên.' }
        else { Set-UpdateView 'Error' $_.Exception.GetBaseException().Message }
    }
    if ($script:session.CloseRequested) { $window.Close() }
}
$controls.Primary.Add_Click({
    if ($controls.RootPicker.Visibility -eq 'Visible') { $script:session.Root = $controls.RootPath.Text.Trim(); Start-InitialUpdate; return }
    $view = Get-DeployUpdateView $script:session.State
    switch ($view.action) {
        'Close' { $window.Close() }
        'Apply' { if (Confirm-Box 'Cài bản cập nhật đã kiểm tra? Ứng dụng sẽ đóng, sao lưu và mở lại khi hoàn tất.' 'Cài đặt bản cập nhật') { Start-UpdateOperation 'Apply' } }
        'Rollback' { if (Confirm-Box 'Khôi phục phiên bản trước? Ứng dụng sẽ đóng rồi mở lại. Cấu hình và dữ liệu được giữ nguyên.' 'Khôi phục') { Start-UpdateOperation 'Rollback' } }
        'Retry' { Start-InitialUpdate }
        default { if ($view.action) { Start-UpdateOperation $view.action } }
    }
})
$controls.BrowseRoot.Add_Click({
    $path = Select-DeployFile 'Chọn ứng dụng TechMaster đang dùng' 'TechMaster Deploy (TechMaster Deploy.exe)|TechMaster Deploy.exe'
    if ($path) { $controls.RootPath.Text = Split-Path -Parent $path }
})
$controls.SaveAccess.Add_Click({
    try { Save-DeployGitHubToken $controls.AccessToken.SecurePassword; $controls.AccessToken.Clear(); $controls.Summary.Text = 'Đã lưu quyền đọc mã hoá cho tài khoản Windows này.' }
    catch { Show-DeployMessage $_.Exception.Message 'Quyền đọc' 'Error' }
})
$controls.RemoveAccess.Add_Click({
    try { $path = Get-DeployCredentialPath; if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }; $controls.Summary.Text = 'Đã xoá quyền đọc đã lưu.' }
    catch { Show-DeployMessage $_.Exception.Message 'Quyền đọc' 'Error' }
})
if ($Mode -in 'History','Rollback','Access') { $controls.ChoosePackage.Visibility = 'Collapsed' }
$controls.ChoosePackage.Add_Click({
    if ($script:session.Job) { return }
    $path = Select-DeployFile 'Chọn gói cập nhật offline' 'TechMaster Deploy ZIP (*.zip)|*.zip'
    if ($path) { $script:session.Mode='Local'; $script:session.Package=$path; Start-UpdateOperation 'PrepareLocal' }
})
$controls.Cancel.Add_Click({ $window.Close() })
$window.Add_Closing({
    param($sender, $event)
    if ($script:session.Job) {
        $event.Cancel = $true
        if ($script:session.State -eq 'Applying') { $controls.Summary.Text = 'Đang thay tệp chương trình. Chờ hoàn tất trước khi đóng.'; return }
        $script:session.CloseRequested = $true
        Request-DeployWorkCancel $script:session.Job
        $controls.Cancel.IsEnabled = $false; $controls.Summary.Text = 'Đang huỷ thao tác…'
    }
})
$window.Add_ContentRendered({ Start-InitialUpdate })
if ($ValidateOnly) { return $window }
try { [void]$window.ShowDialog() } finally { $timer.Stop() }
