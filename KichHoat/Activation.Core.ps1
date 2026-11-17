# Functions only; no activation occurs when this file is dot-sourced.
function Invoke-VerifiedLicenseActivation($license,
    [ValidateSet('Activate', 'DepositOfflineConfirmationId')][string]$method,
    [string]$installationId = '', [string]$confirmationId = '') {
    if (-not $license.ID -or $license.ApplicationID -notin @(
        '55c92734-d682-4d71-983e-d6ec3f16059f', '0ff1ce15-a989-479d-af46-f275c6370663')) {
        throw 'Không xác định được license Windows / Office cần kích hoạt.'
    }
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
