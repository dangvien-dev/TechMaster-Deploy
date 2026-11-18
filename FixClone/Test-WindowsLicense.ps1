# All system reads/removals/installations are mocked. Never changes Windows licensing.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Windows.License.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function License([string]$tail='3V66T',[int]$status=5,[string]$channel='Retail',[string]$name='Windows(R), Professional edition'){
    [pscustomobject]@{ID='11111111-2222-3333-4444-555555555555';Name=$name;PartialProductKey=$tail;LicenseStatus=$status;ProductKeyChannel=$channel;Description=$channel}
}
function Reset-Fixture {
    $script:products=@(License);$script:verified=$true;$script:removed=@();$script:installed=0;$script:removeFail=$false;$script:pretendSuccess=$false
}
function Get-CimInstance{param($ClassName,$Filter) return $script:products}
function Test-WindowsProSetupKey{return $script:verified}
function Start-Sleep{}
function Remove-WindowsSetupLicense([string]$id){
    $script:removed+=$id
    if(-not $script:pretendSuccess){$script:products=@()}
    if($script:removeFail){throw 'fixture uninstall failure'}
}
function Install-WindowsProSetupKey{$script:installed++;$script:products=@(License)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-win-key-'+[guid]::NewGuid().ToString('N'))
try{
    Reset-Fixture
    $inventory=Get-WindowsSetupKeyInventory
    Assert ($inventory.Items.Count -eq 1 -and $inventory.Items[0].Eligible) 'Unactivated Pro setup key requires matching SKU, Retail channel and verified full public setup key'
    foreach($state in 2,3,6){Assert ((Get-WindowsLicenseStateText $state) -notmatch 'dùng thử|hết hạn dùng thử') 'Windows grace states are not labelled evaluation/trial'}
    Assert ((Get-WindowsSetupActivationNotice $inventory) -match 'Installation ID') 'A setup key with an IID still requires a private key before offline activation'
    foreach($case in @(
        @{Item=(License -status 1);Verified=$true},
        @{Item=(License -tail 'ABCDE');Verified=$true},
        @{Item=(License -channel 'OEM:DM');Verified=$true},
        @{Item=(License -channel 'Volume:GVLK');Verified=$true},
        @{Item=(License -name 'Windows Enterprise Evaluation');Verified=$true},
        @{Item=(License -status 4);Verified=$true},
        @{Item=(License);Verified=$false}
    )){
        $script:products=@($case.Item);$script:verified=$case.Verified
        $result=Invoke-WindowsSetupKeyCleanup -ReceiptPath (Join-Path $temp 'should-not-exist.json')
        Assert (-not $result.Changed -and $script:removed.Count -eq 0 -and -not (Test-Path (Join-Path $temp 'should-not-exist.json'))) 'Activated, private, OEM, volume, evaluation, unknown or unverified keys are preserved'
    }
    Reset-Fixture;$script:products=@((License),(License -tail 'ABCDE' -status 1))
    Assert (-not @((Get-WindowsSetupKeyInventory).Items|Where-Object Eligible).Count -and -not (Get-WindowsSetupActivationNotice (Get-WindowsSetupKeyInventory))) 'Any active Windows license protects existing activation, including digital activation'
    Reset-Fixture;$other=License;$other.ID='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';$script:products+=@($other)
    Assert (-not @((Get-WindowsSetupKeyInventory).Items|Where-Object Eligible).Count) 'Ambiguous multiple setup-key records cannot be removed automatically'
    Reset-Fixture;$seen=Get-WindowsSetupKeyInventory;$script:products=@(License -status 1);$blocked=$false
    try{Invoke-WindowsSetupKeyCleanup -Inventory $seen -ReceiptPath (Join-Path $temp 'stale.json')|Out-Null}catch{$blocked=$true}
    Assert ($blocked -and $script:removed.Count -eq 0) 'A plan becomes invalid when Windows activates after review'
    Reset-Fixture;$path=Join-Path $temp 'receipt.json'
    $result=Invoke-WindowsSetupKeyCleanup -ReceiptPath $path
    Assert ($result.Changed -and $script:removed.Count -eq 1 -and $script:removed[0] -eq '11111111-2222-3333-4444-555555555555' -and -not $script:products.Count) 'Cleanup targets only the reviewed license ID and verifies that its key is gone'
    $receipt=[IO.File]::ReadAllText($path)
    Assert ($receipt -match '3V66T' -and $receipt -notmatch 'VK7JG|ProductKey|BackupProductKey') 'Receipt never contains full keys or copied registry key data'
    $restored=Restore-WindowsSetupKeyCleanup $path
    Assert ($restored.Restored -and $script:installed -eq 1) 'Undo restores only the public Pro setup key when no current key exists'
    $script:products=@(License -tail 'CUSTOM' -status 1);$restored=Restore-WindowsSetupKeyCleanup $path
    Assert (-not $restored.Restored -and $script:installed -eq 1 -and $script:products[0].PartialProductKey -eq 'CUSTOM') 'Undo never overwrites a new private/activated key'
    Reset-Fixture;$script:removeFail=$true;$caught=''
    try{Invoke-WindowsSetupKeyCleanup -ReceiptPath (Join-Path $temp 'failed.json')|Out-Null}catch{$caught=$_.Exception.Message}
    Assert ($caught -match 'fixture uninstall failure' -and $script:installed -eq 1 -and $script:products.Count -eq 1) 'A backend failure after removal restores the public setup key'
    Reset-Fixture;$script:pretendSuccess=$true;$caught=''
    try{Invoke-WindowsSetupKeyCleanup -ReceiptPath (Join-Path $temp 'no-change.json')|Out-Null}catch{$caught=$_.Exception.Message}
    Assert ($caught -and $script:installed -eq 0) 'A successful exit code alone is insufficient; the observed installed key must disappear'
    Reset-Fixture;$script:products=@(License -tail '3V66T' -status 1)
    Assert (-not (Get-WindowsSetupActivationNotice (Get-WindowsSetupKeyInventory))) 'An activated digital-license system with the shared setup key is not blocked'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks Windows license assertions; verified setup-only removal, preserved licenses, fresh-state checks, receipts, rollback and IID guidance."
