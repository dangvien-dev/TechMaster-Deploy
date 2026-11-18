# Functions only; no activation occurs when this file is dot-sourced.
function Invoke-VerifiedLicenseActivation($license,
    [ValidateSet('Activate', 'DepositOfflineConfirmationId')][string]$method,
    [string]$installationId = '', [string]$confirmationId = '') {
    if (-not $license.ID -or $license.ApplicationID -notin @(
        '55c92734-d682-4d71-983e-d6ec3f16059f', '0ff1ce15-a989-479d-af46-f275c6370663')) {
        throw 'Không xác định được license Windows / Office cần kích hoạt.'
    }
    if($method -eq 'DepositOfflineConfirmationId'){
        if($installationId -notmatch '^(?:[0-9]{54}|[0-9]{63})$' -or $confirmationId -notmatch '^[0-9]{48}$'){throw 'Installation ID / Confirmation ID chưa đúng định dạng; chưa nạp mã.'}
        $license=Get-OfflineActivationLicense $license $installationId
    }
    $expectedTail=[string]$license.PartialProductKey
    $methodError = ''
    try {
        if ($method -eq 'DepositOfflineConfirmationId') {
            $result = Invoke-CimMethod -InputObject $license -MethodName $method -ErrorAction Stop `
                -Arguments @{ InstallationId = $installationId; ConfirmationId = $confirmationId }
        } else {
            $result = Invoke-CimMethod -InputObject $license -MethodName $method -ErrorAction Stop
        }
        # Void/no-output is not an error code. Confirm actual activation below.
        if ($null -ne $result.ReturnValue -and $result.ReturnValue -ne 0) {
            $methodError = 'ReturnValue 0x{0:X8}' -f ($result.ReturnValue -band 0xffffffffL)
        }
    } catch { $methodError = $_.Exception.Message }

    $stateDetail = 'Trạng thái chưa chuyển sang ĐÃ KÍCH HOẠT.'
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            # A refresh failure alone does not invalidate a successful readback.
            try {
                $service = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
                Invoke-CimMethod -InputObject $service -MethodName RefreshLicenseStatus -ErrorAction Stop | Out-Null
            } catch {}
            $fresh = Get-CimInstance -InputObject $license -ErrorAction Stop
            if ($null -eq $fresh -or $fresh.ID -ne $license.ID -or $fresh.ApplicationID -ne $license.ApplicationID -or $null -eq $fresh.LicenseStatus) {
                throw 'Không đọc được trạng thái của đúng license vừa xử lý.'
            }
            if($expectedTail -and [string]$fresh.PartialProductKey -ine $expectedTail){throw 'Key đã thay đổi trong khi xác minh kích hoạt.'}
            if ($fresh.LicenseStatus -eq 1) {
                return [pscustomobject]@{ State = 'Activated'; Detail = 'Đã xác nhận LicenseStatus = 1 của đúng license.' }
            }
            $stateDetail = 'LicenseStatus hiện tại: {0}.' -f $fresh.LicenseStatus
        } catch { $stateDetail = 'Chưa đọc được trạng thái để xác minh: ' + $_.Exception.Message }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 300 }
    }
    if ($methodError) { return [pscustomobject]@{ State = 'Failed'; Detail = $methodError + ' ' + $stateDetail } }
    return [pscustomobject]@{ State = 'Unconfirmed'; Detail = $stateDetail }
}

function Get-MissingActivationKeyMessage([ValidateSet('Windows','Office')][string]$Product) {
    if($Product -eq 'Office'){
        return 'Chưa tìm thấy key Office đã nhập để kích hoạt. Với Office 2021/2024, mở Word → File → Account → Change Product Key và nhập key bản quyền, rồi kiểm tra lại. Với Microsoft 365, đăng nhập tài khoản có giấy phép trong Word.'
    }
    return 'Chưa tìm thấy key Windows đã nhập để kích hoạt. Mở Settings → System → Activation → Change product key để nhập key bản quyền của máy này. Nếu dùng bản quyền số, kiểm tra trạng thái tại Activation.'
}

function Test-OfficeActivationNeedsKey([object[]]$Products) {
    if(-not $Products.Count){return $true}
    # State 2 alone is not proof of a trial; only explicit temporary SKU names qualify.
    $permanent=@($Products|Where-Object {([string]$_.Name+' '+[string]$_.Description) -notmatch '(?i)(?:^|[_\W])(?:GRACE|TRIAL|EVAL)(?:$|[_\W])'})
    return ($permanent.Count -eq 0)
}

function Get-OfflineActivationLicense($License,[string]$InstallationId='') {
    if(-not $License.ID -or $License.ApplicationID -notin '55c92734-d682-4d71-983e-d6ec3f16059f','0ff1ce15-a989-479d-af46-f275c6370663' -or [string]$License.PartialProductKey -notmatch '^[A-Za-z0-9]{5}$'){
        throw 'Chưa xác định được đúng sản phẩm và key cần lấy Installation ID.'
    }
    $fresh=Get-CimInstance -InputObject $License -ErrorAction Stop
    if(-not $fresh -or $fresh.ID -ne $License.ID -or $fresh.ApplicationID -ne $License.ApplicationID -or [string]$fresh.PartialProductKey -ine [string]$License.PartialProductKey){
        throw 'Key hoặc sản phẩm đã thay đổi. Chạy kiểm tra lại để lấy Installation ID mới; không dùng QR / CID cũ.'
    }
    $iid=([string]$fresh.OfflineInstallationId -replace '\D','')
    if($iid -notmatch '^(?:[0-9]{54}|[0-9]{63})$'){throw 'Chưa đọc được Installation ID hợp lệ của key hiện tại.'}
    if($InstallationId -and $iid -cne $InstallationId){throw 'Installation ID đã thay đổi. Đóng QR cũ và lấy mã mới trước khi nạp Confirmation ID.'}
    if($fresh.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' -and $fresh.PartialProductKey -ieq '3V66T' -and $fresh.LicenseStatus -ne 1){
        throw 'Windows còn dùng key cài đặt chung …3V66T. Nhập key riêng trước khi dùng QR / portal.'
    }
    if($fresh.ApplicationID -eq '0ff1ce15-a989-479d-af46-f275c6370663' -and (Test-OfficeActivationNeedsKey @($fresh))){
        throw 'Office còn dùng giấy phép Grace / Trial. Nhập key riêng trước khi lấy Installation ID.'
    }
    return $fresh
}

function Select-ActivationLicenses {
    param([ValidateSet('Windows','Office')][string]$Product,[object[]]$Products,[switch]$Offline)
    if($Product -eq 'Office'){
        return @($Products|Where-Object {-not (Test-OfficeActivationNeedsKey @($_))})
    }
    $private=@($Products|Where-Object {$_.PartialProductKey -ine '3V66T'})
    if($private.Count -or $Offline){return $private}
    # A setup key may activate online via an existing digital license, never via an offline QR.
    return $Products
}
