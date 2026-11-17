# Run with PowerShell 5.1+; all Windows mutations are mocked, no Office is required.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Office-Cleanup.Core.ps1')
$script:checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}
function Assert-Throws([scriptblock]$action, [string]$pattern) {
    $caught = $null
    try { & $action } catch { $caught = $_.Exception.Message }
    Assert ($null -ne $caught -and $caught -match $pattern) "Expected failure: $pattern; actual: $caught"
}
function License($id, $name, $app = $script:OfficeApplicationId, $tail = 'ABCDE') {
    [pscustomobject]@{ ID = $id; Name = $name; ApplicationID = $app; PartialProductKey = $tail }
}
$office21 = License 'o21' 'Office21ProPlus2021VL_KMS_Client_AE'
$office24 = License 'o24' 'Office24HomeBusiness2024R_Retail'
$office16 = License 'o16' 'Office16ProPlusVL_KMS_Client'
$project = License 'p24' 'Office24ProjectPro2024VL_KMS_Client'
$windows = License 'win' 'Windows Professional' '55c92734-d682-4d71-983e-d6ec3f16059f'
$inventory = [pscustomobject]@{
    Products = @('ProPlus2021Volume', 'HomeBusiness2024Retail', 'ProjectPro2024Volume', 'O365ProPlusRetail', 'ProPlus2019Volume', 'Unknown2024Retail')
    Keys = @($office21, $office24, $office16, $project, $windows)
}
$remove = Get-OfficeCleanupPlan $inventory 'Remove'
$keys = Get-OfficeCleanupPlan $inventory 'Keys'
Assert ($remove.Products.Count -eq 2) 'Only supported 2021/2024 Office suites selected'
Assert ($remove.Keys.Count -eq 2 -and 'win' -notin $remove.Keys.ID -and 'p24' -notin $remove.Keys.ID) 'Remove preserves Windows, Project and older Office keys'
Assert ($keys.Keys.Count -eq 4 -and 'win' -notin $keys.Keys.ID -and $keys.Products.Count -eq 0) 'Keys mode selects Office only, including old Office/Project; no uninstall'
$xml = [xml](New-OfficeRemovalXml $remove.Products)
Assert (@($xml.Configuration.Remove.Product).Count -eq 2) 'ODT XML targets the two exact product IDs'
Assert (-not $xml.Configuration.Remove.All -and -not $xml.Configuration.RemoveMSI -and -not $xml.Configuration.Property) 'No broad uninstall or forced app shutdown'
Assert-Throws { New-OfficeRemovalXml @('ProjectPro2024Volume') } 'Không cho phép'
Assert-Throws { New-OfficeRemovalXml @('Unknown2024Retail') } 'Không cho phép'
Assert-Throws { New-OfficeRemovalXml @() } 'Không có sản phẩm'
Assert ((Get-OfficeLicenseKind $office24) -eq 'Retail') 'Retail is labelled for the selector'
Assert ((Get-OfficeLicenseKind (License 'grace' 'Office24HomeBusiness2024R_Grace edition')) -eq 'Grace / dùng thử') 'Grace is separate from Retail'
$none = Select-OfficeCleanupKeys $keys ''
Assert ($none.Keys.Count -eq 0 -and $none.PreservedKeys.Count -eq 4) 'Empty selection preserves all Office keys'
$one = Select-OfficeCleanupKeys $keys '1'
Assert ($one.Keys.Count -eq 1 -and $one.Keys[0].ID -eq 'o21' -and 'o24' -in $one.PreservedKeys.ID) 'Select a KMS key while retaining Retail'
$multi = Select-OfficeCleanupKeys $keys '1, 3,1'
Assert ($multi.Keys.Count -eq 2 -and 'o24' -notin $multi.Keys.ID -and 'o24' -in $multi.PreservedKeys.ID) 'Multiple rows deduplicated without selecting Retail'
Assert-Throws { Select-OfficeCleanupKeys $keys '0' } 'không hợp lệ'
Assert-Throws { Select-OfficeCleanupKeys $keys '5' } 'không hợp lệ'
Assert-Throws { Select-OfficeCleanupKeys $keys '99999999999999999999999' } 'không hợp lệ'
Assert-Throws { Select-OfficeCleanupKeys $keys '1,abc' } 'Nhập số thứ tự'
Assert-Throws { Select-OfficeCleanupKeys $keys '-1' } 'Nhập số thứ tự'
Assert-Throws { Select-OfficeCleanupKeys $keys '1,' } 'Nhập số thứ tự'
Assert-Throws { Select-OfficeCleanupKeys $remove '1' } 'giữ lại key'
Assert-Throws { Select-OfficeCleanupKeys $remove '' } 'giữ lại key'
$explicitRemove = Select-OfficeCleanupKeys $remove '1,2'
Assert ($explicitRemove.Keys.Count -eq 2 -and $explicitRemove.PreservedKeys.Count -eq 0) 'Uninstall accepts explicitly selecting all affected keys'

$script:calls = @()
$script:methodFailure = ''
$script:methodResult = 'ReturnValue'
$script:methodException = $false
$script:kmsHost = ''
$script:kmsPort = 0
$script:missingKmsProperty = $false
function Invoke-CimMethod($InputObject, $MethodName) {
    $script:calls += "$($InputObject.ID):$MethodName"
    if ($script:methodException) { throw 'CIM access denied' }
    if ($script:methodResult -eq 'Void') { return }
    if ($script:methodResult -eq 'NoReturnProperty') { return [pscustomobject]@{ PSComputerName = 'test' } }
    [pscustomobject]@{ ReturnValue = $(if ($MethodName -eq $script:methodFailure) { 5 } else { 0 }) }
}
function Get-CimInstance {
    if ($script:missingKmsProperty) { return [pscustomobject]@{ ID = 'test' } }
    [pscustomobject]@{ KeyManagementServiceMachine = $script:kmsHost; KeyManagementServicePort = $script:kmsPort }
}
Assert-Throws { Invoke-OfficeLicenseMethod $windows 'UninstallProductKey' } 'ngoài Office'
Assert ($script:calls.Count -eq 0) 'Windows rejected before calling CIM'
$script:methodFailure = 'UninstallProductKey'
Assert-Throws { Invoke-OfficeLicenseMethod $office21 'UninstallProductKey' } 'thất bại'
$script:methodFailure = ''
function Get-Process { if ($script:appRunning) { [pscustomobject]@{ ProcessName = 'WINWORD' } } }
$script:appRunning = $true
Assert-Throws { Assert-OfficeCleanupAppsClosed } 'đóng ứng dụng'
$script:appRunning = $false
function Get-OfficeCleanupInventory { $script:after }
$script:processCount = 0
$script:odtCode = 0
function Start-Process {
    $script:processCount++
    $p = [pscustomobject]@{ ExitCode = $script:odtCode }
    $p | Add-Member ScriptMethod Dispose {}
    return $p
}
$work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $script:calls = @()
    $script:after = [pscustomobject]@{ Products = @('ProjectPro2024Volume', 'O365ProPlusRetail', 'ProPlus2019Volume'); Keys = @($windows, $project, $office16) }
    Invoke-OfficeCleanupPlan $remove 'mock-verified-setup.exe' $work
    Assert ($script:calls.Count -eq 6 -and $script:calls[0] -eq 'o21:ClearKeyManagementServiceMachine' -and $script:calls[2] -eq 'o21:UninstallProductKey') 'KMS reset precedes key removal for exact licenses'
    Assert ($script:processCount -eq 1 -and -not (Test-Path (Join-Path $work 'remove.xml'))) 'ODT executed and temporary XML removed'
    $script:after = $inventory
    Assert-Throws { Invoke-OfficeCleanupPlan $remove 'mock-verified-setup.exe' $work } 'vẫn thấy key'
    $script:processCount = 0
    $script:methodFailure = 'UninstallProductKey'
    Assert-Throws { Invoke-OfficeCleanupPlan $remove 'mock-verified-setup.exe' $work } 'Chưa dọn xong key'
    Assert ($script:processCount -eq 0) 'License failure blocks uninstall'
    $script:methodFailure = ''
    $script:odtCode = 1603
    Assert-Throws { Invoke-OfficeCleanupPlan $remove 'mock-verified-setup.exe' $work } '1603'
    Assert (-not (Test-Path (Join-Path $work 'remove.xml'))) 'ODT failure also removes XML'
    $script:processCount = 0
    $script:after = [pscustomobject]@{ Products = $inventory.Products; Keys = @($windows) }
    Invoke-OfficeCleanupPlan $keys '' $work
    Assert ($script:processCount -eq 0) 'Keys mode does not run ODT'

    # Regression from the uploaded Windows PowerShell 5.1 transcript: a
    # successful clear method can return no ReturnValue on Retail/Grace licenses.
    foreach ($shape in @('Void', 'NoReturnProperty')) {
        $script:methodResult = $shape
        $script:calls = @()
        Invoke-OfficeCleanupPlan $keys '' $work
        Assert ($script:calls.Count -eq 12) "$shape results reach key uninstall after verified KMS readback"
    }
    $script:methodResult = 'Void'
    $retailInventory = [pscustomobject]@{
        Products = @('HomeBusiness2024Retail')
        Keys = @((License 'grace24' 'Office 24, Office24HomeBusiness2024R_Grace edition'), (License 'retail24' 'Office 24, Office24HomeBusiness2024R_Retail edition'))
    }
    $retailPlan = Get-OfficeCleanupPlan $retailInventory 'Keys'
    $script:after = [pscustomobject]@{ Products = $retailInventory.Products; Keys = @() }
    $script:calls = @()
    Invoke-OfficeCleanupPlan $retailPlan '' $work
    Assert ($script:calls.Count -eq 6 -and $script:calls[-1] -eq 'retail24:UninstallProductKey') 'Retail + Grace scenario from transcript succeeds with void methods and verified removal'

    # The requested workflow: remove only Grace, retain the user's Retail.
    # Both fixtures intentionally have the same five-character suffix.
    $partial = Select-OfficeCleanupKeys $retailPlan '1'
    $script:after = [pscustomobject]@{ Products = $retailInventory.Products; Keys = @($retailInventory.Keys[1]) }
    $script:calls = @()
    $script:processCount = 0
    Invoke-OfficeCleanupPlan $partial '' $work
    Assert ($script:calls.Count -eq 3 -and @($script:calls | Where-Object { $_ -like 'retail24:*' }).Count -eq 0) 'Only selected Grace receives CIM calls; Retail is never touched'
    Assert ($script:processCount -eq 0) 'Selective key cleanup never uninstalls Office'
    $script:after = [pscustomobject]@{ Products = $retailInventory.Products; Keys = @() }
    Assert-Throws { Invoke-OfficeCleanupPlan $partial '' $work } 'giữ lại không còn khớp'
    $script:calls = @()
    Invoke-OfficeCleanupPlan (Select-OfficeCleanupKeys $retailPlan '') '' $work
    Assert ($script:calls.Count -eq 0 -and $script:processCount -eq 0) 'Empty key choice executes no mutations'
    $script:after = $inventory
    Assert-Throws { Invoke-OfficeCleanupPlan $keys '' $work } 'vẫn thấy key'
    $script:kmsHost = 'kms.example.invalid'
    $script:calls = @()
    Assert-Throws { Invoke-OfficeCleanupPlan $keys '' $work } 'Chưa dọn xong key'
    Assert (@($script:calls | Where-Object { $_ -match 'UninstallProductKey' }).Count -eq 0) 'Void clear with surviving KMS host blocks key uninstall'
    $script:kmsHost = ''
    $script:kmsPort = 1688
    Assert-Throws { Invoke-OfficeLicenseMethod $office21 'ClearKeyManagementServicePort' } 'chưa xoá được'
    $script:kmsPort = 0
    $script:missingKmsProperty = $true
    Assert-Throws { Invoke-OfficeLicenseMethod $office21 'ClearKeyManagementServiceMachine' } 'không đọc được'
    $script:missingKmsProperty = $false
    $script:methodException = $true
    Assert-Throws { Invoke-OfficeLicenseMethod $office21 'UninstallProductKey' } 'CIM access denied'
    $script:methodException = $false
    $script:methodResult = 'ReturnValue'

    $script:calls = @()
    $script:appRunning = $true
    Assert-Throws { Invoke-OfficeCleanupPlan $keys '' $work } 'đóng ứng dụng'
    Assert ($script:calls.Count -eq 0) 'Open documents block all key changes'
    $script:appRunning = $false

    # A present but untrusted ODT must not be accepted.
    Set-Content (Join-Path $work 'setup.exe') 'not a signed executable'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
    Assert-Throws { Get-OfficeCleanupSetup $work } 'chữ ký Microsoft'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Other, O=Microsoft Corporation Evil' } } }
    Assert-Throws { Get-OfficeCleanupSetup $work } 'chữ ký Microsoft'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US' } } }
    Assert ((Get-OfficeCleanupSetup $work) -eq (Join-Path $work 'setup.exe')) 'Valid Microsoft publisher accepted'
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
Write-Host "PASS: $script:checks assertions; all destructive operations mocked."
