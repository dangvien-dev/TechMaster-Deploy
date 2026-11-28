# Printer cmdlets, pnputil, network probes, Credential Manager, registry and Print Spooler are mocked; INF parsing reads real files in a temporary folder.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PrinterConnect.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m,$pattern=''){$failed=$false;$text='';try{& $action | Out-Null}catch{$failed=$true;$text=$_.Exception.GetBaseException().Message};Assert ($failed -and (-not $pattern -or $text -match $pattern)) "$m ($text)"}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-printer-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
try{
    $log=Join-Path $temp 'printer.jsonl'
    # ---------- Input ----------
    Assert ((ConvertFrom-DeployPrinterAddress ' 192.168.1.50 ') -ceq '192.168.1.50' -and (ConvertFrom-DeployPrinterAddress 'NPI1A2B3C') -ceq 'NPI1A2B3C') 'IP and printer host names are accepted and trimmed'
    Throws {ConvertFrom-DeployPrinterAddress '192.168.1.300'} 'An IP octet above 255 is refused' 'không hợp lệ'
    Throws {ConvertFrom-DeployPrinterAddress 'http://192.168.1.50'} 'A web address is refused with guidance' 'http://'
    Throws {ConvertFrom-DeployPrinterAddress '127.0.0.1'} 'Loopback is refused' 'không dùng được'
    Throws {ConvertFrom-DeployPrinterAddress '192.168.1'} 'An incomplete IP is not taken for a host name' 'IP có dạng'
    Throws {ConvertFrom-DeployPrinterAddress ''} 'An empty address is refused' 'Nhập địa chỉ IP'
    Assert ((ConvertFrom-DeployPrinterPortNumber '') -eq 9100 -and (ConvertFrom-DeployPrinterPortNumber ' 515 ') -eq 515) 'Port defaults to RAW 9100'
    Throws {ConvertFrom-DeployPrinterPortNumber '70000'} 'An out-of-range port is refused' 'Cổng không hợp lệ'
    Assert ((Get-DeployPrinterPortName '192.168.1.50' 9100) -ceq 'IP_192.168.1.50' -and (Get-DeployPrinterPortName '192.168.1.50' 515) -ceq 'IP_192.168.1.50_515') 'Port names follow the Windows IP_ convention'
    $share=ConvertFrom-DeployPrinterShare ' //KE-TOAN/Canon2900 '
    Assert ($share.Server -ceq 'KE-TOAN' -and $share.Share -ceq 'Canon2900' -and $share.Path -ceq '\\KE-TOAN\Canon2900') 'A shared printer path is normalised'
    Throws {ConvertFrom-DeployPrinterShare '\\KE-TOAN\Canon2900\sub'} 'A printer path with a subfolder is refused' 'không có thư mục con'
    Throws {Assert-DeployPrinterName 'A\B'} 'A printer name with a backslash is refused' 'không được chứa'

    # ---------- Error codes ----------
    Assert ((Get-DeployPrinterErrorCode ([ComponentModel.Win32Exception]::new(1801))) -eq 1801) 'A Win32 exception gives its code'
    Assert ((Get-DeployPrinterErrorCode ([Exception]::new('Operation failed with error 0x0000011b.'))) -eq 283) 'A code written in the message is read (0x0000011b)'
    Assert ((Get-DeployPrinterErrorCode ([Runtime.InteropServices.COMException]::new('x',[int]0x80070BCB))) -eq 3019) 'A Win32 HRESULT gives its code (0x00000bcb)'
    Assert ((Get-DeployPrinterErrorCode ([pscustomobject]@{Message='Access';ErrorData=[pscustomobject]@{error_Code=5}})) -eq 5) 'CIM error data gives its code'
    $record=$null;try{throw [ComponentModel.Win32Exception]::new(1722)}catch{$record=$_}
    Assert ((Get-DeployPrinterErrorCode $record) -eq 1722) 'An error record is unwrapped'
    Assert ((Get-DeployPrinterErrorCode ([Exception]::new('outer',[ComponentModel.Win32Exception]::new(1801)))) -eq 1801) 'Inner exceptions are searched'
    Assert ((Get-DeployPrinterErrorCode ([Exception]::new('no code'))) -eq 0) 'Unknown failures give 0'
    $modern=[pscustomobject]@{Build=22631;RpcNamedPipes=$false};$old=[pscustomobject]@{Build=19045;RpcNamedPipes=$false}
    $text=Get-DeployPrinterErrorText 283 $modern
    Assert ($text -match '0x0000011b' -and $text -match 'Chế độ tương thích RPC' -and $text -match 'Không tắt RpcAuthnLevelPrivacyEnabled' -and $text -match 'theo IP') '0x0000011b explains the cause, suggests the client-side mode and warns against disabling the server protection'
    Assert (-not ((Get-DeployPrinterErrorText 283 $old) -match 'Chế độ tương thích')) 'The RPC mode is not suggested on Windows 10'
    Assert ((Get-DeployPrinterErrorText 1801 $modern) -match '0x00000709' -and (Get-DeployPrinterErrorText 1801 ([pscustomobject]@{Build=22631;RpcNamedPipes=$true})) -notmatch 'Chế độ tương thích') '0x00000709 suggests the RPC mode only while it is off'
    Assert ((Get-DeployPrinterErrorText 3019 $modern) -match '0x00000bcb' -and (Get-DeployPrinterErrorText 3019 $modern) -match 'thư mục driver') '0x00000bcb leads to installing the driver as administrator'
    Assert ((Get-DeployPrinterErrorText 1326) -match 'Sai tài khoản' -and (Get-DeployPrinterErrorText 1272) -match 'Guest' -and (Get-DeployPrinterErrorText 4321) -match '0x000010e1') 'Logon codes reuse the LAN messages; others show their hex code'

    # ---------- INF ----------
    $inf=@'
[Version]
Signature="$Windows NT$"
Class=Printer ; printers
ClassGuid={4D36E979-E325-11CE-BFC1-08002BE10318}
[Manufacturer]
%TOSHIBA%=TOSHIBA,NTamd64,NTx86
"Canon"=CANON,NTamd64.10.0
[TOSHIBA.NTamd64]
"TOSHIBA Universal Printer 2" = UNI2, USBPRINT\TOSHIBAUNI2
%ESTUDIO% = ES2010, WSDPRINT\TOSHIBAES2010 ; comment
"TOSHIBA Universal Printer 2" = UNI2, LPTENUM\TOSHIBAUNI2
[TOSHIBA.NTx86]
"TOSHIBA x86 Only" = X86
[CANON.NTamd64.10.0]
"Canon LBP2900; Series" = LBP
[Strings]
TOSHIBA="Toshiba"
ESTUDIO="TOSHIBA e-STUDIO2010AC PCL6"
'@
    $models=@(Get-DeployPrinterInfModels $inf 'amd64')
    Assert (($models.Model -join '|') -ceq 'Canon LBP2900; Series|TOSHIBA e-STUDIO2010AC PCL6|TOSHIBA Universal Printer 2') "x64 models are read once each, with strings resolved and ; inside quotes kept ($($models.Model -join '|'))"
    Assert ((@($models | Where-Object {$_.Model -like 'TOSHIBA e-*'})[0].Manufacturer) -ceq 'Toshiba') 'Manufacturer names are resolved'
    Assert ((@(Get-DeployPrinterInfModels $inf 'x86').Model -join '|') -ceq 'TOSHIBA x86 Only') 'Only sections for the processor of this computer are used'
    Assert (@(Get-DeployPrinterInfModels ($inf -replace 'Class=Printer ; printers','Class=Net' -replace 'ClassGuid=\{4D36E979[^}]+\}','ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}') 'amd64').Count -eq 0) 'Non-printer INFs give no model'
    Assert (@(Get-DeployPrinterInfModels ($inf -replace 'Class=Printer ; printers','') 'amd64').Count -eq 3) 'The printer ClassGuid alone identifies a printer INF'
    $kho=Join-Path $temp 'KhoDriver';New-Item -ItemType Directory (Join-Path $kho 'Toshiba\x64') -Force | Out-Null;New-Item -ItemType Directory (Join-Path $kho 'Net') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $kho 'Toshiba\x64\esf6u.inf'),$inf,[Text.UnicodeEncoding]::new($false,$true))
    [IO.File]::WriteAllText((Join-Path $kho 'Net\nic.inf'),"[Version]`r`nClass=Net`r`n[Manufacturer]`r`nIntel=INTEL`r`n[INTEL]`r`n""Intel NIC""=X")
    [IO.File]::WriteAllText((Join-Path $kho 'readme.txt'),'x')
    $packages=@(Get-DeployPrinterDriverPackages $kho 'amd64')
    Assert ($packages.Count -eq 3 -and @($packages | Where-Object {$_.Inf -notlike '*esf6u.inf'}).Count -eq 0) 'A driver folder is searched recursively; UTF-16 INFs are read and network drivers ignored'
    Throws {Get-DeployPrinterDriverPackages (Join-Path $temp 'missing')} 'A missing folder is reported'
    Throws {Get-DeployPrinterDriverPackages $kho 'amd64' 0} 'Folders with too many INF files are refused' 'hơn 0'

    # ---------- Mocks ----------
    $script:calls=New-Object Collections.ArrayList
    $script:admin=$true;$script:tcp=@{};$script:ping=$true
    $script:drivers=New-Object Collections.ArrayList;[void]$script:drivers.Add('Microsoft Print To PDF')
    $script:ports=New-Object Collections.ArrayList;$script:printers=New-Object Collections.ArrayList
    $script:pnpExit=0;$script:remoteDriver='';$script:logon=0;$script:creds=@{};$script:connectFailure=$null
    $script:rpc=[pscustomobject]@{Present=$false;Value=$null;Kind=''};$script:build=22631;$script:rpcBackup=Join-Path $temp 'rpc-backup.json';$script:spoolerRestarts=0;$script:spoolerFail=$false
    function Test-DeployPrinterAdmin {$script:admin}
    function Test-DeployTcpPort([string]$HostName,[int]$Port,[int]$TimeoutMs=1500){$key=$HostName+':'+$Port;if($script:tcp.ContainsKey($key)){$script:tcp[$key]}else{$false}}
    function Test-DeployPing([string]$HostName){$script:ping}
    function Get-DeploySpoolerState {'Running'}
    function Get-PrinterDriver {@($script:drivers | ForEach-Object {[pscustomobject]@{Name=$_;PrinterEnvironment='Windows x64'}})}
    function Get-DeployPrinterArchitecture {'amd64'}
    function Invoke-DeployPnputil([string[]]$Arguments){[void]$script:calls.Add('pnputil:'+($Arguments -join ' '));[pscustomobject]@{ExitCode=$script:pnpExit;Output='ok'}}
    function Add-PrinterDriver([string]$Name){[void]$script:calls.Add('driver:'+$Name);[void]$script:drivers.Add($Name)}
    function Get-PrinterPort {@($script:ports)}
    function Add-PrinterPort([string]$Name,[string]$PrinterHostAddress,[int]$PortNumber){[void]$script:calls.Add('port:'+$Name+':'+$PortNumber);[void]$script:ports.Add([pscustomobject]@{Name=$Name;PrinterHostAddress=$PrinterHostAddress})}
    function Get-Printer {@($script:printers)}
    function Add-Printer([string]$Name,[string]$DriverName,[string]$PortName,[string]$ConnectionName){
        if($ConnectionName){
            [void]$script:calls.Add('connect:'+$ConnectionName)
            if($script:connectFailure){throw $script:connectFailure}
            [void]$script:printers.Add([pscustomobject]@{Name=$ConnectionName.ToUpperInvariant();PortName='';DriverName=$script:remoteDriver;Type='Connection'})
        }else{[void]$script:calls.Add('printer:'+$Name);[void]$script:printers.Add([pscustomobject]@{Name=$Name;PortName=$PortName;DriverName=$DriverName;Type='Local'})}
    }
    function Set-DeployPrinterDefaults([string]$Name,[bool]$A4,[bool]$Default,[string]$LogPath){[void]$script:calls.Add('defaults:'+$Name+':'+$A4+':'+$Default);[pscustomobject]@{Message='Đã áp dụng.';Kind='Success'}}
    function Invoke-DeployPrinterTestPage([string]$Name){[void]$script:calls.Add('testpage:'+$Name)}
    function Assert-DeployConnectUser {}
    function Test-DeployServerLogon([string]$Server,[string]$User,[Security.SecureString]$Password){[void]$script:calls.Add('logon:'+$Server+':'+$User);Assert ($Password -is [Security.SecureString]) 'The logon test receives the password only as SecureString';$script:logon}
    function Save-DeployShareCredential([string]$Server,[string]$User,[Security.SecureString]$Password){[void]$script:calls.Add('save:'+$Server+':'+$User);$script:creds[$Server]=$User}
    function Get-DeployShareCredentialUser([string]$Server){if($script:creds.ContainsKey($Server)){$script:creds[$Server]}else{$null}}
    function Get-DeployRemotePrinterDriver([string]$Server,[string]$Share){$script:remoteDriver}
    function Get-DeployWindowsToolsIdentity {[pscustomobject]@{Build=$script:build;Ubr=1;Sid='S-1-5-21-1';User='TEST\user';Session=1}}
    function Get-DeployPrinterRpcSetting {$script:rpc}
    function Set-DeployPrinterRpcSetting($State){[void]$script:calls.Add('rpc:'+$State.Present+':'+$State.Value);$script:rpc=[pscustomobject]@{Present=[bool]$State.Present;Value=$(if($State.Present){[int]$State.Value}else{$null});Kind=$(if($State.Present){'DWord'}else{''})}}
    function Get-DeployPrinterRpcBackupPath {$script:rpcBackup}
    function Restart-DeployPrintSpooler {if($script:spoolerFail){throw 'access denied'};$script:spoolerRestarts++}
    function Since([int]$from){@($script:calls | Select-Object -Skip $from)}

    # ---------- Add by IP ----------
    $infPath=Join-Path $kho 'Toshiba\x64\esf6u.inf'
    $script:tcp['192.168.1.50:9100']=$true
    $r=Add-DeployIpPrinter '192.168.1.50' '' 'Photocopy tầng 2' 'TOSHIBA e-STUDIO2010AC PCL6' $infPath $true $true $true $log
    $order=@($script:calls)
    Assert ($r.Kind -eq 'Success' -and ($order -join '|') -ceq ('pnputil:/add-driver '+$infPath+'|driver:TOSHIBA e-STUDIO2010AC PCL6|port:IP_192.168.1.50:9100|printer:Photocopy tầng 2|defaults:Photocopy tầng 2:True:True|testpage:Photocopy tầng 2')) "The driver is staged and installed before the TCP/IP port and queue, then A4 / default / test page ($($order -join '|'))"
    Assert ($r.Message -match 'Standard TCP/IP' -and $r.Message -match 'SNMP' -and $r.Message -match 'chữ ký') 'The result says how the printer was added'
    $before=$script:calls.Count
    $r=Add-DeployIpPrinter '192.168.1.50' 9100 'Photocopy tầng 2' 'TOSHIBA e-STUDIO2010AC PCL6' '' $false $false $false $log
    Assert ($r.Kind -eq 'Success' -and (Since $before).Count -eq 0 -and $r.Message -match 'Dùng lại cổng' -and $r.Message -match 'không tạo lại') 'Running again reuses the port and queue and changes nothing'
    $before=$script:calls.Count
    Throws {Add-DeployIpPrinter '192.168.1.50' 9100 'Photocopy tầng 2' 'Microsoft Print To PDF' '' $false $false $false $log} 'A name already used by another queue is refused' 'Đặt tên khác'
    Assert (@(Since $before | Where-Object {$_ -like 'printer:*'}).Count -eq 0) 'Nothing is created when the name is taken'
    [void]$script:ports.Add([pscustomobject]@{Name='IP_192.168.1.60';PrinterHostAddress='192.168.1.99'})
    Throws {Add-DeployIpPrinter '192.168.1.60' 9100 'Ricoh' 'Microsoft Print To PDF' '' $false $false $false $log} 'A port with the same name pointing elsewhere is not overwritten' 'không ghi đè'
    $r=Add-DeployIpPrinter '192.168.1.70' 9100 'Canon tắt' 'Microsoft Print To PDF' '' $false $false $false $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match '✗ Chưa kết nối được 192.168.1.70:9100' -and @($script:printers | Where-Object {$_.Name -eq 'Canon tắt'}).Count -eq 1) 'An unreachable printer still gets its queue, with a warning'
    Throws {Add-DeployIpPrinter '192.168.1.71' 9100 'X' 'Driver chưa có' '' $false $false $false $log} 'A missing driver without a folder is reported' 'Chọn thư mục driver'
    Throws {Add-DeployIpPrinter '192.168.1.71' 9100 'X' 'Model khác' $infPath $false $false $false $log} 'An INF without the chosen model is refused' 'không có model'
    $script:pnpExit=5;$before=$script:calls.Count
    Throws {Add-DeployIpPrinter '192.168.1.71' 9100 'X' 'TOSHIBA x86 Only' $infPath $false $false $false $log} 'A model for another processor is refused' 'không có model'
    Throws {Add-DeployIpPrinter '192.168.1.71' 9100 'X' 'Canon LBP2900; Series' $infPath $false $false $false $log} 'A pnputil failure (e.g. unsigned driver) stops before the queue' 'chữ ký'
    Assert (@(Since $before | Where-Object {$_ -like 'driver:*' -or $_ -like 'printer:*'}).Count -eq 0) 'No driver or queue is added after pnputil fails'
    $script:pnpExit=0
    $script:admin=$false;$before=$script:calls.Count
    Throws {Add-DeployIpPrinter '192.168.1.72' 9100 'X' 'Microsoft Print To PDF' '' $false $false $false $log} 'Adding a printer requires Administrator' 'Administrator'
    Assert ((Since $before).Count -eq 0) 'Nothing runs without Administrator'
    $script:admin=$true

    # ---------- Shared printer ----------
    $secret='Print@2026'
    $password=ConvertTo-SecureString $secret -AsPlainText -Force
    $script:remoteDriver='Canon LBP2900; Series';$before=$script:calls.Count
    $r=Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password '' '' $true $true $log
    $steps=@(Since $before)
    Assert ($r.Kind -eq 'Success' -and ($steps -join '|') -ceq 'logon:KE-TOAN:print|save:KE-TOAN:print|connect:\\KE-TOAN\Canon2900|defaults:\\KE-TOAN\CANON2900:False:True|testpage:\\KE-TOAN\CANON2900') "The account is tested on the server, saved, then the printer is connected; later steps use the queue name Windows keeps ($($steps -join '|'))"
    Assert ($r.Message -match 'lấy driver từ máy chủ bằng quyền Administrator') 'A driver the server provides is downloaded by the elevated app'
    $before=$script:calls.Count
    $r=Connect-DeploySharedPrinter '\\ke-toan\canon2900' '' (New-Object Security.SecureString) '' '' $false $false $log
    Assert ($r.Kind -eq 'Success' -and (Since $before).Count -eq 0 -and $r.Message -match 'mật khẩu đã lưu' -and $r.Message -match 'đã kết nối') 'Without a password the saved one is used; an existing connection is matched case-insensitively'
    $script:printers.Clear();$script:logon=1326;$before=$script:calls.Count
    Throws {Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password '' '' $false $false $log} 'A wrong password is reported' 'Sai tài khoản hoặc mật khẩu'
    Assert (@(Since $before | Where-Object {$_ -like 'save:*' -or $_ -like 'connect:*'}).Count -eq 0) 'A failed logon saves nothing and does not connect'
    $script:logon=0;$script:creds.Clear()
    Throws {Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' '' (New-Object Security.SecureString) '' '' $false $false $log} 'No password and nothing saved is refused without falling back to Guest' 'Guest'
    Throws {Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password 'TOSHIBA Universal Printer 2' $infPath $false $false $log} 'A driver other than the server driver is refused' 'đúng tên driver'
    $script:drivers.Remove('Canon LBP2900; Series');$before=$script:calls.Count
    $r=Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password '' $infPath $false $false $log
    Assert ($r.Kind -eq 'Success' -and @(Since $before | Where-Object {$_ -like 'driver:*'})[0] -ceq 'driver:Canon LBP2900; Series' -and (Since $before).IndexOf('driver:Canon LBP2900; Series') -lt (Since $before).IndexOf('connect:\\KE-TOAN\Canon2900')) 'The server driver is installed from the folder before connecting (avoids 0x00000bcb)'
    $script:printers.Clear()
    $script:connectFailure=[Exception]::new('Add-Printer failed',[ComponentModel.Win32Exception]::new(1801))
    Throws {Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password '' '' $false $false $log} '0x00000709 on Windows 11 22H2+ is explained with the RPC mode' 'Chế độ tương thích RPC'
    $script:connectFailure=[Exception]::new('Operation could not be completed (error 0x0000011b).')
    Throws {Connect-DeploySharedPrinter '\\KE-TOAN\Canon2900' 'print' $password '' '' $false $false $log} '0x0000011b is explained without disabling protections' 'Không tắt RpcAuthnLevelPrivacyEnabled'
    $script:connectFailure=$null
    Assert (-not ([IO.File]::ReadAllText($log).Contains($secret))) 'The password never reaches the log'

    # ---------- RPC compatibility ----------
    $view=Get-DeployPrinterRpcView
    Assert ($view.CanEnable -and -not $view.CanUndo -and $view.Text -match 'RPC over TCP') 'Windows 11 22H2+ without the setting can enable the mode'
    $script:spoolerRestarts=0
    $r=Set-DeployPrinterRpcCompatibility $true $log
    Assert ($r.Kind -eq 'Success' -and $script:rpc.Present -and $script:rpc.Value -eq 1 -and (Test-Path -LiteralPath $script:rpcBackup) -and $script:spoolerRestarts -eq 1 -and $r.Message -match 'không tắt|Không thay đổi bảo mật') 'Enabling backs up, writes RpcUseNamedPipeProtocol=1 and restarts the spooler'
    $saved=[IO.File]::ReadAllText($script:rpcBackup) | ConvertFrom-Json
    Assert ($saved.Present -eq $false) 'The backup records that the value did not exist'
    $view=Get-DeployPrinterRpcView
    Assert ($view.Enabled -and -not $view.CanEnable -and $view.CanUndo -and $view.Text -match 'app đã bật') 'The window shows the mode as enabled by the app'
    $r=Set-DeployPrinterRpcCompatibility $true $log
    Assert ($r.Kind -eq 'Info' -and $script:spoolerRestarts -eq 1) 'Enabling twice changes nothing'
    $r=Set-DeployPrinterRpcCompatibility $false $log
    Assert ($r.Kind -eq 'Success' -and -not $script:rpc.Present -and -not (Test-Path -LiteralPath $script:rpcBackup) -and $script:spoolerRestarts -eq 2) 'Undo removes the value the app added and the backup'
    $r=Set-DeployPrinterRpcCompatibility $false $log
    Assert ($r.Kind -eq 'Info' -and $r.Message -match 'Chưa có bản sao lưu') 'Undo without the app backup leaves policy settings alone'
    $script:rpc=[pscustomobject]@{Present=$true;Value=0;Kind='DWord'}
    [void](Set-DeployPrinterRpcCompatibility $true $log);[void](Set-DeployPrinterRpcCompatibility $false $log)
    Assert ($script:rpc.Present -and $script:rpc.Value -eq 0) 'An earlier explicit value is restored by undo'
    $script:rpc=[pscustomobject]@{Present=$true;Value='1';Kind='String'}
    Throws {Set-DeployPrinterRpcCompatibility $true $log} 'A value of another type is not overwritten' 'DWORD'
    $script:rpc=[pscustomobject]@{Present=$false;Value=$null;Kind=''};$script:build=19045;$before=$script:calls.Count
    $r=Set-DeployPrinterRpcCompatibility $true $log
    Assert ($r.Kind -eq 'Info' -and (Since $before).Count -eq 0 -and -not (Get-DeployPrinterRpcView).CanEnable) 'Windows 10 already uses named pipes; nothing is written'
    $script:build=22631;$script:spoolerFail=$true
    $r=Set-DeployPrinterRpcCompatibility $true $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match 'khởi động lại máy') 'A spooler that cannot restart is reported'
    $script:spoolerFail=$false;[void](Set-DeployPrinterRpcCompatibility $false $log)
    $script:admin=$false
    Throws {Set-DeployPrinterRpcCompatibility $true $log} 'Changing RPC requires Administrator' 'Administrator'
    $script:admin=$true
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PrinterConnect.Core.ps1'))
    Assert ([regex]::Matches($source,'\.SetValue\(').Count -eq 1 -and $source -match 'SetValue\(\$script:DeployPrinterRpcValue' -and $source -notmatch 'AllowInsecureGuestAuth' -and $source -notmatch 'LimitBlankPasswordUse') 'The only registry value the module writes is RpcUseNamedPipeProtocol; no protection is switched off'

    # ---------- Diagnosis ----------
    [void]$script:printers.Add([pscustomobject]@{Name='Photocopy tầng 2';PortName='IP_192.168.1.50';DriverName='TOSHIBA e-STUDIO2010AC PCL6';Type='Local'})
    $script:tcp=@{'192.168.1.50:9100'=$true;'192.168.1.50:80'=$true}
    $d=Format-DeployPrinterDiagnosis (Get-DeployIpPrinterDiagnosis '192.168.1.50' '')
    Assert ($d.Kind -eq 'Success' -and $d.Message -match '✓ Cổng in 9100 mở' -and $d.Message -match 'http://192.168.1.50' -and $d.Message -match 'Photocopy tầng 2') 'IP diagnosis shows the open print port, web page and existing queue'
    $script:tcp=@{};$script:ping=$false
    $d=Format-DeployPrinterDiagnosis (Get-DeployIpPrinterDiagnosis '192.168.1.80' 9100)
    Assert ($d.Kind -eq 'Error' -and $d.Message -match '✗ Chưa kết nối được cổng 9100' -and $d.Message -match '– Máy in 192.168.1.80 không trả lời ping') 'A closed print port is a failure; no ping is only information'
    $script:tcp=@{'KE-TOAN:445'=$true};$script:ping=$true;$script:creds.Clear();$script:drivers.Remove('Canon LBP2900; Series')
    $d=Format-DeployPrinterDiagnosis (Get-DeploySharePrinterDiagnosis '\\KE-TOAN\Canon2900')
    Assert ($d.Kind -eq 'Attention' -and $d.Message -match '! Cổng 135' -and $d.Message -match '! Chưa lưu mật khẩu' -and $d.Message -match 'Guest' -and $d.Message -match '! Máy này chưa có driver Canon LBP2900' -and $d.Message -match '! Cách kết nối máy chủ in') 'Share diagnosis flags closed RPC, missing password and driver, and points to the RPC mode'
    $script:tcp=@{}
    $d=Format-DeployPrinterDiagnosis (Get-DeploySharePrinterDiagnosis '\\KE-TOAN\Canon2900')
    Assert ($d.Kind -eq 'Error' -and $d.Message -match '✗ Không vào được cổng 445' -and $d.Message -match 'Chưa đọc được tên driver') 'An unreachable server is a failure and its driver is not queried'
    $r=Invoke-DeployPrinterConnectAction 'Diagnose' @{Mode='Ip';Address='192.168.1.80';Port=9100} $log
    Assert ($r.Kind -eq 'Error' -and $r.Log -eq $log) 'The worker routes diagnosis by mode'
    $r=Invoke-DeployPrinterConnectAction 'Scan' @{Folder=$kho} $log
    Assert ($r.Kind -eq 'Success' -and @($r.Packages).Count -eq 3) 'The worker scans a driver folder'
    $r=Invoke-DeployPrinterConnectAction 'Inspect' $null $log
    Assert (@($r.Drivers) -contains 'Microsoft Print To PDF' -and $r.Rpc.Build -eq 22631) 'Inspect returns installed drivers and the RPC state'
    Write-Host "PASS: $checks network printer assertions; input, Win32 codes 0x11b / 0x709 / 0xbcb, INF models, TCP/IP add, shared connection with saved password, driver from folder, RPC mode with backup / undo, diagnosis."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
