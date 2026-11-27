# Real logs and mocked spooler/registry/Settings; no user preferences are changed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Defaults.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m){$failed=$false;try{& $action | Out-Null}catch{$failed=$true};Assert $failed $m}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-defaults-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
try{
    $log=Join-Path $temp 'actions.jsonl'
    $script:queues=@([pscustomobject]@{Name='Office [A]';DriverName='Driver';PortName='USB001'},[pscustomobject]@{Name='Other';DriverName='Driver';PortName='IP'})
    $script:paper='Letter';$script:default='Other';$script:admin=$true;$script:paperWrites=0;$script:defaultWrites=0;$script:modeWrites=0
    $script:mode=[pscustomobject]@{Present=$false;Value=$null;Kind=''}
    $script:paperAccepted=$true;$script:defaultFails=$false;$script:configFails=$false;$script:queueFails=$false
    function Assert-DeployPrinterAdmin {if(-not $script:admin){throw 'admin required'}}
    function Get-Printer {param($ErrorAction)if($script:queueFails){throw 'spooler unavailable'};$script:queues}
    function Get-PrintConfiguration {param($PrinterName,$ErrorAction)if($script:configFails){throw 'driver unsupported'};Assert ($PrinterName -ceq 'Office [A]') 'Configuration targets exact queue, including wildcard characters';[pscustomobject]@{PaperSize=$script:paper}}
    function Set-PrintConfiguration {param($PrinterName,$PaperSize,$ErrorAction)$script:paperWrites++;Assert ($PrinterName -ceq 'Office [A]' -and $PaperSize -ceq 'A4') 'Only chosen printer and paper size are changed';if($script:paperAccepted){$script:paper=$PaperSize}}
    function Get-DeployDefaultPrinter {$script:default}
    function Set-DeployDefaultPrinterNative($Name){$script:defaultWrites++;if($script:defaultFails){throw 'spooler refused default'};$script:default=$Name}
    function Get-DeployPrinterManagement {$script:mode.PSObject.Copy()}
    function Set-DeployPrinterManagement($State){$script:modeWrites++;$script:mode=$State.PSObject.Copy()}
    $script:wmi=@();$script:portInfo=@()
    function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)Assert ($ClassName -ceq 'Win32_Printer') 'Offline detection reads printer status only';$script:wmi}
    function Get-PrinterPort {param($ErrorAction)$script:portInfo}
    $script:pnp=@();$script:portMap=@{}
    function Get-DeployPnpDevices {$script:pnp}
    function Get-DeployDevicePortName([string]$InstanceId){[string]$script:portMap[$InstanceId]}
    $r=Set-DeployPrinterDefaults 'Office [A]' $true $true $log
    Assert ($r.Kind -eq 'Success' -and $script:paper -eq 'A4' -and $script:default -ceq 'Office [A]' -and $script:mode.Value -eq 1) 'A4 and current-user default are read back before success'
    $entries=@(Get-Content $log | ForEach-Object {$_ | ConvertFrom-Json})
    Assert (@($entries | Where-Object Event -eq 'paper-before').Count -eq 1 -and @($entries | Where-Object Event -eq 'default-printer-after').Count -eq 1) 'Persistent log includes original and verified states'
    $writes=$script:paperWrites+$script:defaultWrites
    $r=Set-DeployPrinterDefaults 'Office [A]' $true $true $log
    Assert ($r.Kind -eq 'Success' -and $script:paperWrites+$script:defaultWrites -eq $writes) 'Applying same paper/default avoids redundant spooler changes'
    $script:paper='Letter';$script:paperAccepted=$false;$script:default='Other'
    $r=Set-DeployPrinterDefaults 'Office [A]' $true $true $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match 'Driver' -and $script:default -ceq 'Office [A]') 'Rejected A4 is reported separately from successful default printer'
    $script:paperAccepted=$true;$script:defaultFails=$true;$script:default='Other';$script:mode=[pscustomobject]@{Present=$false;Value=$null;Kind=''}
    $r=Set-DeployPrinterDefaults 'Office [A]' $false $true $log
    Assert ($r.Kind -eq 'Error' -and -not $script:mode.Present -and $script:default -eq 'Other') 'Failed default restores previously absent auto-management preference'
    $script:mode=[pscustomobject]@{Present=$true;Value=0;Kind='DWord'}
    $r=Set-DeployPrinterDefaults 'Office [A]' $false $true $log
    Assert ($r.Kind -eq 'Error' -and $script:mode.Present -and $script:mode.Value -eq 0) 'Failed default restores existing automatic management'
    $script:defaultFails=$false;$script:mode=[pscustomobject]@{Present=$true;Value='custom';Kind='String'};$before=$script:modeWrites
    $r=Set-DeployPrinterDefaults 'Office [A]' $false $true $log
    Assert ($r.Kind -eq 'Error' -and $script:modeWrites -eq $before) 'Unexpected preference kind is preserved'
    $script:admin=$false;$before=$script:paperWrites+$script:defaultWrites
    Throws {Set-DeployPrinterDefaults 'Office [A]' $true $true $log} 'Admin is required before printer mutation'
    Assert ($script:paperWrites+$script:defaultWrites -eq $before) 'No non-admin spooler changes'
    $script:admin=$true
    Throws {Set-DeployPrinterDefaults 'Missing' $true $true $log} 'Stale or missing queue is rejected'
    Throws {Set-DeployPrinterDefaults 'Office [A]' $false $false $log} 'Empty operation is rejected'
    $script:configFails=$true
    $r=Set-DeployPrinterDefaults 'Office [A]' $true $false $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'unsupported') 'Unsupported drivers do not produce a false A4 success'
    $script:configFails=$false
    $script:apps=@([pscustomobject]@{Name='Browser & Test?';Scope='Machine';Display='Browser Test';Http='BrowserHTTP';Https='BrowserHTTPS';Pdf='BrowserPDF'},[pscustomobject]@{Name='PDF User';Scope='User';Display='PDF Test';Http='';Https='';Pdf='PDF.Reader'})
    $script:opened=@()
    function Get-DeployRegisteredDefaultApps {$script:apps}
    function Start-Process {param($FilePath,$ErrorAction)$script:opened+=$FilePath}
    $r=Open-DeployDefaultAppSettings $script:apps[0] Browser $log
    Assert ($r.Kind -eq 'Attention' -and $script:opened[-1] -ceq 'ms-settings:defaultapps?registeredAppMachine=Browser%20%26%20Test%3F') 'Browser settings deep link encodes registered name and waits for Windows confirmation'
    $r=Open-DeployDefaultAppSettings $script:apps[1] Pdf $log
    Assert ($script:opened[-1] -ceq 'ms-settings:defaultapps?registeredAppUser=PDF%20User') 'Per-user PDF registration opens corresponding user settings'
    $before=$script:opened.Count
    Throws {Open-DeployDefaultAppSettings ([pscustomobject]@{Name='arbitrary://command';Scope='Machine'}) Pdf $log} 'Unregistered app object cannot open an arbitrary URI'
    Throws {Open-DeployDefaultAppSettings $script:apps[1] Browser $log} 'PDF-only registration cannot be chosen as browser'
    Assert ($script:opened.Count -eq $before) 'Rejected registration launches nothing'
    function Get-DeployCurrentAssociation($Association){switch($Association){'http'{'BrowserHTTP'}'https'{'DifferentHTTPS'}'.pdf'{'PDF.Reader'}}}
    $snapshot=Get-DeployDefaultsSnapshot
    Assert (-not (Test-DeployDefaultAppChoice $script:apps[0] Browser $snapshot)) 'Matching HTTP alone is not enough to verify a browser'
    $snapshot.Associations['https'].ProgId='BrowserHTTPS'
    Assert (Test-DeployDefaultAppChoice $script:apps[0] Browser $snapshot) 'Both protocol associations verify browser selection'
    $snapshot.Associations['https'].ProgId='browserhttps'
    Assert (Test-DeployDefaultAppChoice $script:apps[0] Browser $snapshot) 'ProgId comparison follows Windows case-insensitive registration semantics'
    Assert (Test-DeployDefaultAppChoice $script:apps[1] Pdf $snapshot) 'PDF verification checks .pdf association independently'
    $snapshot.Associations['.pdf'].Readable=$false
    Assert (-not (Test-DeployDefaultAppChoice $script:apps[1] Pdf $snapshot)) 'Unreadable association is not treated as configured'
    Assert ((Get-DeployAssociationLabel $snapshot.Associations['http'] $snapshot.Apps Http) -ceq 'Browser Test') 'Registered ProgId is displayed with its app name'
    $script:queueFails=$true
    function Get-DeployCurrentAssociation($Association){if($Association -eq '.pdf'){throw 'association unavailable'};'BrowserHTTP'}
    $snapshot=Get-DeployDefaultsSnapshot
    Assert ($snapshot.PrinterError -and @($snapshot.Apps).Count -eq 2 -and -not $snapshot.Associations['.pdf'].Readable -and $snapshot.Associations['http'].Readable) 'Spooler/association failures retain independently readable settings'
    function Start-Process {param($FilePath,$ErrorAction)$script:opened+=$FilePath;if($FilePath -ne 'ms-settings:defaultapps'){throw 'deep link unavailable'}}
    $null=Open-DeployDefaultAppSettings $script:apps[0] Browser $log
    Assert ($script:opened[-1] -ceq 'ms-settings:defaultapps') 'Unsupported app deep link falls back to Windows defaults settings'
    # Offline printer cleanup = Remove device: queue plus disconnected device nodes; drivers are never touched.
    $script:queueFails=$false;$script:admin=$true;$script:default='Default USB'
    $script:DeployPrinterWaitSeconds=0;$script:DeployPendingWaitSeconds=0
    function New-TestQueue($Name,$Port,$Status='Normal',$Type='Local',$Jobs=0,$Shared=$false){[pscustomobject]@{Name=$Name;DriverName=('Driver '+$Name);PortName=$Port;PrinterStatus=$Status;Type=$Type;JobCount=$Jobs;Shared=$Shared}}
    $script:queues=@(
        (New-TestQueue 'Canon LBP2900 (Copy 1)' 'USB002'),
        (New-TestQueue 'Canon [Old]' 'USB003' 'Offline' 'Local' 2),
        (New-TestQueue 'Canon MF240' 'USB001'),
        (New-TestQueue 'Default USB' 'USB004' 'Offline'),
        (New-TestQueue 'Shared USB' 'USB005' 'Offline' 'Local' 0 $true),
        (New-TestQueue 'TOSHIBA 457' 'IP_192.168.1.45' 'Offline'),
        (New-TestQueue 'Copier Custom' 'TOSHIBA_PORT' 'Offline'),
        (New-TestQueue 'WSD Printer' 'WSD-1234-abcd'),
        (New-TestQueue '\\server\Office' 'LPT1:' 'Offline' 'Connection'),
        (New-TestQueue 'Microsoft Print to PDF' 'PORTPROMPT:' 'Offline'),
        (New-TestQueue 'Fax' 'SHRFAX:' 'Offline'),
        (New-TestQueue 'Custom Port' 'MYPORT' 'Offline'),
        (New-TestQueue 'Port Reuse' 'USB012'))
    $script:wmi=@([pscustomobject]@{Name='Canon LBP2900 (Copy 1)';WorkOffline=$true;PrinterStatus=3},[pscustomobject]@{Name='Canon MF240';WorkOffline=$false;PrinterStatus=3},[pscustomobject]@{Name='WSD Printer';WorkOffline=$false;PrinterStatus=7},[pscustomobject]@{Name='Microsoft Print to PDF';WorkOffline=$true;PrinterStatus=7})
    $script:portInfo=@([pscustomobject]@{Name='TOSHIBA_PORT';PrinterHostAddress='192.168.1.50'},[pscustomobject]@{Name='MYPORT';PrinterHostAddress=''})
    $pc='00000000-0000-0000-ffff-ffffffffffff'
    function New-TestNode($Id,$Class,$Name,$Present,$Container,$Parent=''){[pscustomobject]@{InstanceId=$Id;Class=$Class;FriendlyName=$Name;Present=$Present;ContainerId=$Container;Parent=$Parent}}
    $script:pnp=@(
        (New-TestNode 'USB\ROOT_HUB30\1' 'USB' 'Root hub' $true $pc),
        (New-TestNode 'SWD\PRINTENUM\{A}' 'PrintQueue' 'Canon LBP2900 (Copy 1)' $true '{C1}'),
        (New-TestNode 'USBPRINT\CANON\A' 'Printer' 'Canon LBP2900' $false '{C1}' 'USB\VID_04A9\A'),
        (New-TestNode 'USB\VID_04A9\A' 'USB' 'USB Printing Support' $false '{C1}' 'USB\ROOT_HUB30\1'),
        (New-TestNode 'SWD\PRINTENUM\{B}' 'PrintQueue' 'Canon [Old]' $true 'c2'),
        (New-TestNode 'USBPRINT\CANON\B' 'Printer' 'Canon LBP2900' $false 'c2' 'USB\VID_04A9\B'),
        (New-TestNode 'USB\VID_04A9\B' 'USB' 'USB Printing Support' $false 'c2' 'USB\ROOT_HUB30\1'),
        (New-TestNode 'SWD\PRINTENUM\{C}' 'PrintQueue' 'Canon MF240' $true 'c3'),
        (New-TestNode 'USBPRINT\CANON\C' 'Printer' 'Canon MF240' $true 'c3' 'USB\VID_04A9\C'),
        (New-TestNode 'USB\VID_04A9\C' 'USB' 'USB Composite' $true 'c3' 'USB\ROOT_HUB30\1'),
        (New-TestNode 'SWD\PRINTENUM\{D}' 'PrintQueue' 'Default USB' $true 'c4'),
        (New-TestNode 'USBPRINT\GENERIC\D' 'Printer' 'Generic' $false 'c4'),
        (New-TestNode 'SWD\PRINTENUM\{F}' 'PrintQueue' 'TOSHIBA 457' $true $pc),
        (New-TestNode 'STORAGE\VOLUME\OLD' 'Volume' 'Old disk' $false $pc),
        (New-TestNode 'SWD\PRINTENUM\{I}' 'PrintQueue' '\\server\Office' $true 'c13'),
        (New-TestNode 'WSDPRINT\FAILNODE' 'Printer' 'Office MFP' $false 'c13'),
        (New-TestNode 'SWD\PRINTENUM\{G9}' 'PrintQueue' 'Canon LBP2900 (Copy 7)' $false 'c9'),
        (New-TestNode 'USBPRINT\CANON\G9' 'Printer' 'Canon LBP2900' $false 'c9' 'USB\VID_04A9\G9'),
        (New-TestNode 'USB\VID_04A9\G9' 'USB' 'USB Printing Support' $false 'c9' 'USB\ROOT_HUB30\1'),
        (New-TestNode 'USBPRINT\CANON\H10' 'Printer' 'Canon LBP2900' $false 'c10' 'USB\VID_04A9\H10'),
        (New-TestNode 'USB\VID_04A9\H10' 'USB' 'USB Composite' $true 'c10'),
        (New-TestNode 'SWD\PRINTENUM\{OLDFAX}' 'PrintQueue' 'Old Fax Queue' $false $pc),
        (New-TestNode 'USBPRINT\CANON\R12' 'Printer' 'Old on reused port' $false 'c12'))
    $script:portMap=@{'USBPRINT\CANON\A'='USB002';'USBPRINT\CANON\B'='USB003';'USBPRINT\GENERIC\D'='USB004';'USBPRINT\CANON\G9'='USB009';'USBPRINT\CANON\H10'='USB010';'USBPRINT\CANON\R12'='USB012'}
    $scan=Get-DeployPrinterOfflineScan
    $queueRows=@($scan.Rows | Where-Object {$_.Kind -ne 'Device'});$deviceRows=@($scan.Rows | Where-Object {$_.Kind -eq 'Device'})
    $names=@($queueRows | ForEach-Object {$_.Name})
    Assert ($names -ccontains 'Canon LBP2900 (Copy 1)' -and $names -ccontains 'Canon [Old]') 'Unplugged USB queues are found from WorkOffline or the spooler Offline status'
    Assert (-not ($names -ccontains 'Canon MF240') -and -not ($names -ccontains 'Port Reuse')) 'Connected USB printers are never listed'
    Assert (-not ($names -ccontains 'Microsoft Print to PDF') -and -not ($names -ccontains 'Fax') -and -not ($names -ccontains 'Custom Port')) 'Virtual and unknown ports are never listed, even when reported offline'
    Assert ($names -ccontains 'TOSHIBA 457' -and $names -ccontains 'Copier Custom' -and $names -ccontains 'WSD Printer' -and $names -ccontains '\\server\Office' -and $names.Count -eq 8) 'TCP/IP, custom TCP/IP, WSD and shared connections are recognised as network printers'
    Assert ($deviceRows.Count -eq 2 -and $deviceRows[0].Name -ceq 'Canon LBP2900 (Copy 7)' -and $deviceRows[0].Key -ceq 'device:c9' -and $deviceRows[1].Key -ceq 'node:SWD\PRINTENUM\{OLDFAX}' -and $deviceRows[0].Selected) 'Leftover printer devices without a queue are listed by their Devices and Printers name'
    Assert (-not @($deviceRows | Where-Object {$_.Detail -match 'Old disk|Old on reused port'}).Count) 'Containers with a connected node, a port still used by a queue or non-printer nodes are not offered'
    $byName=@{};foreach($row in $queueRows){$byName[$row.Name]=$row}
    Assert ($byName['Canon LBP2900 (Copy 1)'].Selected -and $byName['Canon [Old]'].Selected -and $byName['Canon [Old]'].Key -ceq 'Canon [Old]') 'Offline USB queues are preselected and keyed by their exact name'
    Assert (-not $byName['Default USB'].Selected -and -not $byName['Shared USB'].Selected -and -not $byName['TOSHIBA 457'].Selected -and -not $byName['\\server\Office'].Selected) 'Default, shared and network printers need an explicit tick'
    Assert ($byName['Canon [Old]'].Detail -match '2 lệnh in' -and $byName['Default USB'].Detail -match 'mặc định' -and $byName['TOSHIBA 457'].Kind -ceq 'Network') 'Row details flag pending jobs, default printer and connection kind'
    Assert ($scan.Rows[0].Kind -ceq 'USB' -and $scan.Rows[7].Kind -ceq 'Network' -and $scan.Rows[-1].Kind -ceq 'Device') 'USB leftovers first, then network printers, then leftover devices'
    $map=@($scan.Devices)
    Assert ((Get-DeployQueueContainer $byName['Canon LBP2900 (Copy 1)'] $map) -ceq 'c1' -and (Get-DeployQueueContainer ([pscustomobject]@{Name='No node';PortName='USB003'}) $map) -ceq 'c2') 'Queue container comes from its print-queue node, else from the USBPRINT port name; braces and case are normalised'
    $plan=Get-DeployContainerRemovalPlan 'c1' $map @() @()
    $ids=@($plan.Nodes | ForEach-Object {$_.InstanceId})
    Assert ($ids.Count -eq 3 -and [array]::IndexOf($ids,'USBPRINT\CANON\A') -lt [array]::IndexOf($ids,'USB\VID_04A9\A')) 'Device plan covers the whole container, children before parents'
    Assert ((Get-DeployContainerRemovalPlan 'c10' $map @() @()).Reason -ceq 'connected' -and (Get-DeployContainerRemovalPlan 'c3' $map @() @()).Reason -ceq 'connected') 'A container with any connected node is never removed'
    Assert ((Get-DeployContainerRemovalPlan $pc $map @() @()).Reason -ceq 'no-device' -and (Get-DeployContainerRemovalPlan '' $map @() @()).Reason -ceq 'no-device') "The computer's own container is never removed"
    Assert ((Get-DeployContainerRemovalPlan 'c12' $map @() @('USB012')).Reason -ceq 'shared' -and (Get-DeployContainerRemovalPlan 'c1' $map @('Canon LBP2900 (Copy 1)') @()).Reason -ceq 'shared') 'A device still used by a kept queue or port is kept'
    $prompt=Get-DeployOfflineRemovalPrompt @($byName['Canon [Old]'],$byName['Default USB'],$byName['TOSHIBA 457'],$deviceRows[0]) $true
    Assert ($prompt -match 'Gỡ 4 máy in' -and $prompt.Contains('Canon [Old]') -and $prompt -match 'thiết bị còn sót' -and $prompt -match 'Remove device' -and $prompt -match 'Driver vẫn giữ' -and $prompt -match 'máy in mặc định khác' -and $prompt -match 'Còn 2 lệnh in' -and $prompt -match 'Máy in mạng' -and $prompt -match 'Print Spooler') 'Confirmation explains device removal, kept drivers and every risk'
    Assert (-not ((Get-DeployOfflineRemovalPrompt @($byName['Canon [Old]']) $false) -match 'Print Spooler')) 'Spooler restart is only announced when enabled'
    function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)throw 'WMI unavailable'}
    $names=@((Get-DeployPrinterOfflineScan).Rows | ForEach-Object {$_.Name})
    Assert (-not ($names -ccontains 'Canon LBP2900 (Copy 1)') -and $names -ccontains '\\server\Office') 'A failed WMI query only narrows detection to the spooler status'
    function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)Assert ($ClassName -ceq 'Win32_Printer') 'Offline detection reads printer status only';$script:wmi}
    $script:jobs=@{'Canon [Old]'=@('j1','j2')};$script:removedJobs=@()
    function Get-PrintJob {param($PrinterObject,$ErrorAction)$name=[string]$PrinterObject.Name;if($script:jobs.ContainsKey($name)){foreach($id in @($script:jobs[$name])){[pscustomobject]@{Printer=$name;Id=$id}}}}
    function Remove-PrintJob {param($InputObject,$ErrorAction)$script:removedJobs+=($InputObject.Printer+'#'+$InputObject.Id);$script:jobs.Remove($InputObject.Printer)}
    $script:removed=@();$script:removeFails=@();$script:handles=@()
    function Remove-Printer {param($InputObject,$Name,$ErrorAction)
        Assert ($null -eq $Name -and $null -ne $InputObject) 'Removal passes the exact spooler object, never a wildcard name'
        $target=[string]$InputObject.Name
        if($script:removeFails -ccontains $target){throw 'Access denied by spooler'}
        $script:removed+=$target
        # Windows only marks a queue for deletion while jobs or open handles (Devices and Printers) remain.
        if($script:jobs.ContainsKey($target) -or $script:handles -ccontains $target){$InputObject.PrinterStatus='PendingDeletion';return}
        $script:queues=@($script:queues | Where-Object {$_.Name -cne $target})
        $script:pnp=@($script:pnp | Where-Object {-not ($_.Class -eq 'PrintQueue' -and $_.FriendlyName -ceq $target)})
    }
    $script:removedNodes=@();$script:failNodes=@()
    function Remove-DeployPhantomDevice([string]$InstanceId){
        $node=@($script:pnp | Where-Object {$_.InstanceId -ceq $InstanceId})
        if(-not $node.Count){return $false}
        if($node[0].Present){throw ('Device is connected; not removed: '+$InstanceId)}
        if($script:failNodes -ccontains $InstanceId){throw 'CM_Uninstall_DevNode 0x17'}
        $script:removedNodes+=$InstanceId
        $script:pnp=@($script:pnp | Where-Object {$_.InstanceId -cne $InstanceId})
        return $true
    }
    $script:spoolerRestarts=0
    function Restart-Service {param($Name,[switch]$Force,$ErrorAction)
        Assert ($Name -ceq 'Spooler' -and $Force) 'Only the Print Spooler service is restarted'
        $script:spoolerRestarts++;$script:handles=@()
        foreach($queue in @($script:queues | Where-Object {[string]$_.PrinterStatus -eq 'PendingDeletion'})){
            $script:queues=@($script:queues | Where-Object {$_.Name -cne $queue.Name})
            $script:pnp=@($script:pnp | Where-Object {-not ($_.Class -eq 'PrintQueue' -and $_.FriendlyName -ceq $queue.Name)})
        }
    }
    $script:admin=$false
    Throws {Remove-DeployOfflinePrinters @('Canon [Old]') $log} 'Admin is required before removing printers'
    Assert ($script:removed.Count -eq 0 -and $script:removedNodes.Count -eq 0) 'Nothing is removed without admin'
    $script:admin=$true
    Throws {Remove-DeployOfflinePrinters @('',' ') $log} 'Empty selection is rejected'
    $progress=[hashtable]::Synchronized(@{Index=0;Total=0;Current='';Step='';Percent=0;Lines=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))})
    $r=Remove-DeployOfflinePrinters @('Canon LBP2900 (Copy 1)','Canon [Old]','Canon MF240','Gone','device:c9','node:SWD\PRINTENUM\{OLDFAX}') $log $progress
    Assert ($r.Kind -eq 'Attention' -and @($r.Removed).Count -eq 4 -and @($r.Skipped).Count -eq 2 -and $r.Message -match 'Đã gỡ 4' -and $r.Message -match 'Driver vẫn giữ') 'Queues and leftover devices are removed; connected or missing entries are skipped and reported'
    Assert (@($script:removed).Count -eq 2 -and $script:removed -ccontains 'Canon [Old]' -and -not ($script:removed -ccontains 'Canon MF240')) 'Connected printer is never passed to Remove-Printer'
    Assert ($script:removedJobs.Count -eq 2 -and @($script:queues | Where-Object {$_.Name -ceq 'Canon [Old]'}).Count -eq 0) 'Pending jobs are cancelled first so the queue is really deleted'
    $expectedNodes='USBPRINT\CANON\A','USB\VID_04A9\A','USBPRINT\CANON\B','USB\VID_04A9\B','USBPRINT\CANON\G9','SWD\PRINTENUM\{G9}','USB\VID_04A9\G9','SWD\PRINTENUM\{OLDFAX}'
    Assert ($script:removedNodes.Count -eq $expectedNodes.Count -and -not @($expectedNodes | Where-Object {$script:removedNodes -cnotcontains $_}).Count) 'Disconnected device nodes of the removed printers are removed, like Remove device'
    Assert ([array]::IndexOf($script:removedNodes,'USBPRINT\CANON\A') -lt [array]::IndexOf($script:removedNodes,'USB\VID_04A9\A')) 'Device nodes are removed child first'
    Assert (@($script:pnp | Where-Object {$_.ContainerId -eq 'c3'}).Count -eq 3 -and @($script:pnp | Where-Object {$_.InstanceId -in 'STORAGE\VOLUME\OLD','USB\ROOT_HUB30\1','USBPRINT\CANON\H10','USBPRINT\CANON\R12'}).Count -eq 4) 'Connected devices, the computer container and kept devices are untouched'
    Assert ($progress.Total -eq 6 -and $progress.Percent -eq 100 -and $progress.Lines.Count -eq 6 -and @($r.Lines | Where-Object {$_ -match '^✓'}).Count -eq 4 -and @($r.Lines | Where-Object {$_ -match '^–'}).Count -eq 2) 'Progress reports every entry with one result line each'
    $r=Remove-DeployOfflinePrinters @('TOSHIBA 457') $log
    Assert ($r.Kind -eq 'Success' -and @($r.Lines)[0] -match 'không có thiết bị đi kèm' -and @($script:pnp | Where-Object {$_.InstanceId -ceq 'STORAGE\VOLUME\OLD'}).Count -eq 1 -and $script:removedNodes.Count -eq 8) 'A queue in the computer container is removed without touching other device nodes'
    ($script:queues | Where-Object {$_.Name -ceq 'Shared USB'}).PrinterStatus='Normal'
    $before=@($script:removed).Count
    $r=Remove-DeployOfflinePrinters @('Shared USB') $log
    Assert ($r.Kind -eq 'Attention' -and @($script:removed).Count -eq $before -and $r.Message -match 'kết nối lại') 'Printer reconnected after the list was shown is skipped'
    $script:removeFails=@('Copier Custom')
    $r=Remove-DeployOfflinePrinters @('Copier Custom','Default USB') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Removed) -ccontains 'Default USB' -and @($r.Failed).Count -eq 1 -and $r.Message -match 'Access denied' -and $script:removedNodes -ccontains 'USBPRINT\GENERIC\D') 'One spooler failure does not stop the other removals and is reported'
    $r=Remove-DeployOfflinePrinters @('Copier Custom') $log
    Assert ($r.Kind -eq 'Error' -and -not @($r.Removed).Count) 'Failures only yield an error result'
    $script:removeFails=@();$script:failNodes=@('WSDPRINT\FAILNODE')
    $r=Remove-DeployOfflinePrinters @('\\server\Office') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Partial) -ccontains '\\server\Office' -and $r.Message -match 'chưa trọn' -and @($r.Lines)[0] -match 'chưa xoá được 1 mục thiết bị') 'A device node that cannot be removed is reported, not hidden behind success'
    $script:failNodes=@();$script:handles=@('WSD Printer')
    $r=Remove-DeployOfflinePrinters @('WSD Printer') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Pending) -ccontains 'WSD Printer' -and $r.Message -match 'chưa xoá xong' -and $script:spoolerRestarts -eq 0) 'A queue Windows only marked for deletion is reported as pending, not as removed'
    $pendingRow=@((Get-DeployPrinterOfflineScan).Rows | Where-Object {$_.Name -ceq 'WSD Printer'})
    Assert ($pendingRow.Count -eq 1 -and $pendingRow[0].Detail -match 'chưa xoá xong') 'A pending queue stays listed so it can be removed again'
    $r=Remove-DeployOfflinePrinters @('WSD Printer') $log -RestartSpooler
    Assert ($r.Kind -eq 'Success' -and $script:spoolerRestarts -eq 1 -and @($r.Removed) -ccontains 'WSD Printer' -and @($script:queues | Where-Object {$_.Name -ceq 'WSD Printer'}).Count -eq 0) 'Restarting the Print Spooler finishes a pending deletion and is verified'
    $script:queues+=New-TestQueue 'Split USB' 'USB021' 'Offline'
    $script:pnp+=@((New-TestNode 'SWD\PRINTENUM\{S}' 'PrintQueue' 'Split USB' $true 'q21'),(New-TestNode 'USBPRINT\CANON\S' 'Printer' 'Canon LBP2900' $false 'c21' 'USB\VID_04A9\S'),(New-TestNode 'USB\VID_04A9\S' 'USB' 'USB Printing Support' $false 'c21'))
    $script:portMap['USBPRINT\CANON\S']='USB021'
    $r=Remove-DeployOfflinePrinters @('Split USB') $log
    Assert ($r.Kind -eq 'Success' -and $script:removedNodes -ccontains 'USBPRINT\CANON\S' -and $script:removedNodes -ccontains 'USB\VID_04A9\S' -and -not @($script:pnp | Where-Object {$_.ContainerId -in 'q21','c21'}).Count) 'When the queue node and the USBPRINT node sit in different containers, both are cleared'
    $script:queues+=New-TestQueue 'Late USB' 'USB020' 'Offline'
    function Get-DeployPnpDevices {throw 'SetupAPI unavailable'}
    $r=Remove-DeployOfflinePrinters @('Late USB') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Removed) -ccontains 'Late USB' -and $r.Message -match 'Chưa đọc được danh sách thiết bị') 'Without the device list only the queue is removed and the gap is reported'
    function Get-DeployPnpDevices {$script:pnp}
    $entries=@(Get-Content $log | ForEach-Object {$_ | ConvertFrom-Json})
    Assert (@($entries | Where-Object Event -eq 'printer-remove-before').Count -ge 7 -and @($entries | Where-Object Event -eq 'device-node-removed').Count -ge 9 -and @($entries | Where-Object Event -eq 'device-node-failed').Count -eq 1 -and @($entries | Where-Object Event -eq 'printer-cleanup-skipped').Count -ge 3 -and @($entries | Where-Object Event -eq 'spooler-restarted').Count -eq 1) 'Cleanup logs each queue, device node, skip, failure and spooler restart'
    $snap=Get-DeployDefaultsSnapshot
    Assert (@($snap.OfflinePrinters | Where-Object {$_.Name -ceq 'Copier Custom'}).Count -eq 1 -and -not $snap.OfflineError -and -not $snap.OfflineDeviceError) 'Defaults snapshot carries the offline printer list'
    Write-Host "PASS: $checks default settings assertions; exact printer scope, A4 readback, partial failure, logging, Windows app consent, association verification and offline printer cleanup."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
