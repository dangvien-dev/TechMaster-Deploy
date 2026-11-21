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
    Write-Host "PASS: $checks default settings assertions; exact printer scope, A4 readback, partial failure, logging, Windows app consent and association verification."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
