$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AV.Repair.ps1')
$checks = 0
function Assert($condition, $message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }

# Defender is simulated; files are real (temp folder) so the quarantine move is exercised for real.
$script:calls = New-Object System.Collections.Generic.List[string]
$script:sig = '1.400.100.0'
$script:allowIds = @(2147909550); $script:exclusions = @('D:\'); $script:load = 1
$script:newDetections = @()
function Get-MpComputerStatus { [CmdletBinding()] param() [pscustomobject]@{ AntivirusSignatureVersion = $script:sig } }
function Update-MpSignature { [CmdletBinding()] param() $script:calls.Add('Update'); $script:sig = '1.400.200.0' }
function Get-MpPreference { [CmdletBinding()] param() [pscustomobject]@{ ThreatIDDefaultAction_Ids = $script:allowIds; ExclusionPath = $script:exclusions } }
function Remove-MpPreference { [CmdletBinding()] param($ThreatIDDefaultAction_Ids, $ExclusionPath)
    if ($ThreatIDDefaultAction_Ids) { $script:calls.Add('RemoveAllowed:' + $ThreatIDDefaultAction_Ids); $script:allowIds = @($script:allowIds | Where-Object { $_ -ne $ThreatIDDefaultAction_Ids }) }
    if ($ExclusionPath) { $script:calls.Add('RemoveExclusion:' + $ExclusionPath); $script:exclusions = @($script:exclusions | Where-Object { $_ -ne $ExclusionPath }) } }
function Start-MpScan { [CmdletBinding()] param($ScanType, $ScanPath) $script:calls.Add('Scan:' + $ScanType + ':' + $ScanPath) }
function Get-MpThreatDetection { [CmdletBinding()] param() $script:newDetections }
function Start-MpWDOScan { [CmdletBinding()] param() $script:calls.Add('Offline') }
$script:regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows')
function Get-ItemProperty { [CmdletBinding()] param($LiteralPath) if ($LiteralPath -in $script:regPaths) { [pscustomobject]@{ AppInit_DLLs = 'C:\PROGRA~2\COMMON~1\System\symsrv.dll'; LoadAppInit_DLLs = $script:load } } else { throw 'unexpected registry read' } }
function Set-ItemProperty { [CmdletBinding()] param($LiteralPath, $Name, $Value, $Type) if ($Name -ne 'LoadAppInit_DLLs' -or $Value -ne 0) { throw 'Only LoadAppInit_DLLs = 0 may be written' }; $script:calls.Add('AppInit:' + $LiteralPath); $script:load = 0 }
foreach ($blocked in 'Remove-Item','Remove-MpThreat','Set-MpPreference','Add-MpPreference','Restart-Computer','Stop-Service') {
    Set-Item -Path ('Function:' + $blocked) -Value ([scriptblock]::Create("throw 'Repair must never call $blocked'"))
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-avrepair-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $source = Join-Path $temp 'kho'; New-Item -ItemType Directory -Path $source | Out-Null
    $a = Join-Path $source 'EPPlus_woR_3830_22.exe'; [IO.File]::WriteAllText($a, 'infected-a')
    $b = Join-Path $source 'AdjProg.exe'; [IO.File]::WriteAllText($b, 'infected-b')
    $missing = Join-Path $source 'already-cleaned.exe'
    $vault = Join-Path $temp 'vault'; $backups = Join-Path $temp 'backups'

    # Plan from a report like the KY-THUAT machine.
    $report = [pscustomobject]@{
        Defender = [pscustomobject]@{ Mode = 'Normal' }
        AllowedIds = @('2147909550'); Exclusions = @('D:\', 'D:\Projects\Build')
        Infector = @('AppInit_DLLs đang nạp: C:\PROGRA~2\COMMON~1\System\symsrv.dll')
        Detections = @([pscustomobject]@{ Threat = 'Virus:Win32/Floxif.H'; Files = @([pscustomobject]@{ Path = $a; Present = $true }, [pscustomobject]@{ Path = $missing; Present = $false }) },
                       [pscustomobject]@{ Threat = 'Trojan:Win32/Malgent!pz'; Files = @([pscustomobject]@{ Path = $b; Present = $true }) })
        Drives = @([pscustomobject]@{ Drive = 'C:' }, [pscustomobject]@{ Drive = 'G:' })
    }
    $plan = @(Get-AvRepairPlan $report)
    $ids = @($plan | ForEach-Object Id)
    Assert ($ids[0] -eq 'UpdateSignatures' -and $ids[-1] -eq 'OfflineScan') 'Plan starts with signature update and ends with the rebooting offline scan'
    Assert (@($plan | Where-Object Id -eq 'RemoveExclusion').Count -eq 1 -and ($plan | Where-Object Id -eq 'RemoveExclusion').Data -eq 'D:\') 'Only broad exclusions are offered for removal'
    Assert (-not ($plan | Where-Object Id -eq 'OfflineScan').Recommended -and ($plan | Where-Object Id -eq 'OfflineScan').Danger) 'Offline scan is never pre-selected and is marked dangerous'
    Assert (-not ($plan | Where-Object Id -eq 'FullScan').Recommended) 'Full scan is not pre-selected'
    Assert (@(($plan | Where-Object Id -eq 'Quarantine').Data).Count -eq 2) 'Quarantine covers only files still present'
    Assert (($plan | Where-Object Id -eq 'CustomScan').Data -eq 'G:\') 'Each non-system drive with detections gets its own scan'
    $passivePlan = @(Get-AvRepairPlan ([pscustomobject]@{ Defender = [pscustomobject]@{ Mode = 'Passive Mode' }; AllowedIds = @(); Exclusions = @(); Infector = @(); Detections = @(); Drives = @() }))
    Assert (-not @($passivePlan | Where-Object Recommended).Count -and ($passivePlan[0].Detail -match 'Passive')) 'Passive Defender: nothing pre-selected, reason shown'

    # Run everything except the offline scan, in a deliberately shuffled order.
    $progress = [hashtable]::Synchronized(@{ Lines = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)) })
    $log = Join-Path $temp 'repair.log'
    $selected = @($plan | Where-Object { $_.Id -notin 'OfflineScan','FullScan','CustomScan' })
    [array]::Reverse($selected)
    $results = @(Invoke-AvRepair $selected -Progress $progress -LogPath $log -QuarantineRoot $vault -BackupRoot $backups)
    Assert (@($results | Where-Object { -not $_.Ok }).Count -eq 0) ('All selected actions succeed: ' + (($results | Where-Object { -not $_.Ok } | ForEach-Object { $_.Title + ' ' + $_.Message }) -join ' | '))
    Assert ($script:calls[0] -eq 'Update' -and $script:calls[-1] -like 'Scan:QuickScan*') 'Execution order is fixed regardless of selection order'
    Assert ($script:allowIds.Count -eq 0 -and $script:exclusions.Count -eq 0 -and $script:load -eq 0) 'Allow list, broad exclusion and AppInit are verified as removed'
    Assert ((-not (Test-Path -LiteralPath $a)) -and (-not (Test-Path -LiteralPath $b))) 'Leftover files left their original folder'
    $moved = @(Get-ChildItem -LiteralPath $vault -Recurse -File)
    Assert (@($moved | Where-Object Name -like '*.virus').Count -eq 2) 'Files were renamed *.virus in the vault, not deleted'
    $manifest = Get-Content -LiteralPath (@($moved | Where-Object Name -eq 'DanhSach.tsv')[0].FullName) -Raw
    Assert ($manifest -match [regex]::Escape($a) -and $manifest -match "`t[0-9A-F]{64}") 'Manifest lists original path and SHA256'
    $backup = @(Get-ChildItem -LiteralPath $backups -Filter 'AppInit_*.json')
    Assert ($backup.Count -eq 1 -and (Get-Content -LiteralPath $backup[0].FullName -Raw) -match 'symsrv') 'AppInit values were backed up before the change'
    Assert ($progress.Percent -eq 100 -and $progress.Lines.Count -eq $selected.Count) 'Progress reports every action'
    Assert ((Get-Content -LiteralPath $log -Raw) -match 'XONG') 'Log records each result'
    Assert (($results | Where-Object Title -like 'Cập nhật*').Message -match '1\.400\.200\.0') 'Signature update is verified by version'

    # Edge cases: name collision, unplugged drive, scan with new detections, offline scan.
    [IO.File]::WriteAllText($a, 'again');
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'Quarantine'; Title = 'Q'; Data = @($a) }) $vault $backups
    $r2 = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'Quarantine'; Title = 'Q'; Data = @($a, $missing) }) $vault $backups
    Assert ($r.Ok -and $r2.Ok -and $r2.Message -match 'không còn') 'Missing files are reported, not treated as failures'
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'CustomScan'; Title = 'Quét G:'; Data = (Join-Path $temp 'no-such-drive\') }) $vault $backups
    Assert (-not $r.Ok -and $r.Message -match 'không có trên máy') 'Scanning an unplugged drive explains the failure'
    $script:newDetections = @([pscustomobject]@{ InitialDetectionTime = (Get-Date).AddMinutes(1) })
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'QuickScan'; Title = 'Quét nhanh' }) $vault $backups
    Assert ($r.Ok -and $r.Message -match 'Phát hiện mới: 1') 'New detections after a scan are counted'
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'OfflineScan'; Title = 'Offline' }) $vault $backups
    Assert ($r.Ok -and $script:calls[-1] -eq 'Offline') 'Offline scan is only requested when selected'
    # Another Defender scan is running (the manual full scan started earlier): wait, then run.
    $script:polls = 0; $script:sleeps = 0
    function Get-MpComputerStatus { [CmdletBinding()] param()
        $script:polls++
        if ($script:sleeps -lt 2) { [pscustomobject]@{ AntivirusSignatureVersion = $script:sig; FullScanStartTime = (Get-Date).AddMinutes(-80); FullScanEndTime = (Get-Date).AddDays(-3) } }
        else { [pscustomobject]@{ AntivirusSignatureVersion = $script:sig; FullScanStartTime = (Get-Date).AddMinutes(-80); FullScanEndTime = (Get-Date) } } }
    function Start-Sleep { [CmdletBinding()] param($Seconds) $script:sleeps++ }
    $progressBusy = [hashtable]::Synchronized(@{ Lines = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)) })
    $before = $script:calls.Count
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'QuickScan'; Title = 'Quét nhanh' }) $vault $backups $progressBusy 600
    Assert ($r.Ok -and $script:sleeps -eq 2 -and $script:calls.Count -eq $before + 1) 'A running full scan is waited for, then the quick scan starts'
    Assert ($progressBusy.Current -match 'chờ quét toàn bộ') 'Progress says which scan is being waited for'
    $script:sleeps = -1000
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'CustomScan'; Title = 'Quét ổ'; Data = $temp }) $vault $backups $null 0
    Assert (-not $r.Ok -and $r.Message -match 'Quét toàn bộ của Defender \(bắt đầu' -and $r.Message -match 'chạy lại mục này') 'Timeout explains which scan is still running and what to do'
    function Get-MpComputerStatus { [CmdletBinding()] param() [pscustomobject]@{ AntivirusSignatureVersion = $script:sig } }
    $script:busyOnce = $true
    function Start-MpScan { [CmdletBinding()] param($ScanType, $ScanPath) if ($script:busyOnce) { $script:busyOnce = $false; throw 'A scan is already in progress on this device.' }; $script:calls.Add('Scan:' + $ScanType) }
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'QuickScan'; Title = 'Quét nhanh' }) $vault $backups $null 600
    Assert ($r.Ok -and $script:calls[-1] -eq 'Scan:QuickScan') 'A busy error without timestamps (scheduled scan) is retried'
    function Start-MpScan { [CmdletBinding()] param($ScanType, $ScanPath) throw 'Access denied' }
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'QuickScan'; Title = 'Quét nhanh' }) $vault $backups $null 600
    Assert (-not $r.Ok -and $r.Message -eq 'Access denied') 'Other scan errors are reported immediately, not retried'
    function Update-MpSignature { [CmdletBinding()] param() throw 'Không có mạng' }
    $r = Invoke-AvRepairItem ([pscustomobject]@{ Id = 'UpdateSignatures'; Title = 'Cập nhật' }) $vault $backups
    Assert (-not $r.Ok -and $r.Message -match 'Không có mạng') 'A failing action returns its error instead of stopping the run'
}
finally { [IO.Directory]::Delete($temp, $true) }
Write-Host "PASS: $checks AV repair assertions; real quarantine moves with manifest/SHA256, verified Defender changes, fixed order, no deletion."
