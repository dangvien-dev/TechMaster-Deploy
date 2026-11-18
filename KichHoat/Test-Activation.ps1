# All CIM calls are mocked. This test never activates or changes a license.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Activation.Core.ps1')
$script:checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}
$license = [pscustomobject]@{ Name='Office Retail';ID = 'office-retail'; ApplicationID = '0ff1ce15-a989-479d-af46-f275c6370663';PartialProductKey='ABCDE';OfflineInstallationId=('1'*63) }
function Reset-Mocks {
    $script:shape = 'Void'
    $script:returnCode = 0
    $script:states = @(1)
    $script:reads = 0
    $script:calls = @()
    $script:wrongLicense = $false
    $script:readError = $false
    $script:refreshError = $false
    $script:methodError = $false
    $script:wrongKey=$false;$script:wrongIid=$false
}
function Start-Sleep {}
function Invoke-CimMethod($InputObject, $MethodName, $Arguments) {
    if ($MethodName -eq 'RefreshLicenseStatus') {
        if ($script:refreshError) { throw 'Refresh unavailable' }
        return
    }
    $script:calls += [pscustomobject]@{ ID = $InputObject.ID; Method = $MethodName; Arguments = $Arguments }
    if ($script:methodError) { throw 'CIM access denied' }
    switch ($script:shape) {
        'Void' { return }
        'NoReturnValue' { return [pscustomobject]@{ PSComputerName = 'test' } }
        'Code' { return [pscustomobject]@{ ReturnValue = $script:returnCode } }
    }
}
function Get-CimInstance($ClassName, $InputObject) {
    if ($ClassName -eq 'SoftwareLicensingService') { return [pscustomobject]@{ ID = 'service' } }
    if ($script:readError) { throw 'Readback unavailable' }
    $state = $script:states[[Math]::Min($script:reads, $script:states.Count - 1)]
    $script:reads++
    return [pscustomobject]@{
        ID = $(if ($script:wrongLicense) { 'other-license' } else { $InputObject.ID })
        ApplicationID = $InputObject.ApplicationID
        LicenseStatus = $state
        Name=$InputObject.Name
        PartialProductKey=$(if($script:wrongKey){'OTHER'}else{$InputObject.PartialProductKey})
        OfflineInstallationId=$(if($script:wrongIid){'9'*63}else{$InputObject.OfflineInstallationId})
    }
}
$iid = '1' * 63
$cid = '2' * 48
foreach ($method in @('Activate', 'DepositOfflineConfirmationId')) {
    foreach ($shape in @('Void', 'NoReturnValue', 'Code')) {
        Reset-Mocks
        $script:shape = $shape
        $outcome = Invoke-VerifiedLicenseActivation $license $method $iid $cid
        Assert ($outcome.State -eq 'Activated') "$method with $shape succeeds when the exact license is active"
        Assert ($script:calls.Count -eq 1 -and $script:calls[0].ID -eq $license.ID) 'Activation is submitted only once to the requested license'
        if ($method -eq 'DepositOfflineConfirmationId') {
            Assert ($script:calls[0].Arguments.InstallationId -eq $iid -and $script:calls[0].Arguments.ConfirmationId -eq $cid) 'IID and CID passed unchanged'
        }
    }
}
Reset-Mocks
$script:states = @(2, 1)
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Activated' -and $script:reads -eq 2 -and $script:calls.Count -eq 1) 'Delayed state refresh succeeds without resubmitting CID'
Reset-Mocks
$script:states = @(2)
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Unconfirmed' -and $outcome.Detail -notmatch 'ReturnValue|0x') 'Void and inactive never fabricate a blank hex error or success'
Assert ($script:reads -eq 4 -and $script:calls.Count -eq 1) 'Verification retries are bounded and read-only'
Reset-Mocks
$script:shape = 'Code'
$script:states = @(2)
$outcome = Invoke-VerifiedLicenseActivation $license 'Activate'
Assert ($outcome.State -eq 'Unconfirmed') 'Return code zero alone does not claim activation'
Reset-Mocks
$script:shape = 'Code'
$script:returnCode = 2147942405
$script:states = @(2)
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Failed' -and $outcome.Detail -match '0x80070005') 'Real nonzero error code preserved'
Reset-Mocks
$script:methodError = $true
$script:states = @(2)
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Failed' -and $outcome.Detail -match 'CIM access denied') 'Real CIM exception preserved'
Reset-Mocks
$script:methodError = $true
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Activated') 'Verified active state avoids contradictory failure after a CIM exception'
Reset-Mocks
$script:wrongLicense = $true
$blocked=$false;try{Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid|Out-Null}catch{$blocked=$true}
Assert ($blocked -and -not $script:calls.Count) 'Another license is blocked before CID submission'
Reset-Mocks
$script:readError = $true
$blocked=$false;try{Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid|Out-Null}catch{$blocked=$true}
Assert ($blocked -and -not $script:calls.Count) 'A read failure blocks CID submission instead of trusting a cached IID'
Reset-Mocks
$script:refreshError = $true
$outcome = Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid
Assert ($outcome.State -eq 'Activated') 'Exact active readback is sufficient when service refresh fails'
Reset-Mocks
$windows = [pscustomobject]@{ ID = 'windows'; ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' }
$outcome = Invoke-VerifiedLicenseActivation $windows 'Activate'
Assert ($outcome.State -eq 'Activated' -and $script:calls[0].ID -eq 'windows') 'Windows uses the same verified handling'
Write-Host "PASS: $script:checks activation assertions; all CIM operations mocked."

Assert ((Get-MissingActivationKeyMessage 'Office') -match 'Word' -and (Get-MissingActivationKeyMessage 'Office') -match 'Microsoft 365') 'Missing Office keys give product-key and subscription instructions'
Assert ((Get-MissingActivationKeyMessage 'Windows') -match 'Change product key') 'Missing Windows keys give the native Microsoft entry point'
Assert (Test-OfficeActivationNeedsKey @()) 'An empty Office inventory needs a key notice'
Assert (Test-OfficeActivationNeedsKey @([pscustomobject]@{Name='Office24HomeBusiness2024R_Grace';Description='RETAIL channel';LicenseStatus=2})) 'An explicitly temporary Office SKU is not sent to activation as a private key'
Assert (-not (Test-OfficeActivationNeedsKey @([pscustomobject]@{Name='Office Retail';Description='RETAIL channel';LicenseStatus=2}))) 'Pending activation of a normal Retail key is not mistaken for a trial by status alone'
Write-Host 'PASS: missing-key and explicit Office trial notifications; no UI or license changes.'

foreach($fault in 'wrongKey','wrongIid'){
    Reset-Mocks;Set-Variable -Scope Script -Name $fault -Value $true
    $blocked=$false;try{Invoke-VerifiedLicenseActivation $license 'DepositOfflineConfirmationId' $iid $cid|Out-Null}catch{$blocked=$true}
    Assert ($blocked -and -not $script:calls.Count) 'Changing the key or IID while QR is open blocks CID before any activation method call'
}
Reset-Mocks
$shared=[pscustomobject]@{Name='Windows Professional';ID='windows-shared';ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f';PartialProductKey='3V66T';OfflineInstallationId=('1'*63)}
$script:states=@(5);$blocked=$false
try{Get-OfflineActivationLicense $shared|Out-Null}catch{$blocked=$true}
Assert $blocked 'The generic Windows Pro key cannot be used to generate an offline QR when unactivated'
Write-Host 'PASS: strict key / license / Installation ID binding before QR and CID submission.'

$generic=[pscustomobject]@{Name='Windows Professional';PartialProductKey='3V66T';LicenseStatus=5}
$private=[pscustomobject]@{Name='Windows Professional';PartialProductKey='ABCDE';LicenseStatus=5}
$chosen=@(Select-ActivationLicenses Windows @($generic,$private))
Assert ($chosen.Count -eq 1 -and $chosen[0].PartialProductKey -eq 'ABCDE') 'When both old setup and newly entered private records exist, only the private key is selected'
Assert (@(Select-ActivationLicenses Windows @($generic) -Offline).Count -eq 0 -and @(Select-ActivationLicenses Windows @($generic)).Count -eq 1) 'Only a digital-license online attempt is allowed for the setup key'
Write-Host 'PASS: current private key is selected instead of stale setup records.'
