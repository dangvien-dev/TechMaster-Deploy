# Lifecycle model uses real receipts/markers and fake registry/services; no Windows mutation.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UltraViewer.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Expect-Failure([scriptblock]$action,[string]$pattern){$caught='';try{&$action|Out-Null}catch{$caught=$_.Exception.Message};Assert ($caught -match $pattern) "Expected $pattern; got $caught"}
$script:device='a'*64;$script:version='6.6.133';$script:fields=@{UID='master-original';PreferID='111111111';LastHR='keep-this'}
$script:startup='Automatic';$script:running=$true;$script:stops=0;$script:starts=0;$script:issued=0;$script:offline=$false
function Get-UltraVersion{$script:version}
function Get-UltraDeviceHash{$script:device}
function Protect-UltraBackup($path){}
function Get-UltraIdentity{
    $data=[ordered]@{}
    foreach($name in 'UID','PreferID'){$data[$name]=[pscustomobject]@{Exists=$script:fields.ContainsKey($name);Value=$(if($script:fields.ContainsKey($name)){$script:fields[$name]}else{''})}}
    return [pscustomobject]$data
}
function Set-UltraIdentity($identity,[switch]$Clear){foreach($name in 'UID','PreferID'){if($Clear -or -not $identity.$name.Exists){$script:fields.Remove($name)}else{$script:fields[$name]=$identity.$name.Value}}}
function Get-UltraServices{[pscustomobject]@{Name='UltraViewerService';Startup=$script:startup;WasRunning=$script:running}}
function Stop-UltraRuntime($services,[switch]$Disable){if(@($services).Count -ne 1 -or $services[0].Name -ne 'UltraViewerService'){throw 'Wrong service scope'};$script:stops++;$script:running=$false;if($Disable){$script:startup='Disabled'}}
function Start-UltraRuntime($services){
    $script:starts++;$script:startup=$services[0].Startup;$script:running=$services[0].WasRunning
    if($script:running -and -not $script:offline -and -not $script:fields.ContainsKey('UID')){$script:issued++;$script:fields.UID='new-'+$script:issued;$script:fields.PreferID=(200000000+$script:issued).ToString()}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-ultra-'+[guid]::NewGuid().ToString('N'))
$marker=Join-Path $temp 'UltraViewer-Clone.json';$backups=Join-Path $temp 'backups'
try {
    $receipt=Prepare-UltraForClone $marker $backups
    Assert ((Test-Path $receipt) -and (Test-Path $marker)) 'Master receipt and boot marker persist'
    Assert (-not $script:fields.ContainsKey('UID') -and -not $script:fields.ContainsKey('PreferID')) 'Master is sealed without identity'
    Assert ($script:startup -eq 'Disabled' -and -not $script:running -and $script:starts -eq 0) 'Master service stays disabled; no new ID can be assigned before imaging'
    Assert ((Read-UltraReceipt $receipt).Identity.UID.Value -ceq 'master-original') 'Original ID is backed up before modification'
    Assert ($script:fields.LastHR -ceq 'keep-this') 'LastHR is preserved during preparation'
    Expect-Failure {Prepare-UltraForClone $marker $backups} 'chưa kết thúc'
    $script:device='b'*64
    $done=Complete-UltraAfterClone $marker $backups
    Assert ($done.State -eq 'Complete' -and $script:fields.UID -ne 'master-original' -and $script:fields.PreferID -ne '111111111') 'Clone receives both new identity values'
    Assert ($script:startup -eq 'Automatic' -and $script:running) 'Clone restores original service configuration'
    $uid=$script:fields.UID;$stops=$script:stops
    $null=Complete-UltraAfterClone $marker $backups
    Assert ($script:fields.UID -ceq $uid -and $script:stops -eq $stops) 'Repeated cleanup keeps ID stable'
    $script:device='c'*64
    $null=Complete-UltraAfterClone $marker $backups
    Assert ($script:fields.UID -ceq $uid -and $script:stops -eq $stops) 'Completed marker never resets ID just because adapter/device fingerprint changes'
    Expect-Failure {Restore-UltraReceipt $receipt} 'máy gốc'
    Assert ($script:stops -eq $stops) 'Cross-device restore is blocked before disconnecting anything'
    $manual=Invoke-UltraReset $backups
    Assert ($script:fields.UID -cne $uid) 'Explicit manual reset obtains another identity'
    Restore-UltraReceipt $manual.Receipt
    Assert ($script:fields.UID -ceq $uid -and $script:fields.LastHR -ceq 'keep-this') 'Local restore reinstates exactly the previous two values'
    $script:version='6.7.0';$stops=$script:stops
    Expect-Failure {Invoke-UltraReset $backups} 'chưa được kiểm tra'
    Assert ($script:stops -eq $stops) 'Unsupported versions never stop a session'
    $script:version='6.6.133'
    $null=Prepare-UltraForClone $marker $backups
    $script:device='d'*64;$script:offline=$true
    $pending=Complete-UltraAfterClone $marker $backups
    Assert ($pending.State -eq 'Pending') 'Offline registration is reported as pending, not success'
    $stops=$script:stops;$script:offline=$false;$script:device='e'*64
    $done=Complete-UltraAfterClone $marker $backups
    Assert ($done.State -eq 'Complete' -and $script:stops -eq $stops) 'Pending retry finishes registration without clearing identity again, including after an adapter change'
    Assert ($script:fields.LastHR -ceq 'keep-this') 'Every workflow leaves LastHR unchanged'

    # Reopen/reboot simulation: no in-memory receipt path, disk is the only history.
    $localBackups=Join-Path $temp 'manual-history';$noMarker=Join-Path $temp 'absent.json'
    $script:offline=$true
    $manual=Invoke-UltraReset $localBackups
    $stops=$script:stops;$starts=$script:starts
    $loaded=Get-UltraHistoryStatus $localBackups $noMarker
    Assert ($loaded.Receipt -eq $manual.Receipt -and $loaded.UiKind -eq 'Attention') 'Reopen recovers pending reset from old-format receipt storage'
    Assert ($script:stops -eq $stops -and $script:starts -eq $starts) 'Loading history never stops or starts UltraViewer'
    $checked=Get-UltraHistoryStatus $localBackups $noMarker -Check
    Assert ($checked.UiKind -eq 'Attention') 'Missing current identity cannot be marked verified'
    $script:offline=$false;Start-UltraRuntime @(Get-UltraServices)
    $checked=Get-UltraHistoryStatus $localBackups $noMarker -Check
    Assert ($checked.UiKind -eq 'Success') 'Check verifies both identities against saved receipt without another reset'
    $saved=Read-UltraReceipt $manual.Receipt
    Assert ($saved.Phase -eq 'Verified' -and @($saved.Events).Count -ge 3) 'Verification and timestamped event journal persist on disk'
    Assert ((Get-UltraHistoryStatus $localBackups $noMarker).UiKind -eq 'Success') 'Fresh read recovers previously verified state'
    Assert ($script:stops -eq $stops) 'Repeated verification does not reset identity'
    Restore-UltraReceipt $manual.Receipt
    Assert ((Read-UltraReceipt $manual.Receipt).Phase -eq 'Restored') 'Restore records completion only after both values are verified'
    Assert ((Get-UltraHistoryStatus $localBackups $noMarker -Check).UiKind -eq 'Info') 'Restored receipt is not reported as a new identity'
    $script:fields.UID='partially-changed';$script:fields.PreferID=(Read-UltraReceipt $manual.Receipt).Identity.PreferID.Value
    Set-UltraReceiptState $manual.Receipt 'AwaitingIdentity'
    Assert ((Get-UltraHistoryStatus $localBackups $noMarker -Check).UiKind -eq 'Attention') 'Changing just one identity value cannot pass verification'
    Restore-UltraReceipt $manual.Receipt
    $normalSetter=${function:Set-UltraIdentity}
    function Set-UltraIdentity($identity,[switch]$Clear){if($Clear){throw 'simulated registry failure'};& $normalSetter $identity}
    $failureRoot=Join-Path $temp 'failed-reset'
    try{Expect-Failure {Invoke-UltraReset $failureRoot} 'simulated registry failure'}finally{Set-Item Function:Set-UltraIdentity $normalSetter}
    $failedHistory=Get-UltraResetHistory $failureRoot $noMarker
    Assert ($failedHistory.Phase -eq 'ResetFailed') 'Failed reset rollback persists a distinct failure state'
    Assert ((Get-UltraHistoryStatus $failureRoot $noMarker -Check).UiKind -eq 'Attention') 'Failed reset is never reported as verified on reopen/check'
    $events=@((Read-UltraReceipt $failedHistory.Receipt).Events)
    Assert (@($events[0].PSObject.Properties.Name).Count -eq 2) 'Journal records timestamps and phases without identity/password values'
    $script:device='f'*64
    Assert (-not (Get-UltraResetHistory $localBackups $noMarker).Receipt) 'History copied to a different machine is ignored'
    $script:device='e'*64
    # Legacy v2.2.5 manual reset: no Updated or Events properties.
    $legacy=New-UltraReceipt $localBackups 'Manual' @(Get-UltraServices)
    $legacy.Data.Phase='AwaitingIdentity';$legacy.Data.Date=(Get-Date).AddMinutes(1).ToString('o');Write-UltraJson $legacy.Data $legacy.Path
    Assert ((Get-UltraResetHistory $localBackups $noMarker).Receipt -eq $legacy.Path) 'Previous release receipts are recovered without migration/reset'
    $unused=New-UltraReceipt $localBackups 'Manual' @(Get-UltraServices)
    Assert ((Get-UltraResetHistory $localBackups $noMarker).Receipt -eq $legacy.Path) 'Backup-only receipt is not mistaken for a completed reset'
    $prepared=New-UltraReceipt $localBackups 'Prepare' @(Get-UltraServices)
    $prepared.Data.Phase='Prepared';Write-UltraJson $prepared.Data $prepared.Path
    Assert ((Get-UltraResetHistory $localBackups $noMarker).Receipt -eq $legacy.Path) 'Master preparation is not mistaken for a client reset'
    $bad=Join-Path $localBackups 'bad';New-Item -ItemType Directory $bad | Out-Null
    [IO.File]::WriteAllText((Join-Path $bad 'identity.json'),'{broken')
    $damaged=Get-UltraHistoryStatus $localBackups $noMarker
    Assert ($damaged.Receipt -eq $legacy.Path -and $damaged.UiKind -eq 'Attention') 'Corrupt unrelated receipt warns while retaining valid same-machine history'
    $onlyBad=Join-Path $temp 'only-bad';New-Item -ItemType Directory (Join-Path $onlyBad 'bad') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $onlyBad 'bad/identity.json'),'{broken')
    Assert ((Get-UltraHistoryStatus $onlyBad $noMarker).UiKind -eq 'Attention') 'Only corrupt history reports unreadable data instead of no reset'
    # Legacy AfterClone receipt must use master baseline and a same-machine marker.
    $cloneRoot=Join-Path $temp 'clone-history'
    $clone=New-UltraReceipt $cloneRoot 'AfterClone' @(Get-UltraServices)
    $cloneMarker=Join-Path $temp 'history-clone.json'
    Write-UltraJson ([pscustomobject]@{Schema=1;Phase='Complete';Receipt=$receipt;Device=$script:device;LocalReceipt=$clone.Path}) $cloneMarker
    Assert ((Get-UltraHistoryStatus $cloneRoot $cloneMarker).UiKind -eq 'Success') 'Legacy completed clone marker recovers local receipt'
    Assert (-not (Get-UltraResetHistory $cloneRoot $noMarker).Receipt) 'Orphan backup-only clone receipt is not presented as reset history'
    $cloneMeta=Get-Content -LiteralPath $cloneMarker -Raw | ConvertFrom-Json
    $cloneMeta.Device='a'*64;Write-UltraJson $cloneMeta $cloneMarker
    Assert (-not (Get-UltraResetHistory $cloneRoot $cloneMarker).Receipt) 'Clone marker from another machine cannot authorize local history'
    Restore-UltraReceipt $clone.Path
    Assert ((Get-UltraHistoryStatus $cloneRoot $noMarker).UiKind -eq 'Info') 'Restored clone receipt remains discoverable after marker removal'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks UltraViewer lifecycle assertions; sealed master, new clone identity, idempotence, pending retry, rollback scope and preserved cache."
