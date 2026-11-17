# Only generates XML into a temporary directory; no Sysprep or OS writes.
$ErrorActionPreference = 'Stop'
$script:checks = 0
$global:TMAnswerTest = @{ UiOverride = $null; UserLocale = 'en-US' }
function Assert($condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Get-WinUILanguageOverride { $global:TMAnswerTest.UiOverride }
function Get-UICulture { [Globalization.CultureInfo]::GetCultureInfo('en-US') }
function Get-Culture { [Globalization.CultureInfo]::GetCultureInfo([string]$global:TMAnswerTest.UserLocale) }
function Get-WinSystemLocale { [Globalization.CultureInfo]::GetCultureInfo('en-US') }
function Set-Culture { throw 'Do not modify locale' }
function Set-WinUserLanguageList { throw 'Do not modify languages' }
function Read-Answer([string]$path) {
    $doc = New-Object Xml.XmlDocument
    $doc.Load($path)
    $ns = New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    $component = $doc.SelectSingleNode("//u:component[@name='Microsoft-Windows-International-Core']", $ns)
    [pscustomobject]@{ Document = $doc; Namespace = $ns; Component = $component }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-answer-' + [guid]::NewGuid().ToString('N'))
try {
    $sourcePath = Join-Path $PSScriptRoot 'unattend.xml'
    $source = Read-Answer $sourcePath
    Assert ($null -eq $source.Component.SelectSingleNode('u:UserLocale', $source.Namespace)) 'Template no longer hardcodes the user region'
    Assert ($null -eq $source.Component.SelectSingleNode('u:UILanguage', $source.Namespace)) 'Template no longer forces Vietnamese UI'
    $global:TMAnswerTest.UiOverride = $null; $global:TMAnswerTest.UserLocale = 'en-US'
    $out = Join-Path $temp 'answer.xml'
    & (Join-Path $PSScriptRoot 'New-Unattend.ps1') -OutputPath $out
    $answer = Read-Answer $out
    foreach ($name in 'SystemLocale', 'UILanguage', 'UserLocale') {
        Assert ($answer.Component.SelectSingleNode('u:' + $name, $answer.Namespace).InnerText -ceq 'en-US') 'Generated answer preserves the English master image settings'
    }
    Assert ($answer.Component.SelectSingleNode('u:InputLocale', $answer.Namespace).InnerText -ceq '0409:00000409') 'US keyboard preference retained for first login'
    Assert ($answer.Document.SelectSingleNode('//u:TimeZone', $answer.Namespace).InnerText -ceq 'SE Asia Standard Time') 'Other answer-file deployment settings remain intact'
    $global:TMAnswerTest.UiOverride = [Globalization.CultureInfo]::GetCultureInfo('fr-FR'); $global:TMAnswerTest.UserLocale = 'en-GB'
    & (Join-Path $PSScriptRoot 'New-Unattend.ps1') -OutputPath $out
    $answer = Read-Answer $out
    Assert ($answer.Component.SelectSingleNode('u:UILanguage', $answer.Namespace).InnerText -ceq 'fr-FR') 'Explicit master UI override preserved independently of region'
    Assert ($answer.Component.SelectSingleNode('u:UserLocale', $answer.Namespace).InnerText -ceq 'en-GB') 'Master region preserved independently of UI language'
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'New-Unattend.ps1') -OutputPath $sourcePath } catch { $rejected = $_.Exception.Message -match 'Không ghi đè' }
    Assert $rejected 'Generator cannot overwrite the source template'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }; Remove-Variable TMAnswerTest -Scope Global }
Write-Host "PASS: $script:checks answer-file assertions; preserves master image locale/UI and never invokes Sysprep."
