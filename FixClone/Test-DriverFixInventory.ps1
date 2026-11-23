# Exercise actual inventory/session/report code with a mocked CIM provider only.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DriverFix.Engine.ps1')
. (Join-Path $PSScriptRoot 'DriverFix.Report.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$pattern){$message='';try{& $action | Out-Null}catch{$message=$_.Exception.GetBaseException().Message};Assert ($message -match $pattern) "Expected $pattern; got $message"}
function RawDevice($id,$code){[pscustomobject]@{PNPDeviceID=$id;DeviceID=$id;Name=$id;ConfigManagerErrorCode=$code;HardwareID=@('PCI\VEN_1234&DEV_5678','PCI\VEN_1234&DEV_5678&SUBSYS_TEST');Service='';PNPClass='System'}}
$script:rows=@((RawDevice 'HEALTHY' 0),(RawDevice 'MISSING' 28),(RawDevice 'UNKNOWN' $null));$script:providerFailure=$false;$script:timeout=0
function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)
    switch($ClassName){
        Win32_PnPEntity {if($script:providerFailure){throw 'CIM provider unavailable'};$script:timeout=$OperationTimeoutSec;return $script:rows}
        Win32_ComputerSystem {[pscustomobject]@{Manufacturer='Generic OEM';Model='Any board';TotalPhysicalMemory=8GB}}
        Win32_BIOS {[pscustomobject]@{SMBIOSBIOSVersion='TEST';Manufacturer='TEST'}}
        Win32_BaseBoard {[pscustomobject]@{Manufacturer='Board';Product='Test'}}
        Win32_Processor {[pscustomobject]@{Name='CPU Test'}}
        Win32_OperatingSystem {[pscustomobject]@{Caption='Windows Test'}}
        default {throw ('Unexpected CIM query '+$ClassName)}
    }
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-inventory-'+[guid]::NewGuid().ToString('N'))
try{
    foreach($code in @($null,'bad',[uint32]::MaxValue,-2,'')){
        $d=ConvertTo-DriverFixDevice (RawDevice 'INVALID' $code)
        Assert ($d.ErrorCode -eq -1 -and $d.ErrorCodeText -eq '?' -and $d.Description -match 'Device Manager') 'Missing/invalid device status is unknown, never coerced to healthy Code 0'
    }
    $snapshot=Get-DriverFixSnapshot
    Assert ($snapshot.All.Count -eq 3 -and $snapshot.Problems.Count -eq 2 -and $script:timeout -eq 30) 'Read inventory keeps healthy/problem/unknown devices and uses bounded CIM operation'
    Assert ($snapshot.All[1].HardwareIds.Count -eq 2 -and $snapshot.Source -ceq 'CIM Win32_PnPEntity') 'Full Hardware IDs and actual inventory source are retained'
    $summary=Get-DriverFixScanSummary $snapshot
    Assert ($summary.Total -eq 3 -and $summary.Healthy -eq 1 -and $summary.Problems -eq 1 -and $summary.Unknown -eq 1 -and $summary.Kind -eq 'Attention') 'Summary separates total, healthy, error and unknown counts'
    Assert (@(Get-DriverFixVisibleDevices $snapshot $false).Count -eq 2 -and @(Get-DriverFixVisibleDevices $snapshot $true).Count -eq 3) 'Read-only all-devices filter reveals healthy devices without changing inventory'
    $session=New-DriverFixSession $temp
    Assert ($session.Before.All.Count -eq 3 -and $session.Current.Problems.Count -eq 2 -and -not $session.Profile) 'Actual generic session initializes through the real inventory path'
    $log=Get-Content -LiteralPath $session.LogPath | ForEach-Object {$_|ConvertFrom-Json}
    Assert (@($log)[0].event -eq 'session-start' -and @($log)[-1].data.summary.Total -eq 3) 'Session log begins before inventory and records actual read totals'
    $report=Export-DriverFixReport $session
    $html=[IO.File]::ReadAllText($report)
    Assert (([Net.WebUtility]::HtmlDecode($html)).Contains($summary.CountsText) -and ([Net.WebUtility]::HtmlDecode($html)).Contains('<td>? —')) 'HTML includes scan coverage and does not label unknown status as Code 0'
    $unknown=ConvertTo-DriverFixDevice (RawDevice 'MISSING' $null)
    $delta=Compare-DriverFixSnapshot $snapshot ([pscustomobject]@{All=@($unknown);Problems=@($unknown)})
    Assert ($delta.Resolved.Count -eq 0) 'Unreadable status is never counted as a repaired device'
    $knownNow=ConvertTo-DriverFixDevice (RawDevice 'MISSING' 0)
    $uncertainBefore=[pscustomobject]@{All=@($unknown);Problems=@($unknown)}
    $delta=Compare-DriverFixSnapshot $uncertainBefore ([pscustomobject]@{All=@($knownNow);Problems=@()})
    Assert ($delta.Resolved.Count -eq 0) 'Reading Code 0 after an unknown prior status is not called repairing a known error'
    $script:rows=@((RawDevice 'ONE' 0),(RawDevice 'TWO' 0))
    $healthy=Get-DriverFixScanSummary (Get-DriverFixSnapshot)
    Assert ($healthy.Total -eq 2 -and $healthy.Healthy -eq 2 -and $healthy.Problems -eq 0 -and $healthy.Unknown -eq 0 -and $healthy.Message -match 'Hiện tất cả thiết bị') 'Healthy scan explicitly reports nonzero read coverage and how to view it'
    $script:rows=@();Throws {Get-DriverFixSnapshot} 'Windows không trả về thiết bị PnP'
    $empty=Get-DriverFixScanSummary ([pscustomobject]@{All=@();Problems=@()})
    Assert ($empty.Total -eq 0 -and $empty.Kind -eq 'Error' -and $empty.Message -match 'Không thể kết luận') 'Empty data cannot be described as a successful zero-error scan'
    $before=$session.Current
    Throws {Update-DriverFixSession $session} 'Windows không trả về thiết bị PnP'
    Assert ([object]::ReferenceEquals($session.Current,$before)) 'Failed refresh preserves previous inventory rather than replacing it with zero devices'
    $failedRoot=Join-Path $temp 'failed-init'
    Throws {New-DriverFixSession $failedRoot} 'Nhật ký:'
    $failedLog=@(Get-ChildItem -LiteralPath (Join-Path $failedRoot 'Sessions') -Recurse -Filter events.jsonl)[0]
    $entries=@(Get-Content -LiteralPath $failedLog.FullName | ForEach-Object {$_|ConvertFrom-Json})
    Assert ($entries[0].event -eq 'session-start' -and $entries[-1].event -eq 'session-init-failed') 'Initialization failure has an inspectable log even without a returned UI session'
    $script:providerFailure=$true;Throws {Get-DriverFixSnapshot} 'CIM provider unavailable'
    Assert ($session.Actions.Count -eq 0) 'Scanning, filtering and diagnostic failure run no installation/disable actions'
    Write-Host "PASS: $checks inventory assertions; provider errors, empty reads, unknown statuses, actual session init, totals and HTML. No hardware changes."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
