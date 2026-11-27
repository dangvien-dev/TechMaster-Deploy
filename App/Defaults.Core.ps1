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
    $offline=@();$offlineError=''
    if(-not $printerError){try{$offline=@((Get-DeployPrinterOfflineScan).Rows)}catch{$offlineError=$_.Exception.GetBaseException().Message}}
    try{$apps=@(Get-DeployRegisteredDefaultApps)}catch{$appError=$_.Exception.GetBaseException().Message}
    $associations=@{}
    foreach($name in 'http','https','.pdf'){
        try{$associations[$name]=[pscustomobject]@{Readable=$true;ProgId=(Get-DeployCurrentAssociation $name);Error=''}}
        catch{$associations[$name]=[pscustomobject]@{Readable=$false;ProgId='';Error=$_.Exception.GetBaseException().Message}}
    }
    [pscustomobject]@{User=[Environment]::UserName;Printers=$printers;DefaultPrinter=$default;Management=$management;PrinterError=$printerError;OfflinePrinters=$offline;OfflineError=$offlineError;Apps=$apps;AppError=$appError;Associations=$associations}
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
# Offline printer cleanup. Only queues on a USB or network port that Windows reports offline are
# listed; virtual printers (PDF, XPS, OneNote, Fax, FILE:, PORTPROMPT:, nul:) never are. Removal
# deletes the spooler queue only: drivers, ports and the other printers stay installed.
function Get-DeployPrinterPortKind($Queue,$Ports) {
    $port=[string]$Queue.PortName
    if($port -match '^USB\d+$'){return 'USB'}
    if([string]$Queue.Type -eq 'Connection'){return 'Network'}
    if($port -match '^(IP_|WSD-|https?://|\\\\)' -or $port -match '^\d{1,3}(\.\d{1,3}){3}(_\d+)?$'){return 'Network'}
    if($port -and $Ports -and $Ports.ContainsKey($port) -and [string]$Ports[$port].PrinterHostAddress){return 'Network'}
    return ''
}
function Test-DeployPrinterOffline($Queue,$Wmi) {
    if([string]$Queue.PrinterStatus -match 'Offline'){return $true}
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
        if($kind -eq 'Network'){$parts+='máy in mạng có thể chỉ đang tắt hoặc khác mạng'}
        if($isDefault){$parts+='đang là máy in mặc định'}
        if($shared){$parts+='đang chia sẻ cho máy khác'}
        if($jobs -gt 0){$parts+=('còn '+$jobs+' lệnh in sẽ bị huỷ')}
        $rows+=[pscustomobject]@{Name=$name;DriverName=[string]$queue.DriverName;PortName=[string]$queue.PortName;Kind=$kind;IsDefault=$isDefault;Shared=$shared;JobCount=$jobs;Selected=[bool]($kind -eq 'USB' -and -not $isDefault -and -not $shared);Detail=($parts -join ' · ')}
    }
    # USB first: unplugged printers and "(Copy n)" duplicates are the usual leftovers.
    @($rows | Sort-Object -Property @{Expression={if($_.Kind -eq 'USB'){0}else{1}}},@{Expression={$_.Name}})
}
function Get-DeployPrinterOfflineScan {
    $queues=@(Get-Printer -ErrorAction Stop)
    # A failed CIM / port query only narrows detection; it never adds a queue to the list.
    $wmi=@{}
    try{foreach($item in @(Get-CimInstance -ClassName Win32_Printer -OperationTimeoutSec 20 -ErrorAction Stop)){if($item){$wmi[[string]$item.Name]=$item}}}catch{$wmi=@{}}
    $ports=@{}
    try{foreach($item in @(Get-PrinterPort -ErrorAction Stop)){if($item){$ports[[string]$item.Name]=$item}}}catch{$ports=@{}}
    $default='';try{$default=[string](Get-DeployDefaultPrinter)}catch{$default=''}
    [pscustomobject]@{Queues=$queues;Rows=@(Get-DeployOfflinePrinterRows $queues $wmi $ports $default);DefaultPrinter=$default}
}
function Get-DeployOfflineRemovalPrompt($Rows) {
    $rows=@($Rows | Where-Object {$_})
    $lines=@($rows | ForEach-Object {'• '+$_.Name+' ('+$(if($_.Kind -eq 'USB'){'USB'}else{'mạng'})+', cổng '+$_.PortName+')'})
    $message='Gỡ '+$rows.Count+' máy in không kết nối khỏi Windows?'+"`n`n"+($lines -join "`n")
    $message+="`n`nChỉ xoá hàng đợi máy in. Driver và cổng vẫn giữ trong máy: cắm lại máy in USB hoặc thêm lại máy in mạng khi cần dùng."
    $warnings=@()
    if(@($rows | Where-Object {$_.IsDefault}).Count){$warnings+='Có máy in mặc định trong danh sách; Windows sẽ chọn máy in mặc định khác hoặc để trống.'}
    if(@($rows | Where-Object {$_.Shared}).Count){$warnings+='Có máy in đang chia sẻ; máy khác dùng chung sẽ mất máy in này.'}
    $jobs=0;foreach($row in $rows){$jobs+=[int]$row.JobCount}
    if($jobs -gt 0){$warnings+=('Còn '+$jobs+' lệnh in đang chờ sẽ bị huỷ.')}
    if(@($rows | Where-Object {$_.Kind -eq 'Network'}).Count){$warnings+='Máy in mạng có thể chỉ đang tắt hoặc máy đang ở mạng khác.'}
    if($warnings.Count){$message+="`n`nLưu ý:`n"+(@($warnings | ForEach-Object {'• '+$_}) -join "`n")}
    return $message
}
function Remove-DeployOfflinePrinters([string[]]$Names,[string]$LogPath) {
    Assert-DeployPrinterAdmin
    $requested=@($Names | Where-Object {-not [string]::IsNullOrWhiteSpace($_)} | Select-Object -Unique)
    if(-not $requested.Count){throw 'Chọn ít nhất một máy in không kết nối để gỡ.'}
    # Re-read the spooler: a printer reconnected after the list was shown is skipped, never removed.
    $scan=Get-DeployPrinterOfflineScan
    Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-request' @{User=[Environment]::UserName;Requested=$requested;Offline=@($scan.Rows | ForEach-Object {$_.Name});DefaultPrinter=$scan.DefaultPrinter}
    $removed=@();$skipped=@();$failed=@()
    foreach($name in $requested){
        $row=@($scan.Rows | Where-Object {$_.Name -ceq $name})
        $queue=@($scan.Queues | Where-Object {$_.Name -ceq $name})
        if($row.Count -ne 1 -or $queue.Count -ne 1){
            $skipped+=$name
            Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-skipped' @{Printer=$name;Reason=$(if($queue.Count){'not-offline'}else{'missing'})}
            continue
        }
        try{
            Write-DeployWindowsToolsLog $LogPath 'printer-remove-before' $row[0]
            # Pass the exact spooler object: names may contain wildcard characters such as [ ].
            Remove-Printer -InputObject $queue[0] -ErrorAction Stop
            $removed+=$name
        }catch{
            $failure=$_.Exception.GetBaseException().Message
            $failed+=($name+': '+$failure)
            Write-DeployWindowsToolsLog $LogPath 'printer-remove-failed' @{Printer=$name;Error=$failure}
        }
    }
    $verifyError=''
    if($removed.Count){
        $after=@()
        try{$after=@(Get-Printer -ErrorAction Stop)}catch{$verifyError=$_.Exception.GetBaseException().Message}
        if(-not $verifyError){
            foreach($name in @($removed)){
                # A queue with jobs can stay as PendingDeletion until the spooler finishes; that still counts as removed.
                $still=@($after | Where-Object {$_.Name -ceq $name -and [string]$_.PrinterStatus -notmatch 'PendingDeletion'})
                if($still.Count){$removed=@($removed | Where-Object {$_ -cne $name});$failed+=($name+': Windows vẫn còn hàng đợi sau khi gỡ.')}
            }
        }
        Write-DeployWindowsToolsLog $LogPath 'printer-cleanup-after' @{Removed=$removed;Remaining=@($after | ForEach-Object {[string]$_.Name});VerifyError=$verifyError}
    }
    $messages=@()
    if($removed.Count){$messages+=($(if($verifyError){'Đã gửi lệnh gỡ '}else{'Đã gỡ '})+$removed.Count+' máy in: '+($removed -join ', ')+'. Driver và cổng máy in vẫn được giữ.')}
    if($skipped.Count){$messages+=('Bỏ qua '+$skipped.Count+' máy in vì đã kết nối lại hoặc không còn trong Windows: '+($skipped -join ', ')+'.')}
    if($failed.Count){$messages+=('Không gỡ được: '+($failed -join '; '))}
    if($verifyError){$messages+=('Chưa đọc lại được danh sách máy in để xác nhận: '+$verifyError+' Bấm Kiểm tra lại.')}
    $kind=if($failed.Count -and -not $removed.Count){'Error'}elseif($failed.Count -or $skipped.Count -or $verifyError){'Attention'}else{'Success'}
    [pscustomobject]@{Message=($messages -join "`n");Kind=$kind;Log=$LogPath;Removed=$removed;Skipped=$skipped;Failed=$failed}
}
