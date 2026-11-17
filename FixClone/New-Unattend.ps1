# Keep the image's own language/region instead of forcing a Vietnamese locale.
param(
    [string]$TemplatePath = (Join-Path $PSScriptRoot 'unattend.xml'),
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFullPath($TemplatePath) -eq [IO.Path]::GetFullPath($OutputPath)) { throw 'Không ghi đè mẫu unattend gốc.' }
$override = Get-WinUILanguageOverride -ErrorAction Stop
$ui = if ($null -ne $override) { $override.Name } else { (Get-UICulture).Name }
$values = [ordered]@{
    SystemLocale = (Get-WinSystemLocale -ErrorAction Stop).Name
    UILanguage = $ui
    UserLocale = (Get-Culture).Name
}
foreach ($value in $values.Values) {
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'Không đọc được vùng / ngôn ngữ máy gốc.' }
    $null = [Globalization.CultureInfo]::GetCultureInfo($value)
}
$doc = New-Object Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.Load($TemplatePath)
$ns = New-Object Xml.XmlNamespaceManager($doc.NameTable)
$ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
$component = $doc.SelectSingleNode("/u:unattend/u:settings[@pass='oobeSystem']/u:component[@name='Microsoft-Windows-International-Core']", $ns)
if ($null -eq $component) { throw 'Mẫu thiếu cấu hình vùng cho OOBE.' }
foreach ($name in $values.Keys) {
    $node = $component.SelectSingleNode('u:' + $name, $ns)
    if ($null -eq $node) { $node = $doc.CreateElement($name, 'urn:schemas-microsoft-com:unattend'); $null = $component.AppendChild($node) }
    $node.InnerText = $values[$name]
}
New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Force | Out-Null
$writer = [Xml.XmlWriter]::Create($OutputPath, [Xml.XmlWriterSettings]@{ Encoding = [Text.UTF8Encoding]::new($false); Indent = $true })
try { $doc.Save($writer) } finally { $writer.Dispose() }
Write-Host 'Đã tạo cấu hình clone theo vùng và ngôn ngữ hiện tại của máy gốc; bàn phím US.'
