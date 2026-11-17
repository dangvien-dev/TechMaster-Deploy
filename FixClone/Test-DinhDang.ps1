# Runs the actual formatting entrypoint with mocked registry/native commands.
$ErrorActionPreference = 'Stop'
$global:TMFormatTestValues = @{ LocaleName = 'en-US'; sShortDate = 'MM/dd/yyyy'; sShortTime = 'h:mm tt'; sList = ','; iMeasure = '1' }
$global:TMFormatTestWrites = @()
function reg.exe {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$registryArgs)
    $nameIndex = [array]::IndexOf($registryArgs, '/v')
    $valueIndex = [array]::IndexOf($registryArgs, '/d')
    if ($registryArgs[0] -ne 'add' -or $nameIndex -lt 0 -or $valueIndex -lt 0) { throw 'Unexpected registry operation' }
    $global:TMFormatTestValues[[string]$registryArgs[$nameIndex+1]] = [string]$registryArgs[$valueIndex+1]
    $global:TMFormatTestWrites += [string]$registryArgs[$nameIndex+1]
    $global:LASTEXITCODE = 0
}
function Get-ItemProperty { [pscustomobject]$global:TMFormatTestValues }
function Set-Culture { throw 'Formatting must not change the culture' }
function Set-WinUserLanguageList { throw 'Formatting must not change languages/keyboards' }
function Set-WinDefaultInputMethodOverride { throw 'Formatting must not change default keyboard' }
function Add-Type { throw 'Native broadcast omitted in this test' }
try {
    . (Join-Path $PSScriptRoot 'Fix-DinhDang.ps1')
    foreach ($entry in @{ LocaleName = 'en-US'; sShortDate = 'MM/dd/yyyy'; sShortTime = 'h:mm tt'; sDecimal = ','; sThousand = '.'; sList = ','; iMeasure = '1' }.GetEnumerator()) {
        if ($global:TMFormatTestValues[$entry.Key] -cne $entry.Value) { throw "FAIL: formatting value $($entry.Key)" }
    }
    if (($global:TMFormatTestWrites | Sort-Object) -join ',' -cne 'sDecimal,sThousand') { throw 'FAIL: more than the two number fields were written' }
    $global:TMFormatTestWrites = @()
    Set-Intl 'HKU\FixtureDefault'
    if (($global:TMFormatTestWrites | Sort-Object) -join ',' -cne 'sDecimal,sThousand') { throw 'FAIL: default-profile formatter writes other settings' }
    Write-Host 'PASS: actual format entrypoint and default-profile writer change only decimal/group symbols; all other locale/input settings untouched.'
} finally { Remove-Variable TMFormatTestValues,TMFormatTestWrites -Scope Global }
