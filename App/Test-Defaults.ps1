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
    # Offline printer cleanup: only offline USB / network queues, re-checked and removed by exact object.
    $script:queueFails=$false;$script:admin=$true;$script:default='Default USB'
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
        (New-TestQueue 'Custom Port' 'MYPORT' 'Offline'))
    $script:wmi=@([pscustomobject]@{Name='Canon LBP2900 (Copy 1)';WorkOffline=$true;PrinterStatus=3},[pscustomobject]@{Name='Canon MF240';WorkOffline=$false;PrinterStatus=3},[pscustomobject]@{Name='WSD Printer';WorkOffline=$false;PrinterStatus=7},[pscustomobject]@{Name='Microsoft Print to PDF';WorkOffline=$true;PrinterStatus=7})
    $script:portInfo=@([pscustomobject]@{Name='TOSHIBA_PORT';PrinterHostAddress='192.168.1.50'},[pscustomobject]@{Name='MYPORT';PrinterHostAddress=''})
    $scan=Get-DeployPrinterOfflineScan
    $names=@($scan.Rows | ForEach-Object {$_.Name})
    Assert ($names -ccontains 'Canon LBP2900 (Copy 1)' -and $names -ccontains 'Canon [Old]') 'Unplugged USB queues are found from WorkOffline or the spooler Offline status'
    Assert (-not ($names -ccontains 'Canon MF240')) 'Connected USB printer is never listed'
    Assert (-not ($names -ccontains 'Microsoft Print to PDF') -and -not ($names -ccontains 'Fax') -and -not ($names -ccontains 'Custom Port')) 'Virtual and unknown ports are never listed, even when reported offline'
    Assert ($names -ccontains 'TOSHIBA 457' -and $names -ccontains 'Copier Custom' -and $names -ccontains 'WSD Printer' -and $names -ccontains '\\server\Office' -and $names.Count -eq 8) 'TCP/IP, custom TCP/IP, WSD and shared connections are recognised as network printers'
    $byName=@{};foreach($row in $scan.Rows){$byName[$row.Name]=$row}
    Assert ($byName['Canon LBP2900 (Copy 1)'].Selected -and $byName['Canon [Old]'].Selected) 'Offline USB queues are preselected'
    Assert (-not $byName['Default USB'].Selected -and -not $byName['Shared USB'].Selected -and -not $byName['TOSHIBA 457'].Selected -and -not $byName['\\server\Office'].Selected) 'Default, shared and network printers need an explicit tick'
    Assert ($byName['Canon [Old]'].Detail -match '2 lệnh in' -and $byName['Default USB'].Detail -match 'mặc định' -and $byName['TOSHIBA 457'].Kind -ceq 'Network' -and $byName['Canon [Old]'].Kind -ceq 'USB') 'Row details flag pending jobs, default printer and connection kind'
    Assert ($scan.Rows[0].Kind -ceq 'USB' -and $scan.Rows[-1].Kind -ceq 'Network') 'USB leftovers are listed before network printers'
    $prompt=Get-DeployOfflineRemovalPrompt @($byName['Canon [Old]'],$byName['Default USB'],$byName['TOSHIBA 457'])
    Assert ($prompt -match 'Gỡ 3 máy in' -and $prompt.Contains('Canon [Old]') -and $prompt -match 'máy in mặc định khác' -and $prompt -match 'Còn 2 lệnh in' -and $prompt -match 'Máy in mạng') 'Confirmation lists every queue and warns about default printer, pending jobs and network printers'
    $script:removed=@();$script:removeFails=@();$script:sticky=@();$script:pending=@()
    function Remove-Printer {param($InputObject,$Name,$ErrorAction)
        Assert ($null -eq $Name -and $null -ne $InputObject) 'Removal passes the exact spooler object, never a wildcard name'
        if($script:removeFails -ccontains $InputObject.Name){throw 'Access denied by spooler'}
        $script:removed+=$InputObject.Name
        if($script:pending -ccontains $InputObject.Name){$InputObject.PrinterStatus='PendingDeletion';return}
        if(-not ($script:sticky -ccontains $InputObject.Name)){$script:queues=@($script:queues | Where-Object {$_.Name -cne $InputObject.Name})}
    }
    $script:admin=$false
    Throws {Remove-DeployOfflinePrinters @('Canon [Old]') $log} 'Admin is required before removing printers'
    Assert ($script:removed.Count -eq 0) 'No queue is removed without admin'
    $script:admin=$true
    Throws {Remove-DeployOfflinePrinters @('',' ') $log} 'Empty selection is rejected'
    $r=Remove-DeployOfflinePrinters @('Canon LBP2900 (Copy 1)','Canon [Old]','Canon MF240','Gone') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Removed).Count -eq 2 -and @($r.Skipped).Count -eq 2 -and $r.Message -match 'Đã gỡ 2 máy in') 'Offline queues are removed; connected or missing names are skipped and reported'
    Assert (@($script:removed).Count -eq 2 -and $script:removed -ccontains 'Canon [Old]' -and -not ($script:removed -ccontains 'Canon MF240')) 'Connected printer is never passed to Remove-Printer'
    Assert (@($script:queues | Where-Object {$_.Name -ceq 'Canon MF240'}).Count -eq 1 -and @($script:queues | Where-Object {$_.Name -ceq 'Canon [Old]'}).Count -eq 0) 'Removed queue is gone and the connected queue stays installed'
    ($script:queues | Where-Object {$_.Name -ceq 'Shared USB'}).PrinterStatus='Normal'
    $before=@($script:removed).Count
    $r=Remove-DeployOfflinePrinters @('Shared USB') $log
    Assert ($r.Kind -eq 'Attention' -and @($script:removed).Count -eq $before -and $r.Message -match 'kết nối lại') 'Printer reconnected after the list was shown is skipped'
    $script:removeFails=@('TOSHIBA 457')
    $r=Remove-DeployOfflinePrinters @('TOSHIBA 457','Default USB') $log
    Assert ($r.Kind -eq 'Attention' -and @($r.Removed) -ccontains 'Default USB' -and @($r.Failed).Count -eq 1 -and $r.Message -match 'Access denied') 'One spooler failure does not stop the other removals and is reported'
    $r=Remove-DeployOfflinePrinters @('TOSHIBA 457') $log
    Assert ($r.Kind -eq 'Error' -and -not @($r.Removed).Count) 'Failures only yield an error result'
    $script:removeFails=@();$script:sticky=@('WSD Printer')
    $r=Remove-DeployOfflinePrinters @('WSD Printer') $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'vẫn còn hàng đợi') 'Queue still present after removal is not reported as removed'
    $script:pending=@('Copier Custom')
    $r=Remove-DeployOfflinePrinters @('Copier Custom') $log
    Assert ($r.Kind -eq 'Success' -and @($r.Removed) -ccontains 'Copier Custom') 'PendingDeletion after removal counts as removed'
    $entries=@(Get-Content $log | ForEach-Object {$_ | ConvertFrom-Json})
    Assert (@($entries | Where-Object Event -eq 'printer-remove-before').Count -ge 4 -and @($entries | Where-Object Event -eq 'printer-cleanup-skipped').Count -ge 3 -and @($entries | Where-Object Event -eq 'printer-remove-failed').Count -ge 2) 'Cleanup logs each queue before removal, skips and failures'
    $snap=Get-DeployDefaultsSnapshot
    Assert (@($snap.OfflinePrinters | Where-Object {$_.Name -ceq '\\server\Office'}).Count -eq 1 -and -not $snap.OfflineError) 'Defaults snapshot carries the offline printer list'
    function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)throw 'WMI unavailable'}
    $names=@((Get-DeployPrinterOfflineScan).Rows | ForEach-Object {$_.Name})
    Assert (-not ($names -ccontains 'WSD Printer') -and $names -ccontains '\\server\Office') 'A failed WMI query only narrows detection to the spooler status'
    Write-Host "PASS: $checks default settings assertions; exact printer scope, A4 readback, partial failure, logging, Windows app consent, association verification and offline printer cleanup."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
