# Noninteractive operations; UI chooses keys and confirms before calling Apply.
function Invoke-OfficeCleanupTask {
    param([ValidateSet('Inspect','Keys','Remove','Temporary')][string]$Operation, $Inventory, [string[]]$SelectedIds=@(), [string]$LogPath='', [string]$ProgressPath='')
    if ($Operation -eq 'Inspect') { return Get-OfficeCleanupInventory }
    $mutex=New-Object Threading.Mutex($false,'Global\TechMaster.OfficeDeployment')
    $owned=$false
    try {
        try { $owned=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned=$true }
        if (-not $owned) { throw 'Office đang được cài / dọn ở cửa sổ khác.' }
        $fresh=Get-OfficeCleanupInventory
        if ($Inventory) { Assert-OfficeInventoryUnchanged $Inventory $fresh }
        if ($Operation -eq 'Temporary') { $plan=Get-OfficeTemporaryPlan $fresh }
        else { $plan=New-OfficeSelectedPlan $fresh $SelectedIds $Operation }
        if (-not @($plan.Keys).Count -and -not @($plan.Products).Count) { return [pscustomobject]@{ Message='Không có key phù hợp để xoá.'; Inventory=$fresh;Outcome='NoChange' } }
        Assert-OfficeCleanupAppsClosed
        if (-not $LogPath) { $LogPath=Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Office Logs/'+[guid]::NewGuid().ToString('N')+'/Cleanup.log') }
        $directory=Split-Path -Parent $LogPath
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $setup=''
        if ($Operation -eq 'Remove') { $setup=Get-OfficeCleanupSetup (Join-Path $PSScriptRoot 'ODT') }
        if ($ProgressPath) { [IO.File]::WriteAllText($ProgressPath,'Đang gỡ / dọn Office…') }
        try { & { Invoke-OfficeCleanupPlan $plan $setup $directory } *> $LogPath }
        catch { [IO.File]::AppendAllText($LogPath, "`nLỖI: " + $_.Exception.Message); throw }
        $after=Get-OfficeCleanupInventory
        return [pscustomobject]@{ Message='Đã kiểm tra: hoàn tất thao tác đã chọn, các key giữ lại vẫn còn.'; Inventory=$after;Outcome='Complete' }
    } finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
