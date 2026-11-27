# Printer changes target an exact installed queue; app associations use Windows Settings.
. (Join-Path $PSScriptRoot 'Windows.Tools.ps1')
function Initialize-DeployDefaultsNative {
    if(-not ('TechMaster.DefaultsNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Defaults.Native.cs')}
}
function Assert-DeployPrinterAdmin {
    $who=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not ([Security.Principal.WindowsPrincipal]::new($who)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Mở TechMaster Deploy bằng quyền Administrator để thay thiết lập máy in.'}
}
function Get-DeployDefaultPrinter {Initialize-DeployDefaultsNative;[TechMaster.DefaultsNative]::Printer()}
function Set-DeployDefaultPrinterNative([string]$Name) {Initialize-DeployDefaultsNative;[TechMaster.DefaultsNative]::SetPrinter($Name)}
function Get-DeployPrinterManagement {
    $root=Open-DeployMenuRegistry;$key=$null
    try{
        $key=$root.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Windows')
        $present=$key -and 'LegacyDefaultPrinterMode' -in $key.GetValueNames()
        [pscustomobject]@{Present=[bool]$present;Value=$(if($present){$key.GetValue('LegacyDefaultPrinterMode')}else{$null});Kind=$(if($present){[string]$key.GetValueKind('LegacyDefaultPrinterMode')}else{''})}
    }finally{if($key){$key.Dispose()};$root.Dispose()}
}
function Set-DeployPrinterManagement($State) {
    $root=Open-DeployMenuRegistry;$key=$null
    try{
        $key=$root.CreateSubKey('Software\Microsoft\Windows NT\CurrentVersion\Windows')
        if($State.Present){$key.SetValue('LegacyDefaultPrinterMode',[int]$State.Value,[Microsoft.Win32.RegistryValueKind]::DWord)}
        else{$key.DeleteValue('LegacyDefaultPrinterMode',$false)}
        $key.Flush()
    }finally{if($key){$key.Dispose()};$root.Dispose()}
}
function Get-DeployRegisteredDefaultApps {
    $apps=@();$seen=@{}
    foreach($scope in 'User','Machine') {
        $hive=if($scope -eq 'User'){[Microsoft.Win32.RegistryHive]::CurrentUser}else{[Microsoft.Win32.RegistryHive]::LocalMachine}
        $views=if([Environment]::Is64BitOperatingSystem){@([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)}else{@([Microsoft.Win32.RegistryView]::Registry32)}
        foreach($view in $views){
            $root=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view);$registered=$null
            try{
                $registered=$root.OpenSubKey('SOFTWARE\RegisteredApplications')
                if(-not $registered){continue}
                foreach($name in $registered.GetValueNames()){
                    $id=$scope+'|'+$name
                    if($seen.ContainsKey($id)){continue}
                    $cap=$null;$urls=$null;$files=$null
                    try{
                        $path=[string]$registered.GetValue($name)
                        if(-not $path -or $path.StartsWith('\')){continue}
                        $cap=$root.OpenSubKey($path);if(-not $cap){continue}
                        $urls=$cap.OpenSubKey('URLAssociations');$files=$cap.OpenSubKey('FileAssociations')
                        $http=if($urls){[string]$urls.GetValue('http')}else{''}
                        $https=if($urls){[string]$urls.GetValue('https')}else{''}
                        $pdf=if($files){[string]$files.GetValue('.pdf')}else{''}
                        if(-not (($http -and $https) -or $pdf)){continue}
                        $label=[string]$cap.GetValue('ApplicationName')
                        if(-not $label -or $label.StartsWith('@')){$label=$name}
                        $apps+=[pscustomobject]@{Name=$name;Scope=$scope;Display=($label+$(if($scope -eq 'User'){' (tài khoản này)'}else{''}));Http=$http;Https=$https;Pdf=$pdf}
                        $seen[$id]=$true
                    }finally{if($files){$files.Dispose()};if($urls){$urls.Dispose()};if($cap){$cap.Dispose()}}
                }
            }finally{if($registered){$registered.Dispose()};$root.Dispose()}
        }
    }
    @($apps | Sort-Object Display)
}
function Get-DeployCurrentAssociation([ValidateSet('http','https','.pdf')][string]$Association) {
    Initialize-DeployDefaultsNative
    [TechMaster.DefaultsNative]::Association($Association,($Association -ne '.pdf'))
}
function Get-DeployDefaultsSnapshot {
    $printerError='';$appError='';$default='';$printers=@();$apps=@();$management=$null
    try{$printers=@(Get-Printer -ErrorAction Stop | Select-Object Name,DriverName,PortName);$default=Get-DeployDefaultPrinter;$management=Get-DeployPrinterManagement}catch{$printerError=$_.Exception.GetBaseException().Message}
    $offline=@();$offlineError='';$offlineDeviceError=''
    if(-not $printerError){try{$cleanupScan=Get-DeployPrinterOfflineScan;$offline=@($cleanupScan.Rows);$offlineDeviceError=[string]$cleanupScan.DeviceError}catch{$offlineError=$_.Exception.GetBaseException().Message}}
    try{$apps=@(Get-DeployRegisteredDefaultApps)}catch{$appError=$_.Exception.GetBaseException().Message}
    $associations=@{}
    foreach($name in 'http','https','.pdf'){
        try{$associations[$name]=[pscustomobject]@{Readable=$true;ProgId=(Get-DeployCurrentAssociation $name);Error=''}}
        catch{$associations[$name]=[pscustomobject]@{Readable=$false;ProgId='';Error=$_.Exception.GetBaseException().Message}}
    }
    [pscustomobject]@{User=[Environment]::UserName;Printers=$printers;DefaultPrinter=$default;Management=$management;PrinterError=$printerError;OfflinePrinters=$offline;OfflineError=$offlineError;OfflineDeviceError=$offlineDeviceError;Apps=$apps;AppError=$appError;Associations=$associations}
}
function Get-DeployAssociationLabel($Association,$Apps,[string]$Field) {
    if(-not $Association.Readable){return 'Chưa đọc được thiết lập'}
    if(-not $Association.ProgId){return 'Chưa có ứng dụng mặc định'}
    $app=$Apps | Where-Object {$_.$Field -eq $Association.ProgId} | Select-Object -First 1
    if($app){return [string]$app.Display}
    return [string]$Association.ProgId
}
function Test-DeployDefaultAppChoice($App,[ValidateSet('Browser','Pdf')][string]$Kind,$Snapshot) {
    $fields=if($Kind -eq 'Browser'){@{http='Http';https='Https'}}else{@{'.pdf'='Pdf'}}
    foreach($association in $fields.Keys){
        $actual=$Snapshot.Associations[$association];$expected=[string]$App.($fields[$association])
        if(-not $expected -or -not $actual.Readable -or $actual.ProgId -ne $expected){return $false}
    }
    return $true
}
function Open-DeployDefaultAppSettings($App,[ValidateSet('Browser','Pdf')][string]$Kind,[string]$LogPath) {
    # Re-read registrations so a stale/custom object cannot launch an arbitrary URI.
    $valid=@(Get-DeployRegisteredDefaultApps | Where-Object {$_.Name -ceq $App.Name -and $_.Scope -ceq $App.Scope})
    if($valid.Count -ne 1){throw 'Ứng dụng không còn đăng ký trong Windows. Bấm Kiểm tra lại sau khi cài ứng dụng.'}
    $choice=$valid[0]
    if(($Kind -eq 'Browser' -and (-not $choice.Http -or -not $choice.Https)) -or ($Kind -eq 'Pdf' -and -not $choice.Pdf)){throw 'Ứng dụng chưa đăng ký hỗ trợ loại mặc định này.'}
    $parameter=if($choice.Scope -eq 'User'){'registeredAppUser'}else{'registeredAppMachine'}
    $uri='ms-settings:defaultapps?'+$parameter+'='+[uri]::EscapeDataString([string]$choice.Name)
    Write-DeployWindowsToolsLog $LogPath 'open-default-app-settings' @{User=[Environment]::UserName;Kind=$Kind;App=$choice.Name;Scope=$choice.Scope;Uri=$uri}
    try{Start-Process -FilePath $uri -ErrorAction Stop | Out-Null}
    catch{Start-Process -FilePath 'ms-settings:defaultapps' -ErrorAction Stop | Out-Null}
    [pscustomobject]@{Message='Đã mở thiết lập của '+$choice.Display+'. Chọn Set default / Đặt mặc định trong Windows, rồi quay lại bấm Kiểm tra lại. Với PDF, chọn mặc định cho .pdf; trình duyệt cần cả HTTP và HTTPS.';Kind='Attention';Log=$LogPath}
}
function Set-DeployPrinterDefaults([string]$Name,[bool]$A4,[bool]$Default,[string]$LogPath) {
    Assert-DeployPrinterAdmin
    if(-not $A4 -and -not $Default){throw 'Chọn Đặt A4 hoặc Đặt máy in mặc định trước khi áp dụng.'}
    if([string]::IsNullOrWhiteSpace($Name)){throw 'Chọn một máy in đã cài đặt.'}
    $matches=@(Get-Printer -ErrorAction Stop | Where-Object {$_.Name -ceq $Name})
    if($matches.Count -ne 1){throw 'Máy in đã chọn không còn tồn tại hoặc tên không xác định được duy nhất. Bấm Kiểm tra lại.'}
    Write-DeployWindowsToolsLog $LogPath 'printer-request' @{User=[Environment]::UserName;Printer=$Name;A4=$A4;Default=$Default}
    $messages=@();$errors=@()
    if($A4){
        try{
            $before=Get-PrintConfiguration -PrinterName $Name -ErrorAction Stop
            Write-DeployWindowsToolsLog $LogPath 'paper-before' @{Printer=$Name;PaperSize=[string]$before.PaperSize}
            if([string]$before.PaperSize -ne 'A4'){Set-PrintConfiguration -PrinterName $Name -PaperSize A4 -ErrorAction Stop}
            $after=Get-PrintConfiguration -PrinterName $Name -ErrorAction Stop
            Write-DeployWindowsToolsLog $LogPath 'paper-after' @{Printer=$Name;PaperSize=[string]$after.PaperSize}
            if([string]$after.PaperSize -ne 'A4'){throw 'Driver chưa nhận khổ A4; mở Tuỳ chọn in để chọn khổ được driver hỗ trợ.'}
            $messages+='Đã xác nhận khổ A4 cho '+$Name+'.'
        }catch{$errors+='Khổ A4: '+$_.Exception.GetBaseException().Message;Write-DeployWindowsToolsLog $LogPath 'paper-failed' $_.Exception.GetBaseException().Message}
    }
    if($Default){
        $oldManagement=$null;$managementWritten=$false
        try{
            $oldDefault=Get-DeployDefaultPrinter;$oldManagement=Get-DeployPrinterManagement
            Write-DeployWindowsToolsLog $LogPath 'default-printer-before' @{Printer=$oldDefault;Management=$oldManagement}
            if($oldManagement.Present -and ($oldManagement.Kind -ne 'DWord' -or $oldManagement.Value -notin 0,1)){throw 'Cấu hình quản lý máy in đang có kiểu / giá trị khác; chưa ghi đè.'}
            # Keep the explicit user choice rather than allowing Windows to choose the last-used queue.
            Set-DeployPrinterManagement ([pscustomobject]@{Present=$true;Value=1;Kind='DWord'});$managementWritten=$true
            if($oldDefault -cne $Name){Set-DeployDefaultPrinterNative $Name}
            $actual=Get-DeployDefaultPrinter;$mode=Get-DeployPrinterManagement
            Write-DeployWindowsToolsLog $LogPath 'default-printer-after' @{Printer=$actual;Management=$mode}
            if($actual -cne $Name -or -not $mode.Present -or $mode.Value -ne 1){throw 'Windows chưa xác nhận máy in mặc định đã chọn.'}
            $messages+='Đã đặt máy in mặc định cho tài khoản đang chạy app và tắt Windows tự quản lý máy in.'
        }catch{
            $failure=$_.Exception.GetBaseException().Message
            if($managementWritten){
                try{Set-DeployPrinterManagement $oldManagement;Write-DeployWindowsToolsLog $LogPath 'printer-management-restored' $oldManagement}
                catch{$failure+=' Không khôi phục được tuỳ chọn tự quản lý: '+$_.Exception.GetBaseException().Message}
            }
            $errors+='Máy in mặc định: '+$failure
            Write-DeployWindowsToolsLog $LogPath 'default-printer-failed' $failure
        }
    }
    [pscustomobject]@{Message=(@($messages)+@($errors) -join "`n");Kind=$(if($errors.Count){if($messages.Count){'Attention'}else{'Error'}}else{'Success'});Log=$LogPath}
}
# Offline printer cleanup ("Remove device" in Devices and Printers, drivers kept).
# Devices and Printers lists device containers, not spooler queues: an unplugged USB printer keeps
# non-present PnP nodes (print queue, USBPRINT, USB) that still show after the queue is deleted.
# Only queues on a USB / network port that Windows reports offline, and printer device containers
# whose every node is disconnected, are listed. Virtual printers (PDF, XPS, OneNote, Fax, FILE:,
# PORTPROMPT:, nul:) never are. Connected device nodes are never removed; driver packages stay.
$script:DeployComputerContainer='00000000-0000-0000-ffff-ffffffffffff'
$script:DeployPrinterWaitSeconds=2
$script:DeployPendingWaitSeconds=5
function Get-DeployPrinterPortKind($Queue,$Ports) {
    $port=[string]$Queue.PortName
    if($port -match '^USB\d+$'){return 'USB'}
    if([string]$Queue.Type -eq 'Connection'){return 'Network'}
    if($port -match '^(IP_|WSD-|https?://|\\\\)' -or $port -match '^\d{1,3}(\.\d{1,3}){3}(_\d+)?$'){return 'Network'}
    if($port -and $Ports -and $Ports.ContainsKey($port) -and [string]$Ports[$port].PrinterHostAddress){return 'Network'}
    return ''
}
function Test-DeployPrinterOffline($Queue,$Wmi) {
    # PendingDeletion: a queue Windows has not finished deleting (open handles, stuck jobs) stays listed for retry.
    if([string]$Queue.PrinterStatus -match 'Offline|PendingDeletion'){return $true}
    if(-not $Wmi){return $false}
    # Windows shows a queue as Offline from the spooler status or from Use Printer Offline (WorkOffline).
    return [bool]($Wmi.WorkOffline -eq $true -or [int]$Wmi.PrinterStatus -eq 7 -or [int]$Wmi.ExtendedPrinterStatus -eq 7 -or [int]$Wmi.DetectedErrorState -eq 9)
}
function Get-DeployOfflinePrinterRows($Queues,$Wmi,$Ports,[string]$DefaultPrinter) {
    $rows=@()
    foreach($queue in @($Queues)){
        if(-not $queue){continue}
        $name=[string]$queue.Name
        if(-not $name){continue}
        $kind=Get-DeployPrinterPortKind $queue $Ports
        if(-not $kind){continue}
        $info=$null
        if($Wmi -and $Wmi.ContainsKey($name)){$info=$Wmi[$name]}
        if(-not (Test-DeployPrinterOffline $queue $info)){continue}
        $isDefault=[bool]($DefaultPrinter -and $name -ceq $DefaultPrinter)
        $shared=[bool]($queue.Shared -eq $true)
        $jobs=0;[void][int]::TryParse([string]$queue.JobCount,[ref]$jobs)
        $parts=@($(if($kind -eq 'USB'){'USB'}else{'Mạng'}),('cổng '+[string]$queue.PortName))
        if([string]$queue.DriverName){$parts+=('driver '+[string]$queue.DriverName)}
        if([string]$queue.PrinterStatus -match 'PendingDeletion'){$parts+='Windows chưa xoá xong'}
        if($kind -eq 'Network'){$parts+='máy in mạng có thể chỉ đang tắt hoặc khác mạng'}
        if($isDefault){$parts+='đang là máy in mặc định'}
        if($shared){$parts+='đang chia sẻ cho máy khác'}
        if($jobs -gt 0){$parts+=('còn '+$jobs+' lệnh in sẽ bị huỷ')}
        $rows+=[pscustomobject]@{Key=$name;Name=$name;DriverName=[string]$queue.DriverName;PortName=[string]$queue.PortName;Kind=$kind;IsDefault=$isDefault;Shared=$shared;JobCount=$jobs;ContainerId='';InstanceId='';Selected=[bool]($kind -eq 'USB' -and -not $isDefault -and -not $shared);Detail=($parts -join ' · ')}
    }
    # USB first: unplugged printers and "(Copy n)" duplicates are the usual leftovers.
    @($rows | Sort-Object -Property @{Expression={if($_.Kind -eq 'USB'){0}else{1}}},@{Expression={$_.Name}})
}
function ConvertTo-DeployContainerId($Value) {([string]$Value).Trim().Trim('{','}').ToLowerInvariant()}
function Get-DeployPnpDevices {Initialize-DeployDefaultsNative;@([TechMaster.DefaultsNative]::Devices())}
function Get-DeployDevicePortName([string]$InstanceId) {
    try{[string](Get-ItemProperty -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$InstanceId+'\Device Parameters') -Name PortName -ErrorAction Stop).PortName}catch{''}
}
function Get-DeployPrinterDeviceMap {
    foreach($node in @(Get-DeployPnpDevices)){
        if(-not $node -or -not [string]$node.InstanceId){continue}
        $id=[string]$node.InstanceId;$port=''
        # USBPRINT\...\Device Parameters\PortName ties an unplugged printer to its USB00x queue port.
        if(-not $node.Present -and $id -like 'USBPRINT\*'){$port=Get-DeployDevicePortName $id}
        [pscustomobject]@{InstanceId=$id;Class=[string]$node.Class;FriendlyName=[string]$node.FriendlyName;Present=[bool]$node.Present;ContainerId=(ConvertTo-DeployContainerId $node.ContainerId);Parent=[string]$node.Parent;PortName=$port}
    }
}
function Get-DeployQueueContainers($Queue,$Devices) {
    # Both the queue's own node and the USBPRINT node on its port: Windows usually puts them in one
    # container, but if not, both must go for the printer to leave Devices and Printers.
    $found=@();$name=[string]$Queue.Name;$port=[string]$Queue.PortName
    $hits=@($Devices | Where-Object {$_.Class -eq 'PrintQueue' -and $_.FriendlyName -ceq $name -and $_.ContainerId})
    if($hits.Count -gt 1){$hits=@($hits | Where-Object {$_.Present})}
    if($hits.Count -eq 1){$found+=[string]$hits[0].ContainerId}
    if($port -match '^USB\d+$'){
        $hits=@($Devices | Where-Object {$_.PortName -and $_.PortName -ieq $port -and $_.ContainerId})
        if($hits.Count -eq 1){$found+=[string]$hits[0].ContainerId}
    }
    @($found | Select-Object -Unique)
}
function Get-DeployQueueContainer($Queue,$Devices) {[string]@(Get-DeployQueueContainers $Queue $Devices)[0]}
function Get-DeployDeviceDepth($Node,$ById) {
    $depth=0;$parent=[string]$Node.Parent
    while($parent -and $ById.ContainsKey($parent) -and $depth -lt 32){$depth++;$parent=[string]$ById[$parent].Parent}
    return $depth
}
function Get-DeployContainerRemovalPlan([string]$ContainerId,$Devices,[string[]]$KeepQueues,[string[]]$KeepPorts) {
    # Never the computer's own container: it holds the PC's internal (and old internal) devices.
    if(-not $ContainerId -or $ContainerId -eq $script:DeployComputerContainer){return [pscustomobject]@{Nodes=@();Reason='no-device'}}
    $members=@($Devices | Where-Object {$_.ContainerId -eq $ContainerId})
    if(-not $members.Count){return [pscustomobject]@{Nodes=@();Reason='no-device'}}
    # The queue's own print-queue node is present until the queue is deleted; any other connected node keeps the device.
    if(@($members | Where-Object {$_.Present -and $_.Class -ne 'PrintQueue'}).Count){return [pscustomobject]@{Nodes=@();Reason='connected'}}
    $keepQueues=@($KeepQueues);$keepPorts=@($KeepPorts)
    if(@($members | Where-Object {($_.Class -eq 'PrintQueue' -and $keepQueues -ccontains $_.FriendlyName) -or ($_.PortName -and $keepPorts -icontains $_.PortName)}).Count){return [pscustomobject]@{Nodes=@();Reason='shared'}}
    $byId=@{};foreach($member in $members){$byId[$member.InstanceId]=$member}
    # Children first (USBPRINT before its USB parent).
    $ordered=@($members | Sort-Object -Property @{Expression={Get-DeployDeviceDepth $_ $byId};Descending=$true},@{Expression={switch($_.Class){'PrintQueue'{0}'Printer'{1}'USB'{3}default{2}}}})
    [pscustomobject]@{Nodes=$ordered;Reason=''}
}
function Get-DeployOrphanPrinterRows($Devices,$Queues) {
    # Printer devices whose queue is already gone but which Devices and Printers still shows.
    $queueNames=@($Queues | ForEach-Object {[string]$_.Name})
    $queuePorts=@($Queues | ForEach-Object {[string]$_.PortName} | Where-Object {$_})
    $rows=@()
    $printerNodes=@($Devices | Where-Object {$_.Class -in 'Printer','PrintQueue'})
    foreach($container in @($printerNodes | Where-Object {$_.ContainerId -and $_.ContainerId -ne $script:DeployComputerContainer} | ForEach-Object {$_.ContainerId} | Select-Object -Unique)){
        $members=@($Devices | Where-Object {$_.ContainerId -eq $container})
        if(@($members | Where-Object {$_.Present}).Count){continue}
        if(@($members | Where-Object {($_.Class -eq 'PrintQueue' -and $queueNames -ccontains $_.FriendlyName) -or ($_.PortName -and $queuePorts -icontains $_.PortName)}).Count){continue}
        $label=@($members | Where-Object {$_.Class -eq 'PrintQueue' -and $_.FriendlyName} | ForEach-Object {$_.FriendlyName})[0]
        if(-not $label){$label=@($members | Where-Object {$_.Class -eq 'Printer' -and $_.FriendlyName} | ForEach-Object {$_.FriendlyName})[0]}
        if(-not $label){$label=@($members | Where-Object {$_.FriendlyName} | ForEach-Object {$_.FriendlyName})[0]}
        if(-not $label){$label='Thiết bị máy in không tên'}
        $port=[string]@($members | Where-Object {$_.PortName} | ForEach-Object {$_.PortName})[0]
        $rows+=[pscustomobject]@{Key=('device:'+$container);Name=[string]$label;DriverName='';PortName=$port;Kind='Device';IsDefault=$false;Shared=$false;JobCount=0;ContainerId=$container;InstanceId='';Selected=$true;Detail=('Thiết bị còn sót: không còn hàng đợi in nhưng vẫn hiện trong Devices and Printers'+$(if($port){' · cổng '+$port}else{''})+' · '+$members.Count+' mục thiết bị ẩn')}
    }
    # A leftover print-queue node outside any printer container (for example in the computer's own container).
    foreach($node in @($printerNodes | Where-Object {$_.Class -eq 'PrintQueue' -and -not $_.Present -and (-not $_.ContainerId -or $_.ContainerId -eq $script:DeployComputerContainer) -and -not ($queueNames -ccontains $_.FriendlyName)})){
        $rows+=[pscustomobject]@{Key=('node:'+$node.InstanceId);Name=$(if($node.FriendlyName){[string]$node.FriendlyName}else{[string]$node.InstanceId});DriverName='';PortName='';Kind='Device';IsDefault=$false;Shared=$false;JobCount=0;ContainerId='';InstanceId=[string]$node.InstanceId;Selected=$true;Detail='Hàng đợi in còn sót trong danh sách thiết bị · 1 mục thiết bị ẩn'}
    }
    @($rows | Sort-Object -Property Name)
}
function Get-DeployPrinterOfflineScan {
    $queues=@(Get-Printer -ErrorAction Stop)
    # A failed CIM / port / device query only narrows detection; it never adds an entry to the list.
    $wmi=@{}
    try{foreach($item in @(Get-CimInstance -ClassName Win32_Printer -OperationTimeoutSec 20 -ErrorAction Stop)){if($item){$wmi[[string]$item.Name]=$item}}}catch{$wmi=@{}}
    $ports=@{}
    try{foreach($item in @(Get-PrinterPort -ErrorAction Stop)){if($item){$ports[[string]$item.Name]=$item}}}catch{$ports=@{}}
    $default='';try{$default=[string](Get-DeployDefaultPrinter)}catch{$default=''}
    $devices=@();$deviceError=''
    try{$devices=@(Get-DeployPrinterDeviceMap)}catch{$devices=@();$deviceError=$_.Exception.GetBaseException().Message}
    $rows=@(Get-DeployOfflinePrinterRows $queues $wmi $ports $default)+@(Get-DeployOrphanPrinterRows $devices $queues)
    [pscustomobject]@{Queues=$queues;Rows=$rows;DefaultPrinter=$default;Devices=$devices;DeviceError=$deviceError}
}
function Get-DeployOfflineRemovalPrompt($Rows,[bool]$RestartSpooler=$false) {
    $rows=@($Rows | Where-Object {$_})
    $lines=@($rows | ForEach-Object {'• '+$_.Name+' ('+$(switch($_.Kind){'USB'{'USB, cổng '+$_.PortName}'Network'{'mạng, cổng '+$_.PortName}default{'thiết bị còn sót'}})+')'})
    $message='Gỡ '+$rows.Count+' máy in không kết nối khỏi Windows?'+"`n`n"+($lines -join "`n")
    $message+="`n`nXoá hàng đợi in và thiết bị, giống Remove device trong Devices and Printers. Driver vẫn giữ trong máy: cắm lại máy in USB hoặc thêm lại máy in mạng khi cần dùng."
    $warnings=@()
    if(@($rows | Where-Object {$_.IsDefault}).Count){$warnings+='Có máy in mặc định trong danh sách; Windows sẽ chọn máy in mặc định khác hoặc để trống.'}
    if(@($rows | Where-Object {$_.Shared}).Count){$warnings+='Có máy in đang chia sẻ; máy khác dùng chung sẽ mất máy in này.'}
    $jobs=0;foreach($row in $rows){$jobs+=[int]$row.JobCount}
    if($jobs -gt 0){$warnings+=('Còn '+$jobs+' lệnh in đang chờ sẽ bị huỷ.')}
    if(@($rows | Where-Object {$_.Kind -eq 'Network'}).Count){$warnings+='Máy in mạng có thể chỉ đang tắt hoặc máy đang ở mạng khác.'}
    if($RestartSpooler){$warnings+='Nếu Windows chưa xoá xong (thường do cửa sổ Devices and Printers đang mở), app sẽ khởi động lại dịch vụ Print Spooler; lệnh in đang in dở trên máy in khác có thể phải in lại.'}
    if($warnings.Count){$message+="`n`nLưu ý:`n"+(@($warnings | ForEach-Object {'• '+$_}) -join "`n")}
    return $message
}
function Set-DeployCleanupProgress($Progress,[int]$Index,[string]$Current,[string]$Step) {
    if(-not $Progress){return}
    $Progress.Index=$Index;$Progress.Current=$Current;$Progress.Step=$Step
    $total=[Math]::Max(1,[int]$Progress.Total)
    $Progress.Percent=[Math]::Min(99,[int](100*[Math]::Max(0,$Index-1)/$total))
}
function Add-DeployCleanupLine($Progress,$Lines,[string]$Text) {
    [void]$Lines.Add($Text)
    if($Progress){[void]$Progress.Lines.Add($Text)}
}
function Remove-DeployPhantomDevice([string]$InstanceId) {
    Initialize-DeployDefaultsNative
    for($attempt=1;;$attempt++){
        try{return [TechMaster.DefaultsNative]::RemovePhantomDevice($InstanceId)}
        catch{
            # The spooler may need a moment to drop the deleted queue's own device node.
            if($attempt -ge 4 -or $_.Exception.GetBaseException().Message -notmatch 'connected'){throw}
            Start-Sleep -Milliseconds 500
        }
    }
}
function Remove-DeployDeviceNodes($Nodes,[string]$LogPath,[string]$Label) {
    $removed=0;$errors=@()
    foreach($node in @($Nodes)){
        try{
            $gone=Remove-DeployPhantomDevice $node.InstanceId
            if($gone){$removed++}
            Write-DeployWindowsToolsLog $LogPath 'device-node-removed' @{Printer=$Label;InstanceId=$node.InstanceId;Class=$node.Class;Removed=[bool]$gone}
        }catch{
            $failure=$_.Exception.GetBaseException().Message
            $errors+=($node.InstanceId+': '+$failure)
            Write-DeployWindowsToolsLog $LogPath 'device-node-failed' @{Printer=$Label;InstanceId=$node.InstanceId;Class=$node.Class;Error=$failure}
        }
    }
    [pscustomobject]@{Removed=$removed;Errors=$errors}
}
function Get-DeployRemainingPrinters([string[]]$Names,[double]$Seconds=0) {
    $deadline=(Get-Date).AddSeconds($Seconds)
    while($true){
        $left=@(Get-Printer -ErrorAction Stop | Where-Object {$Names -ccontains [string]$_.Name} | ForEach-Object {[string]$_.Name})
        if(-not $left.Count -or (Get-Date) -ge $deadline){return $left}
        Start-Sleep -Milliseconds 400
    }
}
function Clear-DeployPrinterJobs($Queue,[string]$LogPath) {
    # A queue that still has jobs is only marked for deletion; offline printers never finish them.
    $removed=0
    try{
        foreach($job in @(Get-PrintJob -PrinterObject $Queue -ErrorAction Stop)){
            if(-not $job){continue}
            try{Remove-PrintJob -InputObject $job -ErrorAction Stop;$removed++}
            catch{Write-DeployWindowsToolsLog $LogPath 'print-job-remove-failed' @{Printer=[string]$Queue.Name;Error=$_.Exception.GetBaseException().Message}}
        }
    }catch{Write-DeployWindowsToolsLog $LogPath 'print-job-read-failed' @{Printer=[string]$Queue.Name;Error=$_.Exception.GetBaseException().Message}}
    return $removed
}
function Get-DeployQueueOutcome([string]$Label,$Step) {
    if(@($Step.Errors).Count){return [pscustomobject]@{State='partial';Line=('! '+$Label+' — đã xoá hàng đợi; chưa xoá được '+@($Step.Errors).Count+' mục thiết bị: '+(@($Step.Errors) -join '; '))}}
    switch($Step.Reason){
        'connected'{return [pscustomobject]@{State='partial';Line=('! '+$Label+' — đã xoá hàng đợi; thiết bị đang kết nối nên giữ nguyên')}}
        'shared'{return [pscustomobject]@{State='done';Line=('✓ '+$Label+' — đã xoá hàng đợi; giữ thiết bị vì máy in khác còn dùng')}}
        'no-device'{return [pscustomobject]@{State='done';Line=('✓ '+$Label+' — đã xoá hàng đợi (không có thiết bị đi kèm)')}}
    }
    if(-not $Step.Removed){return [pscustomobject]@{State='done';Line=('✓ '+$Label+' — đã xoá hàng đợi; Windows đã tự xoá thiết bị')}}
    [pscustomobject]@{State='done';Line=('✓ '+$Label+' — đã xoá hàng đợi và '+$Step.Removed+' mục thiết bị')}
}
function Invoke-DeployPrinterDeviceStep([string]$Label,[string[]]$ContainerIds,$Devices,$Keep,[string]$LogPath,$Progress,[int]$Index) {
    $removed=0;$errors=@();$reasons=@();$attempted=@()
    foreach($container in @($ContainerIds | Where-Object {$_})){
        $plan=Get-DeployContainerRemovalPlan $container $Devices $Keep.Queues $Keep.Ports
        if(-not @($plan.Nodes).Count){$reasons+=$plan.Reason;continue}
        Set-DeployCleanupProgress $Progress $Index $Label 'xoá thiết bị'
        $result=Remove-DeployDeviceNodes $plan.Nodes $LogPath $Label
        $removed+=$result.Removed;$errors+=@($result.Errors);$attempted+=$container
    }
    $reason=if($attempted.Count){''}elseif($reasons -contains 'connected'){'connected'}elseif($reasons -contains 'shared'){'shared'}else{'no-device'}
    [pscustomobject]@{Removed=$removed;Errors=$errors;Reason=$reason;Attempted=$attempted}
}
function Remove-DeployOfflinePrinters([string[]]$Names,[string]$LogPath,$Progress=$null,[switch]$RestartSpooler) {
    Assert-DeployPrinterAdmin
    $requested=@($Names | Where-Object {-not [string]::IsNullOrWhiteSpace($_)} | Select-Object -Unique)
    if(-not $requested.Count){throw 'Chọn ít nhất một máy in không kết nối để gỡ.'}
    if($Progress){$Progress.Total=$requested.Count}
    Set-DeployCleanupProgress $Progress 0 '' 'Đang đọc lại máy in và thiết bị…'
    # Re-read everything: a printer reconnected after the list was shown is skipped, never removed.
    $scan=Get-DeployPrinterOfflineScan
    $devices=@($scan.Devices)
    $kept=@($scan.Queues | Where-Object {$requested -cnotcontains [string]$_.Name})
    $keep=[pscustomobject]@{Queues=@($kept | ForEach-Object {[string]$_.Name});Ports=@($kept | ForEach-Object {[string]$_.PortName} | Where-Object {$_})}
    Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-request' @{User=[Environment]::UserName;Requested=$requested;Listed=@($scan.Rows | ForEach-Object {$_.Key});DefaultPrinter=$scan.DefaultPrinter;DeviceError=$scan.DeviceError;RestartSpooler=[bool]$RestartSpooler}
    $lines=New-Object Collections.ArrayList
    $done=@();$partial=@();$skipped=@();$failed=@();$pending=@();$verify=@{};$index=0
    foreach($key in $requested){
        $index++
        $match=@($scan.Rows | Where-Object {$_.Key -ceq $key})
        $label=if($match.Count){[string]$match[0].Name}else{[string]$key}
        Set-DeployCleanupProgress $Progress $index $label 'kiểm tra'
        if($match.Count -ne 1){
            $skipped+=$label
            Add-DeployCleanupLine $Progress $lines ('– '+$label+' — bỏ qua: đã kết nối lại hoặc không còn trong Windows')
            Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-skipped' @{Key=$key;Reason='not-listed'}
            continue
        }
        $row=$match[0]
        try{
            if($row.Kind -eq 'Device'){
                $plan=if($row.ContainerId){Get-DeployContainerRemovalPlan $row.ContainerId $devices $keep.Queues $keep.Ports}else{[pscustomobject]@{Nodes=@($devices | Where-Object {$_.InstanceId -ieq $row.InstanceId -and -not $_.Present});Reason='no-device'}}
                if(-not @($plan.Nodes).Count){
                    $skipped+=$label
                    $reason=switch($plan.Reason){'connected'{'thiết bị đang kết nối'}'shared'{'máy in khác còn dùng thiết bị này'}default{'không còn thiết bị'}}
                    Add-DeployCleanupLine $Progress $lines ('– '+$label+' — bỏ qua: '+$reason)
                    Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-skipped' @{Key=$key;Reason=$plan.Reason}
                    continue
                }
                Write-DeployWindowsToolsLog $LogPath 'device-remove-before' @{Row=$row;Nodes=@($plan.Nodes)}
                Set-DeployCleanupProgress $Progress $index $label 'xoá thiết bị'
                $result=Remove-DeployDeviceNodes $plan.Nodes $LogPath $label
                if($row.ContainerId){$verify[$label]=@($row.ContainerId)}
                if(@($result.Errors).Count){$partial+=$label;Add-DeployCleanupLine $Progress $lines ('! '+$label+' — chưa xoá được '+@($result.Errors).Count+' mục thiết bị: '+(@($result.Errors) -join '; '))}
                else{$done+=$label;Add-DeployCleanupLine $Progress $lines ('✓ '+$label+' — đã xoá '+$result.Removed+' mục thiết bị còn sót')}
                continue
            }
            $queue=@($scan.Queues | Where-Object {$_.Name -ceq $row.Name})
            if($queue.Count -ne 1){
                $skipped+=$label
                Add-DeployCleanupLine $Progress $lines ('– '+$label+' — bỏ qua: không còn trong Windows')
                Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-skipped' @{Key=$key;Reason='missing'}
                continue
            }
            $containers=@(Get-DeployQueueContainers $queue[0] $devices)
            Write-DeployWindowsToolsLog $LogPath 'printer-remove-before' @{Row=$row;ContainerIds=$containers}
            Set-DeployCleanupProgress $Progress $index $label 'huỷ lệnh in chờ'
            $jobs=Clear-DeployPrinterJobs $queue[0] $LogPath
            Set-DeployCleanupProgress $Progress $index $label 'xoá hàng đợi in'
            # Pass the exact spooler object: names may contain wildcard characters such as [ ].
            Remove-Printer -InputObject $queue[0] -ErrorAction Stop
            Set-DeployCleanupProgress $Progress $index $label 'chờ Windows xoá hàng đợi'
            if(@(Get-DeployRemainingPrinters @($row.Name) $script:DeployPrinterWaitSeconds).Count){
                $pending+=[pscustomobject]@{Label=$label;Name=[string]$row.Name;ContainerIds=$containers}
                Add-DeployCleanupLine $Progress $lines ('… '+$label+' — Windows chưa xoá xong hàng đợi, sẽ kiểm tra lại')
                Write-DeployWindowsToolsLog $LogPath 'printer-remove-pending' @{Printer=$label;JobsRemoved=$jobs}
                continue
            }
            $step=Invoke-DeployPrinterDeviceStep $label $containers $devices $keep $LogPath $Progress $index
            if(@($step.Attempted).Count){$verify[$label]=@($step.Attempted)}
            $outcome=Get-DeployQueueOutcome $label $step
            if($outcome.State -eq 'partial'){$partial+=$label}else{$done+=$label}
            Add-DeployCleanupLine $Progress $lines $outcome.Line
        }catch{
            $failure=$_.Exception.GetBaseException().Message
            $failed+=($label+': '+$failure)
            Add-DeployCleanupLine $Progress $lines ('✗ '+$label+' — lỗi: '+$failure)
            Write-DeployWindowsToolsLog $LogPath 'printer-remove-failed' @{Printer=$label;Error=$failure}
        }
    }
    $spoolerError=''
    if($pending.Count){
        Set-DeployCleanupProgress $Progress $requested.Count '' 'Đang chờ Windows xoá các hàng đợi còn lại…'
        $left=@()
        try{
            $left=@(Get-DeployRemainingPrinters @($pending | ForEach-Object {$_.Name}) $script:DeployPendingWaitSeconds)
            if($left.Count -and $RestartSpooler){
                Set-DeployCleanupProgress $Progress $requested.Count '' 'Đang khởi động lại dịch vụ Print Spooler…'
                try{Restart-Service -Name Spooler -Force -ErrorAction Stop;Write-DeployWindowsToolsLog $LogPath 'spooler-restarted' @{Pending=$left}}
                catch{$spoolerError=$_.Exception.GetBaseException().Message;Write-DeployWindowsToolsLog $LogPath 'spooler-restart-failed' $spoolerError}
                if(-not $spoolerError){
                    $left=@(Get-DeployRemainingPrinters $left $script:DeployPrinterWaitSeconds)
                    foreach($name in @($left)){
                        try{
                            $again=@(Get-Printer -ErrorAction Stop | Where-Object {$_.Name -ceq $name})
                            if($again.Count -eq 1){[void](Clear-DeployPrinterJobs $again[0] $LogPath);Remove-Printer -InputObject $again[0] -ErrorAction Stop}
                        }catch{Write-DeployWindowsToolsLog $LogPath 'printer-remove-retry-failed' @{Printer=$name;Error=$_.Exception.GetBaseException().Message}}
                    }
                    $left=@(Get-DeployRemainingPrinters $left $script:DeployPrinterWaitSeconds)
                }
            }
        }catch{$left=@($pending | ForEach-Object {$_.Name});Write-DeployWindowsToolsLog $LogPath 'printer-pending-check-failed' $_.Exception.GetBaseException().Message}
        $finished=@($pending | Where-Object {$left -cnotcontains $_.Name})
        if($finished.Count){try{$devices=@(Get-DeployPrinterDeviceMap)}catch{Write-DeployWindowsToolsLog $LogPath 'device-map-failed' $_.Exception.GetBaseException().Message}}
        foreach($entry in $finished){
            try{
                $step=Invoke-DeployPrinterDeviceStep $entry.Label @($entry.ContainerIds) $devices $keep $LogPath $Progress $requested.Count
                if(@($step.Attempted).Count){$verify[$entry.Label]=@($step.Attempted)}
                $outcome=Get-DeployQueueOutcome $entry.Label $step
                if($outcome.State -eq 'partial'){$partial+=$entry.Label}else{$done+=$entry.Label}
                Add-DeployCleanupLine $Progress $lines $outcome.Line
            }catch{
                $failure=$_.Exception.GetBaseException().Message
                $failed+=($entry.Label+': '+$failure)
                Add-DeployCleanupLine $Progress $lines ('✗ '+$entry.Label+' — lỗi: '+$failure)
            }
        }
        $pending=@($pending | Where-Object {$left -ccontains $_.Name})
        foreach($entry in $pending){Add-DeployCleanupLine $Progress $lines ('! '+$entry.Label+' — Windows vẫn chưa xoá xong hàng đợi')}
    }
    $verifyError=''
    if($verify.Count){
        Set-DeployCleanupProgress $Progress $requested.Count '' 'Đang kiểm tra lại danh sách thiết bị…'
        $after=$null
        try{$after=@(Get-DeployPrinterDeviceMap)}catch{$verifyError=$_.Exception.GetBaseException().Message}
        if($null -ne $after){
            foreach($label in @($verify.Keys)){
                $containers=@($verify[$label])
                $left=@($after | Where-Object {$containers -contains $_.ContainerId -and -not $_.Present})
                if($left.Count -and $done -ccontains $label){
                    $done=@($done | Where-Object {$_ -cne $label});$partial+=$label
                    Add-DeployCleanupLine $Progress $lines ('! '+$label+' — Windows vẫn còn '+$left.Count+' mục thiết bị ẩn')
                }
            }
        }
        Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-after' @{Done=$done;Partial=$partial;Pending=@($pending | ForEach-Object {$_.Label});VerifyError=$verifyError}
    }
    $messages=@()
    if($done.Count){$messages+=('Đã gỡ '+$done.Count+' máy in / thiết bị khỏi Windows: '+($done -join ', ')+'.')}
    if($partial.Count){$messages+=('Gỡ chưa trọn '+$partial.Count+' mục: '+($partial -join ', ')+'. Xem chi tiết bên dưới.')}
    if($pending.Count){$messages+=('Windows chưa xoá xong '+$pending.Count+' hàng đợi: '+(@($pending | ForEach-Object {$_.Label}) -join ', ')+'. '+$(if($RestartSpooler -and -not $spoolerError){'Đã khởi động lại Print Spooler mà vẫn còn; khởi động lại máy rồi bấm Gỡ lại.'}else{'Đóng cửa sổ Devices and Printers / Cài đặt máy in rồi bấm Gỡ lại, hoặc tích tự khởi động lại Print Spooler.'}))}
    if($skipped.Count){$messages+=('Bỏ qua '+$skipped.Count+' mục vì đã kết nối lại hoặc không còn trong Windows: '+($skipped -join ', ')+'.')}
    if($failed.Count){$messages+=('Không gỡ được: '+($failed -join '; '))}
    if($scan.DeviceError){$messages+=('Chưa đọc được danh sách thiết bị nên chỉ xoá hàng đợi: '+$scan.DeviceError)}
    if($spoolerError){$messages+=('Không khởi động lại được Print Spooler: '+$spoolerError)}
    if($verifyError){$messages+=('Chưa đọc lại được danh sách thiết bị để xác nhận: '+$verifyError)}
    if($done.Count -or $partial.Count){$messages+='Driver vẫn giữ nguyên.'}
    $kind=if($failed.Count -and -not $done.Count -and -not $partial.Count){'Error'}elseif($partial.Count -or $pending.Count -or $skipped.Count -or $failed.Count -or $scan.DeviceError -or $spoolerError -or $verifyError){'Attention'}else{'Success'}
    if($Progress){$Progress.Percent=100}
    [pscustomobject]@{Message=($messages -join "`n");Kind=$kind;Log=$LogPath;Removed=$done;Partial=$partial;Pending=@($pending | ForEach-Object {$_.Label});Skipped=$skipped;Failed=$failed;Lines=@($lines)}
}
