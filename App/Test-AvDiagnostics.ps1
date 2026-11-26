$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AV.Diagnostics.ps1')
foreach ($name in 'windir','ProgramData','ProgramFiles','COMPUTERNAME','SystemDrive') { if (-not (Get-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue)) { Set-Item -LiteralPath ('Env:' + $name) -Value $(switch ($name) { 'windir' {'C:\Windows'} 'ProgramData' {'C:\ProgramData'} 'ProgramFiles' {'C:\Program Files'} 'COMPUTERNAME' {'TEST-PC'} default {'C:'} }) } }

# Any mutation is a test failure: the diagnostic is read-only.
foreach ($blocked in 'Remove-Item','Set-ItemProperty','New-ItemProperty','Add-MpPreference','Set-MpPreference','Remove-MpPreference','Remove-MpThreat','Stop-Service','Set-Service','Unregister-ScheduledTask','Disable-ScheduledTask','Stop-Process','Move-Item','Copy-Item') {
    Set-Item -Path ('Function:' + $blocked) -Value ([scriptblock]::Create("throw 'Diagnostic must never call $blocked'"))
}

function Get-CimInstance { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) $script:Case.Products }
function Get-MpComputerStatus { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) [pscustomobject]@{ AMRunningMode = 'Passive Mode'; RealTimeProtectionEnabled = $false; AntivirusSignatureLastUpdated = '2026-11-25' } }
function Get-MpThreat { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) $script:Case.Threats }
function Get-MpThreatDetection { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) $script:Case.Detections }
function Get-MpPreference { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) [pscustomobject]@{ ExclusionPath = $script:Case.Exclusions; ExclusionProcess = @('N/A: Must be an administrator to view exclusions') } }
function Get-WinEvent { [CmdletBinding()] param([string]$ListLog, [string]$LogName, [int]$MaxEvents) @() }
function Get-ItemProperty { [CmdletBinding()] param($LiteralPath) if ($LiteralPath -like '*exefile*') { [pscustomobject]@{ '(default)' = $script:Case.ExeCommand } } else { [pscustomobject]@{ '(default)' = '"%1" %*' } } }
function Test-Path { [CmdletBinding()] param($LiteralPath) $script:Case.Existing -contains $LiteralPath }
function Get-ChildItem { [CmdletBinding()] param($LiteralPath, [switch]$Recurse, [switch]$File, [switch]$Directory) $script:Case.Files | Where-Object { $_.Path.StartsWith($LiteralPath + '\') } | ForEach-Object { [pscustomobject]@{ FullName = $_.Path; Name = Split-Path $_.Path -Leaf; Extension = [IO.Path]::GetExtension($_.Path) } } }
function Get-AuthenticodeSignature { [CmdletBinding()] param($LiteralPath) [pscustomobject]@{ Status = ($script:Case.Files | Where-Object Path -eq $LiteralPath).Status } }
function Get-ScheduledTask { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) $script:Case.Tasks }
function Get-Service { [CmdletBinding()] param($Namespace, $ClassName, $ListLog) @([pscustomobject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; Status = 'Running' }) }

$officeWord = 'C:\Program Files\Microsoft Office\Office14\WINWORD.EXE'
$zaloDll = 'C:\Users\Admin\AppData\Local\Programs\Zalo\Zalo-26.11.12\Qt5Core.dll'
$zaloExe = 'C:\Users\Admin\AppData\Local\Programs\Zalo\Zalo.exe'
$roots = @('C:\Program Files\Microsoft Office', 'C:\Users\Admin\AppData\Local\Programs\Zalo')

# Case 1: the reported machine - both AV off, Office 2010 Valid, Zalo DLL unsigned, no traces.
$script:Case = @{
    Products = @([pscustomobject]@{ displayName = 'Windows Defender'; productState = 393472 }, [pscustomobject]@{ displayName = 'Kaspersky'; productState = 262144 })
    Threats = @(); Detections = @(); Exclusions = @(); ExeCommand = '"%1" %*'; Existing = @(); Tasks = @()
    Files = @(@{ Path = $officeWord; Status = 'Valid' }, @{ Path = $zaloExe; Status = 'Valid' }, @{ Path = $zaloDll; Status = 'NotSigned' }, @{ Path = 'C:\Users\Admin\AppData\Local\Programs\Zalo\Zalo-26.9.10\resources\index.d.ts'; Status = 'UnknownError' }, @{ Path = 'C:\Users\Admin\AppData\Local\Programs\Zalo\Zalo-26.9.10\resources\package.json'; Status = 'UnknownError' })
}
$report = Get-AvDiagnostic -Roots $roots
$text = Format-AvDiagnostic $report
if (@($report.Products | Where-Object Enabled).Count -ne 0) { throw 'productState 393472 / 262144 must decode as real-time off.' }
if ((ConvertFrom-AvProductState 397312).Enabled -ne $true -or (ConvertFrom-AvProductState 397328).UpToDate -ne $false) { throw 'productState decoding is wrong.' }
if ($report.UnsignedDll -ne 1 -or @($report.UnsignedExe).Count -ne 0 -or @($report.Modified).Count -ne 0) { throw 'Signature classification is wrong.' }
if ($report.Scanned -ne 3 -or @($report.Untrusted).Count -ne 0) { throw 'Only .exe / .dll files may be scanned (no .ts / .json noise).' }
if ($report.Office[0].Edition -notmatch '2010') { throw 'Office 2010 not detected.' }
if ($text -match '\[NGHI' -or $text -match '\[KH') { throw 'Clean machine must not be reported as infected / cracked.' }
if ($text -notmatch 'Office 2010') { throw 'Missing Office edition.' }
if ($text -match 'N/A: Must') { throw 'Non-admin exclusion placeholder must be ignored.' }

# Case 2: Neshta-like infector.
$script:Case.ExeCommand = 'C:\Windows\svchost.com "%1" %*'
$script:Case.Existing = @('C:\Windows\svchost.com')
$script:Case.Files = @(@{ Path = $officeWord; Status = 'HashMismatch' })
$script:Case.Threats = @([pscustomobject]@{ ThreatID = 7; ThreatName = 'Virus:Win32/Neshta.A' })
$script:Case.Detections = @([pscustomobject]@{ ThreatID = 7; InitialDetectionTime = (Get-Date); Resources = @('file:_' + $officeWord) })
$report = Get-AvDiagnostic -Roots $roots
$text = Format-AvDiagnostic $report
if (@($report.Infector).Count -ne 2 -or @($report.Modified).Count -ne 1) { throw 'Infector markers missed.' }
if ($text -notmatch '\[NGHI' -or $text -notmatch 'Neshta' -or $text -notmatch [regex]::Escape($officeWord)) { throw 'Infector conclusion missing.' }
if ($text -match 'file:_') { throw 'Resource prefix not cleaned.' }

# Case 3: external activation tool + exclusion, flagged as HackTool.
$script:Case.ExeCommand = '"%1" %*'; $script:Case.Existing = @('C:\Windows\AutoKMS')
$script:Case.Files = @(@{ Path = $officeWord; Status = 'Valid' })
$script:Case.Threats = @([pscustomobject]@{ ThreatID = 9; ThreatName = 'HackTool:Win32/AutoKMS' })
$script:Case.Detections = @([pscustomobject]@{ ThreatID = 9; InitialDetectionTime = (Get-Date); Resources = @('file:_C:\Windows\AutoKMS\AutoKMS.exe') })
$script:Case.Tasks = @([pscustomobject]@{ TaskName = 'AutoKMS'; TaskPath = '\' })
$script:Case.Exclusions = @('C:\Windows\AutoKMS')
$report = Get-AvDiagnostic -Roots $roots
$text = Format-AvDiagnostic $report
if ($text -notmatch '\[KH' -or $text -match '\[NGHI') { throw 'Activation-tool conclusion wrong.' }
if (@($report.Activation).Count -lt 2 -or @($report.Exclusions).Count -ne 1) { throw 'Activation traces / exclusions missed.' }
if ($text -match 'KI.M TRA G') { throw 'A single tool folder exclusion is not a broad exclusion.' }
$script:Case.Exclusions = @('D:\')
$text = Format-AvDiagnostic (Get-AvDiagnostic -Roots $roots)
if ($text -notmatch [regex]::Escape('D:\') -or $text -notmatch '\[KI.M TRA G') { throw 'Whole-drive exclusion must be flagged as urgent.' }

# Case 4: old detections outside the window are ignored; ML-only name is "possible false positive".
$script:Case.Existing = @(); $script:Case.Tasks = @(); $script:Case.Exclusions = @()
$script:Case.Threats = @([pscustomobject]@{ ThreatID = 1; ThreatName = 'Trojan:Win32/Wacatac.C!ml' }, [pscustomobject]@{ ThreatID = 2; ThreatName = 'Virus:Win32/Sality' })
$script:Case.Detections = @(
    [pscustomobject]@{ ThreatID = 1; InitialDetectionTime = (Get-Date); Resources = @('file:_' + $zaloExe) },
    [pscustomobject]@{ ThreatID = 2; InitialDetectionTime = (Get-Date).AddDays(-200); Resources = @('file:_C:\old.exe') })
$report = Get-AvDiagnostic -Roots $roots
$text = Format-AvDiagnostic $report
if (@($report.Detections).Count -ne 1 -or $text -match 'Sality') { throw 'Old detections must be filtered by the time window.' }
if ($text -notmatch '\[C' -or $text -match '\[NGHI') { throw 'ML detection should be reported as possible false positive.' }

Write-Host 'PASS: AV diagnostics (5 cases) decode Security Center state, classify signatures, flag infector / activation tool / ML detections / whole-drive exclusions, ignore non-binary files, never mutate.'
