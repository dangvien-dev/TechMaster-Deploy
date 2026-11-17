$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UltraViewer.Core.ps1')
. (Join-Path $PSScriptRoot 'Master.Deployment.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Invoke-MasterPreparation{$script:events+='save-word'}
function Invoke-MasterPreCheck{$script:events+='precheck'}
function Confirm-Box{$script:events+='confirm';return $script:confirm}
function Invoke-MasterTemporaryOfficeCleanup($logRoot){$script:events+='trial';if($script:trialFail){throw 'trial failed'}}
function Prepare-UltraForClone($marker,$backup){$script:events+='seal-ultra';return 'fake-receipt'}
function Restore-UltraReceipt($receipt){$script:events+='restore-ultra'}
function Invoke-MasterSysprep($system,$unattend){$script:events+='sysprep';if($script:fail){throw 'sysprep failed'}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-master-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$options=[pscustomobject]@{Schema=1;CleanOfficeTrial=$true;PrepareUltra=$true}
try{
    $script:confirm=$true;$script:fail=$false;$script:trialFail=$false;$script:events=@()
    $done=Invoke-MasterDeployment $options $temp 'fake-system' 'fake-unattend'
    Assert ($done -and ($script:events -join ',') -ceq 'save-word,precheck,confirm,trial,seal-ultra,sysprep') 'Word preferences are saved before license removal; identity is sealed immediately before Sysprep'
    $script:events=@();$script:fail=$true;$caught=''
    try{Invoke-MasterDeployment $options $temp 'fake-system' 'fake-unattend'}catch{$caught=$_.Exception.Message}
    Assert ($caught -match 'sysprep failed' -and $script:events[-1] -ceq 'restore-ultra') 'Sysprep failure restores Ultra identity and service state'
    $script:events=@();$script:fail=$false;$script:confirm=$false
    $done=Invoke-MasterDeployment $options $temp 'fake-system' 'fake-unattend'
    Assert (-not $done -and ($script:events -join ',') -ceq 'save-word,precheck,confirm') 'Cancelling final button does not remove any keys or stop UltraViewer'
    $script:confirm=$true;$script:trialFail=$true;$script:events=@()
    try{Invoke-MasterDeployment $options $temp 'fake-system' 'fake-unattend'}catch{}
    Assert ('seal-ultra' -notin $script:events -and 'sysprep' -notin $script:events) 'License-cleanup failure prevents sealing or shutting down'
    $script:events=@();$caught=''
    try{Invoke-MasterDeployment ([pscustomobject]@{Schema=1;CleanOfficeTrial='true';PrepareUltra=$true}) $temp 'system' 'unattend'}catch{$caught=$_.Exception.Message}
    Assert ($caught -match 'không hợp lệ' -and $script:events.Count -eq 0) 'Corrupted options cannot enable destructive stages'
    $script:events=@()
    Invoke-ClonePreparedCleanup (Join-Path $temp 'unprepared')
    Assert ($script:events.Count -eq 0) 'Old/unprepared installations never auto-delete keys or reset IDs'
}finally{Remove-Item $temp -Recurse -Force}
Write-Host "PASS: $checks master-deployment orchestration assertions; save settings first, cancel safely, rollback and no unprepared cleanup."
