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
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks UltraViewer lifecycle assertions; sealed master, new clone identity, idempotence, pending retry, rollback scope and preserved cache."
