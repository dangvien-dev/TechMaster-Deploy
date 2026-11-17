$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UltraViewer.Diagnostics.ps1')
function Get-ItemProperty($Path) {
    if ($Path -like '*Uninstall*') { [pscustomobject]@{ DisplayName='UltraViewer';DisplayVersion='6.6.133';InstallLocation='C:\UltraViewer' } }
    else { [pscustomobject]@{ DriverDesc='Test adapter';NetworkAddress='001122334455' } }
}
function Get-CimInstance { [pscustomobject]@{ Name='UltraViewer_Desktop.exe';ProcessId=999;CommandLine='password=DO-NOT-EXPORT' } }
function Get-NetAdapter { [pscustomobject]@{ Name='Ethernet';InterfaceDescription='Test NIC';MacAddress='00-11-22-33-44-55';HardwareInterface=$true;Status='Up' } }
function Test-Path { $true }
function Get-Item {
    $entry=[pscustomobject]@{}
    $entry | Add-Member ScriptMethod GetValueNames { @('ID','Password','SecretToken','Settings') }
    $entry | Add-Member ScriptMethod GetValue { param($name,$default,$options) if ($name -ne 'ID') { throw 'Never read credentials' }; return 'cloned-install-identity-test' }
    return $entry
}
function Stop-Process { throw 'Diagnostic must never stop a session' }
function Set-ItemProperty { throw 'Diagnostic must never change registry' }
function Remove-Item { throw 'Diagnostic must never delete configuration' }
function Set-NetAdapterAdvancedProperty { throw 'Diagnostic must never change MAC' }
$result=Get-UltraViewerDiagnostic
$text=Format-UltraViewerDiagnostic $result
if ($text -notmatch '6.6.133' -or $text -notmatch '00-11-22-33-44-55' -or $text -notmatch '001122334455' -or $text -notmatch '999') { throw 'Missing required diagnostics.' }
if ($text -match 'DO-NOT-EXPORT|Password|SecretToken|cloned-install-identity-test') { throw 'Sensitive fields or raw identity were exposed.' }
if ($result.RegistryFields[0].IdentityHashes[0].SHA256 -notmatch '^[a-f0-9]{64}$') { throw 'Missing comparable identity fingerprint.' }
if ($result.Running[0].PSObject.Properties.Name -contains 'CommandLine') { throw 'Unexpected process secrets exported.' }
Write-Host 'PASS: UltraViewer 6.6.133 read-only diagnostics include versions/MAC/override/session IDs; no passwords or mutation.'
