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
    try{$apps=@(Get-DeployRegisteredDefaultApps)}catch{$appError=$_.Exception.GetBaseException().Message}
    $associations=@{}
    foreach($name in 'http','https','.pdf'){
        try{$associations[$name]=[pscustomobject]@{Readable=$true;ProgId=(Get-DeployCurrentAssociation $name);Error=''}}
        catch{$associations[$name]=[pscustomobject]@{Readable=$false;ProgId='';Error=$_.Exception.GetBaseException().Message}}
    }
    [pscustomobject]@{User=[Environment]::UserName;Printers=$printers;DefaultPrinter=$default;Management=$management;PrinterError=$printerError;Apps=$apps;AppError=$appError;Associations=$associations}
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
