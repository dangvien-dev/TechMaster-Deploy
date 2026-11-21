param([ValidateSet('Menu','Inspect','Keys','Remove')][string]$Mode='Menu',[string]$LogPath='',[string]$ProgressPath='',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Office-Cleanup.Core.ps1')
$cleanupWindow=Import-DeployWindow (Join-Path $PSScriptRoot 'Office-Cleanup.xml')
if($Mode -eq 'Keys'){
    $cleanupWindow.Title='Key Office / dùng tạm'
    $cleanupWindow.FindName('Heading').Text='Key Office / dùng tạm'
    $cleanupWindow.FindName('Instructions').Text='Bấm Chọn key dùng thử để đánh dấu các key Grace / Trial chưa kích hoạt đã nhận diện. Kiểm tra danh sách rồi xác nhận xoá. Key không chọn được giữ, gồm Retail; các thiết lập Word được giữ.'
    $cleanupWindow.FindName('RemoveOffice').Visibility='Collapsed'
}

$script:cleanup=@{ Job=$null; Inventory=$null; Rows=@(); ExitCode=0; Log=$LogPath }
if (-not $script:cleanup.Log) { $script:cleanup.Log=Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Office Logs/'+[guid]::NewGuid().ToString('N')+'/Cleanup.log') }
function Set-CleanupBusy([bool]$busy) {
    foreach ($name in 'Keys','Refresh','SelectTrial','DeleteKeys','RemoveOffice','Close') { $cleanupWindow.FindName($name).IsEnabled = -not $busy }
    if($Mode -eq 'Inspect'){foreach($name in 'SelectTrial','DeleteKeys','RemoveOffice'){$cleanupWindow.FindName($name).IsEnabled=$false};$cleanupWindow.FindName('Keys').IsReadOnly=$true}
    $cleanupWindow.FindName('Progress').IsIndeterminate=$busy
}
function Start-CleanupOperation([string]$operation,[string[]]$ids=@()) {
    if ($script:cleanup.Job) { return }
    Set-CleanupBusy $true
    Set-DeployNotice ($cleanupWindow.FindName('Status')) $(if($operation -eq 'Inspect'){'Đang đọc Office…'}else{'Đang xử lý các mục đã chọn…'}) 'Working'
    $script:cleanup.Job=Start-DeployWork @'
param($directory,$operation,$inventory,$ids,$log,$progress)
$ErrorActionPreference='Stop'
. (Join-Path $directory 'Office-Cleanup.Core.ps1')
. (Join-Path $directory 'Office-Cleanup.Engine.ps1')
Invoke-OfficeCleanupTask -Operation $operation -Inventory $inventory -SelectedIds $ids -LogPath $log -ProgressPath $progress
'@ @($PSScriptRoot,$operation,$script:cleanup.Inventory,$ids,$script:cleanup.Log,$ProgressPath)
    $script:cleanup.Operation=$operation; $cleanupTimer.Start()
}
function Set-CleanupInventory($inventory) {
    $script:cleanup.Inventory=$inventory
    $script:cleanup.Rows=@($inventory.Keys | ForEach-Object {
        [pscustomobject]@{ Selected=$false; ID=$_.ID; Kind=(Get-OfficeLicenseKind $_); Status=$(if($_.LicenseStatus -eq 1){'Đã kích hoạt'}else{'Chưa kích hoạt'}); Last5=$_.PartialProductKey; Name=$_.Name; Temporary=(Test-OfficeTemporaryLicense $_) }
    })
    $cleanupWindow.FindName('Keys').ItemsSource=$script:cleanup.Rows
    $cleanupWindow.FindName('Products').Text='Click-to-Run: '+($inventory.Products -join ', ')
}
$cleanupTimer=New-DeployTimer 200 {
    $job=$script:cleanup.Job
    if (-not $job -or -not $job.Async.IsCompleted) { return }
    $cleanupTimer.Stop();$script:cleanup.Job=$null
    try {
        $result=@(Receive-DeployWork $job)[-1]
        if ($script:cleanup.Operation -eq 'Inspect') { Set-CleanupInventory $result; Set-DeployNoticeKind ($cleanupWindow.FindName('Status')) 'Info'; $cleanupWindow.FindName('Status').Text=$(if($Mode -eq 'Keys'){'Chọn key dùng thử hoặc kiểm tra từng key trước khi xoá. Chưa có key nào được chọn tự động.'}else{'Chọn key cần xoá hoặc chỉ kiểm tra danh sách.'}) }
        else { Set-CleanupInventory $result.Inventory; Set-DeployNotice ($cleanupWindow.FindName('Status')) $result.Message $(if($result.Outcome -eq 'NoChange'){'Info'}else{'Success'}); $script:cleanup.ExitCode=0 }
    } catch { $script:cleanup.ExitCode=1; Set-DeployNotice ($cleanupWindow.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'; Show-DeployMessage $_.Exception.GetBaseException().Message 'Gỡ / dọn Office' 'Error' }
    finally { Set-CleanupBusy $false }
}
function Confirm-CleanupOperation([string]$operation) {
    if ($Mode -eq 'Keys' -and $operation -ne 'Keys') { return }
    if (-not $script:cleanup.Inventory -or $script:cleanup.Job) { return }
    $cleanupWindow.FindName('Keys').CommitEdit() | Out-Null
    $ids=@($script:cleanup.Rows | Where-Object Selected | ForEach-Object ID)
    try { $plan=New-OfficeSelectedPlan $script:cleanup.Inventory $ids $operation }
    catch { Show-DeployMessage $_.Exception.Message 'Kiểm tra lựa chọn' 'Warning';return }
    if (-not @($plan.Keys).Count -and -not @($plan.Products).Count) { Show-DeployMessage 'Chưa chọn key để xoá.';return }
    $names=(@($plan.Keys | ForEach-Object { $_.Name+' — '+$_.PartialProductKey }) -join "`n")
    $message='Key sẽ xoá:' + "`n"+$names+"`n`nKey không chọn được giữ lại. Lưu tài liệu và đóng Office trước khi tiếp tục."
    if ($operation -eq 'Remove') { $message+=' Sẽ gỡ các bộ Office: '+($plan.Products -join ', ') }
    if (Confirm-Box $message 'Xác nhận gỡ / dọn Office' -ConfirmText $(if($operation -eq 'Remove'){'Gỡ Office'}else{'Xoá key đã chọn'}) -Danger -Owner $cleanupWindow) { Start-CleanupOperation $operation $ids }
}
$cleanupWindow.FindName('Refresh').Add_Click({ Start-CleanupOperation 'Inspect' })
$cleanupWindow.FindName('SelectTrial').Add_Click({ foreach($row in $script:cleanup.Rows){$row.Selected=$row.Temporary};$cleanupWindow.FindName('Keys').Items.Refresh() })
$cleanupWindow.FindName('DeleteKeys').Add_Click({ Confirm-CleanupOperation 'Keys' })
$cleanupWindow.FindName('RemoveOffice').Add_Click({ Confirm-CleanupOperation 'Remove' })
$cleanupWindow.FindName('Close').Add_Click({$cleanupWindow.Close()})
$cleanupWindow.FindName('ViewLog').Add_Click({if(Test-Path -LiteralPath $script:cleanup.Log){Start-Process notepad.exe ('"{0}"' -f $script:cleanup.Log)}})
$cleanupWindow.Add_Closing({param($sender,$event) if($script:cleanup.Job){$event.Cancel=$true}})
$cleanupWindow.Add_ContentRendered({Start-CleanupOperation 'Inspect'})
Set-CleanupBusy $false
if($ValidateOnly){return $cleanupWindow}
try{[void]$cleanupWindow.ShowDialog()}finally{$cleanupTimer.Stop()}
exit $script:cleanup.ExitCode
