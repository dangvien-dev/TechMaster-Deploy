# Exercises the real HTML exporter with mocked CIM and browser startup.
# Does not change activation or open a browser. Removes only its own report.
$ErrorActionPreference = 'Stop'
$script:checks = 0
$global:TMReportTestFixture = [pscustomobject]@{ Win = @(); Office = @(); FailWin = $false; FailOffice = $false; Opened = '' }
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}
function New-License($name, [int]$status) {
    # Count = null reproduces the problematic scalar adaptation even on PS7.
    [pscustomobject]@{ Name = $name; LicenseStatus = $status; PartialProductKey = 'ABCDE'; Description = 'RETAIL channel'; Count = $null }
}
function Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName, [string]$Filter)
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer = 'Test'; Model = 'Mock' } }
        'Win32_BIOS' { [pscustomobject]@{ SerialNumber = 'TEST-SERIAL' } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Windows Test'; BuildNumber = '1' } }
        'SoftwareLicensingProduct' {
            if ($Filter -match '55c92734') {
                if ($global:TMReportTestFixture.FailWin) { throw 'Mock Windows query failed' }
                $global:TMReportTestFixture.Win
            } else {
                if ($global:TMReportTestFixture.FailOffice) { throw 'Mock Office query failed' }
                $global:TMReportTestFixture.Office
            }
        }
        default { throw "Unexpected CIM query: $ClassName" }
    }
}
function Start-Process($FilePath) { $global:TMReportTestFixture.Opened = $FilePath }
$previousName = $env:COMPUTERNAME
$env:COMPUTERNAME = 'TMReportTest_' + [guid]::NewGuid().ToString('N')
$ownReport = $null
function Run-Report([string]$expectedClass) {
    $global:TMReportTestFixture.Opened = ''
    $path = & (Join-Path $PSScriptRoot 'Bien-Ban-Ban-Quyen.ps1') -NoPrompt -Customer 'Test' -Technician 'Test'
    $script:ownReport = $path
    $html = [Net.WebUtility]::HtmlDecode([IO.File]::ReadAllText($path))
    Assert ($global:TMReportTestFixture.Opened -eq $path) 'Exporter opens the generated report path'
    Assert ($html -match ('<div class="sum ' + $expectedClass + '">')) "Summary must be $expectedClass"
    Assert ($html -notmatch '\{\{[A-Z_]+\}\}') 'No unreplaced template placeholders'
    return $html
}
try {
    $global:TMReportTestFixture.FailWin = $false; $global:TMReportTestFixture.FailOffice = $false
    $global:TMReportTestFixture.Win = @(New-License 'Windows Professional' 1)
    $global:TMReportTestFixture.Office = @(New-License 'Office24 Retail' 1)
    $html = Run-Report 'ok'
    Assert ($html -notmatch 'Có sản phẩm <b>chưa kích hoạt') 'Single active Windows + single active Office never produce a red summary'
    Assert ([regex]::Matches($html, "class='ok'>Đã kích hoạt").Count -eq 2) 'Both actual product rows are active'

    $global:TMReportTestFixture.Office = @()
    $html = Run-Report 'ok'
    Assert ($html -match 'Không phát hiện Office') 'Absent key-based Office is labelled explicitly'

    $global:TMReportTestFixture.Office = @(New-License 'Office Retail' 1; New-License 'Office Grace' 2)
    $html = Run-Report 'bad'
    Assert ($html -match 'Office Grace' -and $html -match 'Chưa kích hoạt \(dùng thử\)') 'A real inactive Grace row remains visible and makes the summary red'

    $global:TMReportTestFixture.Win = @(New-License 'Windows Professional' 5)
    $global:TMReportTestFixture.Office = @(New-License 'Office Retail' 1)
    $null = Run-Report 'bad'

    $global:TMReportTestFixture.Win = @()
    $html = Run-Report 'warn'
    Assert ($html -match 'Không đọc được thông tin Windows') 'Missing Windows data is unknown, not an invented activation failure'

    $global:TMReportTestFixture.Win = @(New-License 'Windows Professional' 1)
    $global:TMReportTestFixture.FailOffice = $true
    $html = Run-Report 'warn'
    Assert ($html -match 'Không đọc được thông tin Office' -and $html -notmatch 'Không phát hiện Office') 'Office query errors are distinguished from no Office installation'

    $global:TMReportTestFixture.FailOffice = $false; $global:TMReportTestFixture.FailWin = $true
    $html = Run-Report 'warn'
    Assert ($html -notmatch 'Có sản phẩm <b>chưa kích hoạt') 'Windows query failure is not called unactivated'
} finally {
    if ($script:ownReport -and (Test-Path -LiteralPath $script:ownReport)) { Remove-Item -LiteralPath $script:ownReport -Force }
    $env:COMPUTERNAME = $previousName
    Remove-Variable -Name TMReportTestFixture -Scope Global
}
Write-Host "PASS: $script:checks assertions; real HTML export with mocked CIM."
