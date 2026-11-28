function New-DeployPrinterDriverItem([string]$Label,[string]$Name,[string]$Inf) {[pscustomobject]@{Label=$Label;Name=$Name;Inf=$Inf}}
function Set-DeployPrinterDriverList($Window) {
    $view=$Window.Tag;$combo=$Window.FindName('Driver')
    $previous=$combo.SelectedItem
    $items=@()
    if($view.Mode -eq 'Share'){$items+=New-DeployPrinterDriverItem 'Tự động — dùng đúng driver của máy chủ in' '' ''}
    foreach($package in @($view.Packages)){$items+=New-DeployPrinterDriverItem ($package.Model+' — từ thư mục ('+[IO.Path]::GetFileName([string]$package.Inf)+')') ([string]$package.Model) ([string]$package.Inf)}
    foreach($name in @($view.Installed)){$items+=New-DeployPrinterDriverItem ($name+' (đã cài)') ([string]$name) ''}
    $combo.ItemsSource=$items
    $selected=$null
    if($view.Prefer){$selected=@($items | Where-Object {$_.Name -ceq $view.Prefer.Name -and $_.Inf -ceq $view.Prefer.Inf})[0];$view.Prefer=$null}
    if(-not $selected -and $previous){$selected=@($items | Where-Object {$_.Name -ceq $previous.Name -and $_.Inf -ceq $previous.Inf})[0]}
    if(-not $selected -and $items.Count){$selected=$items[0]}
    $combo.SelectedItem=$selected
}
function Set-DeployPrinterRpcState($Window,$Rpc) {
    if(-not $Rpc){return}
    $Window.FindName('RpcState').Text=[string]$Rpc.Text
    $Window.FindName('RpcEnable').IsEnabled=[bool]$Rpc.CanEnable
    $Window.FindName('RpcUndo').IsEnabled=[bool]$Rpc.CanUndo
}
function Set-DeployPrinterConnectBusy($Window,[bool]$Busy) {
    $Window.FindName('Choices').IsEnabled=-not $Busy
    foreach($name in 'Diagnose','Apply','Close'){$Window.FindName($name).IsEnabled=-not $Busy}
}
function Get-DeployPrinterConnectPayload($Window,[ValidateSet('Diagnose','Apply')][string]$Purpose) {
    $mode=$Window.Tag.Mode
    $driver=$Window.FindName('Driver').SelectedItem
    if($mode -eq 'Ip'){
        $address=ConvertFrom-DeployPrinterAddress ([string]$Window.FindName('Address').Text)
        $port=ConvertFrom-DeployPrinterPortNumber ([string]$Window.FindName('PortNumber').Text)
        $payload=@{Mode='Ip';Address=$address;Port=$port}
        if($Purpose -eq 'Apply'){
            if(-not $driver -or -not $driver.Name){throw 'Chọn driver máy in, hoặc bấm Chọn thư mục driver… để lấy driver từ bộ cài của hãng.'}
            $name=([string]$Window.FindName('PrinterName').Text).Trim()
            if(-not $name){$name=[string]$driver.Name+' ('+$address+')';if($name.Length -gt 200){$name=$name.Substring(0,200)}}
            $payload.Name=Assert-DeployPrinterName $name
            $payload.Driver=[string]$driver.Name;$payload.Inf=[string]$driver.Inf
            $payload.A4=[bool]($Window.FindName('SetA4').IsChecked -eq $true)
            $payload.Default=[bool]($Window.FindName('SetDefault').IsChecked -eq $true)
            $payload.TestPage=[bool]($Window.FindName('TestPage').IsChecked -eq $true)
        }
        return $payload
    }
    $target=ConvertFrom-DeployPrinterShare ([string]$Window.FindName('SharePath').Text)
    $password=$Window.FindName('Password').SecurePassword
    $account=([string]$Window.FindName('Account').Text).Trim()
    if($password.Length -gt 0 -and -not $account){throw 'Nhập tài khoản trên máy chủ in (ví dụ print).'}
    $password.MakeReadOnly()
    # Kiểm tra kết nối also tries a typed password (nothing is saved); Kết nối máy in saves it.
    $payload=@{Mode='Share';Path=$target.Path;Account=$account;Password=$password}
    if($Purpose -eq 'Apply'){
        $payload.Driver=$(if($driver){[string]$driver.Name}else{''});$payload.Inf=$(if($driver){[string]$driver.Inf}else{''})
        $payload.Default=[bool]($Window.FindName('ShareDefault').IsChecked -eq $true)
        $payload.TestPage=[bool]($Window.FindName('ShareTestPage').IsChecked -eq $true)
    }
    return $payload
}
function Start-DeployPrinterConnectTask($Window,[ValidateSet('Inspect','Scan','Diagnose','Apply','RpcEnable','RpcUndo')][string]$Action,$Payload=$null) {
    $view=$Window.Tag;if($view.Job){return}
    $status=$Window.FindName('Status')
    if($Action -in 'Diagnose','Apply'){
        try{$Payload=Get-DeployPrinterConnectPayload $Window $Action}catch{Set-DeployNotice $status $_.Exception.GetBaseException().Message 'Attention';return}
    }
    if($Action -eq 'RpcEnable' -and -not (Confirm-Box 'Đổi máy này sang kết nối máy chủ in qua RPC named pipes (RpcUseNamedPipeProtocol = 1)? Vẫn xác thực tài khoản và mã hoá; không tắt bản vá bảo mật in, không đổi máy chủ. App sao lưu thiết lập cũ và khởi động lại Print Spooler: lệnh in đang chờ trên máy này có thể phải in lại.' 'Chế độ tương thích RPC' 'Bật' -Owner $Window)){return}
    if($Action -eq 'RpcUndo' -and -not (Confirm-Box 'Khôi phục cách kết nối máy chủ in như trước khi app bật chế độ tương thích? App khởi động lại Print Spooler.' 'Chế độ tương thích RPC' 'Hoàn tác' -Owner $Window)){return}
    $text=switch($Action){
        'Inspect'{'Đang đọc driver máy in đã cài…'}
        'Scan'{'Đang tìm driver máy in trong '+[string]$Payload.Folder+'…'}
        'Diagnose'{'Đang kiểm tra kết nối (chỉ đọc, không thay đổi gì)…'}
        'Apply'{if($view.Mode -eq 'Ip'){'Đang thêm máy in…'}else{'Đang kiểm tra tài khoản và kết nối máy in…'}}
        default{'Đang đổi thiết lập RPC và khởi động lại Print Spooler…'}
    }
    Set-DeployPrinterConnectBusy $Window $true
    Set-DeployNotice $status $text 'Working'
    try{
        $view.Action=$Action
        $view.Job=Start-DeployWork @'
param($core,$action,$payload)
$ErrorActionPreference='Stop'
. $core
$log=Get-DeployWindowsToolsLog 'PrinterConnect'
try{
    Invoke-DeployPrinterConnectAction $action $payload $log
}catch{
    $message=$_.Exception.GetBaseException().Message
    Write-DeployWindowsToolsLog $log 'failed' @{Action=$action;Error=$message}
    [pscustomobject]@{Message=$message;Kind='Error';Log=$log}
}
'@ @((Join-Path $PSScriptRoot 'PrinterConnect.Core.ps1'),$Action,$Payload)
        $view.Timer.Start()
    }catch{
        $view.Job=$null;Set-DeployPrinterConnectBusy $Window $false
        Set-DeployNotice $status $_.Exception.GetBaseException().Message 'Error'
    }
}
function Complete-DeployPrinterConnectTask($Window,$Result) {
    $view=$Window.Tag
    if($null -ne $Result.Drivers){$view.Installed=@($Result.Drivers)}
    if($null -ne $Result.Packages){
        $view.Packages=@($Result.Packages)
        if($view.Packages.Count){$view.Prefer=[pscustomobject]@{Name=[string]$view.Packages[0].Model;Inf=[string]$view.Packages[0].Inf}}
    }
    Set-DeployPrinterDriverList $Window
    if($Result.Rpc){Set-DeployPrinterRpcState $Window $Result.Rpc}
    if($Result.Log){$Window.FindName('Log').Text='Nhật ký: '+$Result.Log}
    $message=[string]$Result.Message
    if(-not $message -and $view.Action -eq 'Inspect'){$message=if($view.Mode -eq 'Ip'){'Nhập IP máy in, chọn driver rồi bấm Kiểm tra kết nối hoặc Thêm máy in.'}else{'Nhập đường dẫn \\MÁY\MáyIn, tài khoản có mật khẩu trên máy chủ in rồi bấm Kiểm tra kết nối hoặc Kết nối máy in.'}}
    Set-DeployNotice ($Window.FindName('Status')) $message $(if($Result.Kind){[string]$Result.Kind}else{'Info'})
}
function Select-DeployPrinterDriverFolder($Owner) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker=New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description='Chọn thư mục driver máy in đã giải nén (có file .inf)';$picker.ShowNewFolderButton=$false
    try{if($picker.ShowDialog() -eq 'OK'){return $picker.SelectedPath};return $null}finally{$picker.Dispose()}
}
function New-DeployPrinterConnectWindow($Owner=$null,[ValidateSet('Ip','Share')][string]$Mode='Ip') {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'PrinterConnectWindow.xml')
    $window.Tag=@{Mode=$Mode;Job=$null;Action='';Timer=$null;Installed=@();Packages=@();Prefer=$null}
    $title=if($Mode -eq 'Ip'){'Thêm máy in mạng theo IP'}else{'Kết nối máy in chia sẻ'}
    $window.Title=$title;$window.FindName('Heading').Text=$title
    $window.FindName('Subtitle').Text=if($Mode -eq 'Ip'){'Máy in / photocopy có cổng LAN: tạo cổng Standard TCP/IP, cài driver từ kho và thêm hàng đợi cho cả máy này.'}else{'Lưu cho tài khoản Windows '+[Security.Principal.WindowsIdentity]::GetCurrent().Name+': tài khoản có mật khẩu, driver cài sẵn bằng quyền Administrator, không tắt bảo mật in.'}
    foreach($name in 'IpCard','ShareCard','RpcCard'){$window.FindName($name).Visibility='Collapsed'}
    if($Mode -eq 'Ip'){$window.FindName('IpCard').Visibility='Visible'}else{$window.FindName('ShareCard').Visibility='Visible';$window.FindName('RpcCard').Visibility='Visible'}
    $window.FindName('Apply').Content=if($Mode -eq 'Ip'){'Thêm máy in'}else{'Kết nối máy in'}
    $window.FindName('Account').Text='print'
    $window.FindName('RpcEnable').IsEnabled=$false;$window.FindName('RpcUndo').IsEnabled=$false
    Set-DeployPrinterDriverList $window
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $window=$sender.Tag;$view=$window.Tag;$job=$view.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$view.Job=$null
        try{Complete-DeployPrinterConnectTask $window (@(Receive-DeployWork $job)[-1])}
        catch{Set-DeployNotice ($window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{
            # The password is kept for Kết nối máy in after a check, and cleared once a connection was attempted.
            if($view.Action -eq 'Apply'){$window.FindName('Password').Clear()}
            Set-DeployPrinterConnectBusy $window $false
        }
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('Diagnose').Add_Click({param($sender,$event)Start-DeployPrinterConnectTask ([Windows.Window]::GetWindow($sender)) 'Diagnose'})
    $window.FindName('Apply').Add_Click({param($sender,$event)Start-DeployPrinterConnectTask ([Windows.Window]::GetWindow($sender)) 'Apply'})
    $window.FindName('RpcEnable').Add_Click({param($sender,$event)Start-DeployPrinterConnectTask ([Windows.Window]::GetWindow($sender)) 'RpcEnable'})
    $window.FindName('RpcUndo').Add_Click({param($sender,$event)Start-DeployPrinterConnectTask ([Windows.Window]::GetWindow($sender)) 'RpcUndo'})
    $window.FindName('PickDriverFolder').Add_Click({
        param($sender,$event)
        $window=[Windows.Window]::GetWindow($sender)
        $folder=Select-DeployPrinterDriverFolder $window
        if($folder){Start-DeployPrinterConnectTask $window 'Scan' @{Folder=[string]$folder}}
    })
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_Loaded({param($sender,$event)Start-DeployPrinterConnectTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null;$sender.FindName('Password').Clear()})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployPrinterConnect($Owner=$null,[ValidateSet('Ip','Share')][string]$Mode='Ip'){$view=New-DeployPrinterConnectWindow $Owner $Mode;[void]$view.ShowDialog()}
