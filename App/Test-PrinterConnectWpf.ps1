# Native WPF tests for the network printer window. Worker startup, folder picker and confirmations are intercepted; nothing on the computer changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'PrinterConnect.Core.ps1')
. (Join-Path $PSScriptRoot 'PrinterConnect.UI.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Click($window,[string]$name){$window.FindName($name).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
function Reset-Job($window){$window.Tag.Timer.Stop();$window.Tag.Job=$null;Set-DeployPrinterConnectBusy $window $false;$script:captured=$null}
# Real Windows calls that change nothing: the IPC$ logon test, a closed TCP port, printer INFs shipped with Windows.
Initialize-DeployConnectNative
$bogus=ConvertTo-SecureString 'not-a-password' -AsPlainText -Force
$code=[TechMaster.LanConnectNative]::TestConnection('\\127.0.0.1\IPC$','techmaster-no-user',$bogus,0)
Assert ($code -is [int]) "The account test on \\server\IPC$ runs through the any-resource overload (Win32 code $code)"
$refused=$false;try{[void][TechMaster.LanConnectNative]::TestConnection('\\127.0.0.1\IPC$','x',$bogus,2)}catch{$refused=$true}
Assert $refused 'Only the any / disk resource types are accepted'
$open=[TechMaster.LanConnectNative]::OpenConnection('\\127.0.0.1\IPC$','techmaster-no-user',$bogus)
try{Assert ($open -is [int]) "The check session on \\server\IPC$ opens through native code (Win32 code $open)"}
finally{$close=[TechMaster.LanConnectNative]::CloseConnection('\\127.0.0.1\IPC$')}
Assert ($close -is [int]) 'Closing the check session returns a Win32 code'
Assert ($null -eq [TechMaster.LanConnectNative]::SavedUser('127.0.0.1')) 'The account test saves no password'
$watch=[Diagnostics.Stopwatch]::StartNew()
Assert (-not (Test-DeployTcpPort '127.0.0.1' 1 800) -and $watch.ElapsedMilliseconds -lt 5000) 'A closed port is reported quickly'
$windowsInf=@(Get-ChildItem -LiteralPath (Join-Path $env:WINDIR 'INF') -Filter 'prn*.inf' -ErrorAction SilentlyContinue | Select-Object -First 40)
$found=@($windowsInf | ForEach-Object {@(Get-DeployPrinterInfModels (Read-DeployInfText $_.FullName))} | Where-Object {$_.Model})
if($windowsInf.Count -and -not $found.Count){
    # Shows what the parser saw so a format it misses can be fixed from the CI log.
    $sample=$windowsInf[0];$head=[IO.File]::ReadAllBytes($sample.FullName) | Select-Object -First 4 | ForEach-Object {$_.ToString('x2')}
    $text=Read-DeployInfText $sample.FullName
    $lines=@($text -split '\r?\n' | Where-Object {$_ -match '^\s*\[|^\s*(Class|ClassGuid)\s*=|^\s*[^;\[]+=\s*[^,]+,\s*NT'} | Select-Object -First 12)
    Write-Host ('INF sample '+$sample.Name+' bytes '+($head -join ' ')+"`n"+($lines -join "`n"))
}
if($windowsInf.Count){Assert ($found.Count -gt 0) "Printer models are read from INF files shipped with Windows ($($windowsInf.Count) files: $(@($windowsInf | ForEach-Object {$_.Name}) -join ', '))"}
$originalWorker=${function:Start-DeployWork};$originalConfirm=${function:Confirm-Box}
$windows=@()
try{
    function Start-DeployWork([string]$code,[object[]]$arguments){$script:captured=@{Code=$code;Args=$arguments};@{Async=[pscustomobject]@{IsCompleted=$false}}}
    function Confirm-Box([string]$message,[string]$title='Xác nhận',[string]$ConfirmText='Xác nhận',[string]$CancelText='Huỷ',[switch]$Danger,$Owner=$null){$script:prompt=$message;$script:answer}
    function Select-DeployPrinterDriverFolder($Owner){$script:folder}
    $rpc=[pscustomobject]@{Build=22631;Enabled=$false;CanEnable=$true;CanUndo=$false;Text='Mặc định Windows 11 22H2+: kết nối máy chủ in qua RPC over TCP (build 22631).'}
    $inspect=[pscustomobject]@{Message='';Kind='Info';Drivers=@('Microsoft Print To PDF','TOSHIBA Universal Printer 2');Rpc=$rpc;Log=''}
    $expected=@{Ip=@('IpCard','DriverCard');Share=@('ShareCard','DriverCard','RpcCard')}
    foreach($mode in 'Ip','Share'){
        $view=New-DeployPrinterConnectWindow $null $mode;$windows+=$view
        $title=if($mode -eq 'Ip'){'Thêm máy in mạng theo IP'}else{'Kết nối máy in chia sẻ'}
        $shown=@('IpCard','ShareCard','DriverCard','RpcCard' | Where-Object {$view.FindName($_).Visibility -eq 'Visible'})
        Assert (($shown -join ',') -ceq ($expected[$mode] -join ',') -and $view.Title -ceq $title -and $view.FindName('Heading').Text -ceq $title) "$mode shows only its own cards ($($shown -join ','))"
        Assert ([string]$view.FindName('Apply').Content -ceq $(if($mode -eq 'Ip'){'Thêm máy in'}else{'Kết nối máy in'})) "$mode names its main action"
        $view.Tag.Action='Inspect';Complete-DeployPrinterConnectTask $view $inspect
        $items=@($view.FindName('Driver').ItemsSource)
        if($mode -eq 'Ip'){Assert ($items.Count -eq 2 -and $view.FindName('Driver').SelectedItem.Name -ceq 'Microsoft Print To PDF' -and $items[0].Label -match 'đã cài') 'IP mode lists installed drivers'}
        else{Assert ($items.Count -eq 3 -and $view.FindName('Driver').SelectedItem.Name -ceq '' -and $items[0].Label -match 'Tự động') 'Share mode starts with the server driver (automatic)'}
        Assert ($view.FindName('Status').Text -match $(if($mode -eq 'Ip'){'Nhập IP máy in'}else{'tài khoản có mật khẩu'})) "$mode explains the first step"
        foreach($scale in 1.0,1.5){
            $size=[Windows.Size]::new((1024/$scale),(768/$scale))
            $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
            $visible=if($mode -eq 'Ip'){@('Address','PortNumber','PrinterName','Driver','PickDriverFolder')}else{@('SharePath','Account','Password','Driver','RpcEnable','RpcUndo')}
            $hidden=if($mode -eq 'Ip'){@('SharePath','RpcEnable')}else{@('Address','SetA4')}
            Assert (@($visible | Where-Object {$view.FindName($_).ActualHeight -le 0}).Count -eq 0 -and @($hidden | Where-Object {$view.FindName($_).ActualHeight -gt 0}).Count -eq 0) "$mode lays out its own fields and none of the others at $scale"
            Assert ($view.FindName('Diagnose').ActualHeight -gt 0 -and $view.FindName('Apply').ActualHeight -gt 0 -and $view.FindName('Close').ActualWidth -gt 0) "Footer actions are laid out at $scale"
            Assert ($view.FindName('Address').Parent.CornerRadius.TopLeft -gt 0 -and $view.FindName('Driver').Parent.CornerRadius.TopLeft -gt 0) 'Inputs use the rounded shared controls'
        }
    }
    $ip=$windows[0];$share=$windows[1]

    # IP mode
    $script:captured=$null
    Click $ip 'Diagnose'
    Assert (-not $ip.Tag.Job -and $null -eq $script:captured -and $ip.FindName('Status').Text -match 'Nhập địa chỉ IP') 'An empty address is reported in the window without starting work'
    $ip.FindName('Address').Text=' 192.168.1.50 ';$ip.FindName('PortNumber').Text=''
    Click $ip 'Diagnose'
    Assert ($ip.Tag.Job -and $script:captured.Args[1] -ceq 'Diagnose' -and $script:captured.Args[2].Mode -ceq 'Ip' -and $script:captured.Args[2].Address -ceq '192.168.1.50' -and $script:captured.Args[2].Port -eq 9100) 'Diagnose sends the cleaned address and default port'
    Assert (-not $ip.FindName('Choices').IsEnabled -and -not $ip.FindName('Apply').IsEnabled -and -not $ip.FindName('Close').IsEnabled) 'Work in progress locks the window'
    Reset-Job $ip
    Click $ip 'Apply'
    $payload=$script:captured.Args[2]
    Assert ($script:captured.Args[1] -ceq 'Apply' -and $payload.Name -ceq 'Microsoft Print To PDF (192.168.1.50)' -and $payload.Driver -ceq 'Microsoft Print To PDF' -and $payload.Inf -ceq '' -and $payload.A4 -and -not $payload.Default -and -not $payload.TestPage) 'Apply names the queue after model and IP when the name is empty; A4 is on by default'
    Reset-Job $ip
    $script:folder='D:\KhoDriver\Toshiba'
    Click $ip 'PickDriverFolder'
    Assert ($script:captured.Args[1] -ceq 'Scan' -and $script:captured.Args[2].Folder -ceq 'D:\KhoDriver\Toshiba') 'Choosing a driver folder scans it in the background'
    Reset-Job $ip
    $script:folder=$null
    Click $ip 'PickDriverFolder'
    Assert ($null -eq $script:captured) 'Cancelling the folder picker starts nothing'
    $ip.Tag.Action='Scan'
    Complete-DeployPrinterConnectTask $ip ([pscustomobject]@{Message='Tìm thấy 1 model';Kind='Success';Packages=@([pscustomobject]@{Model='TOSHIBA e-STUDIO2010AC PCL6';Manufacturer='Toshiba';Inf='D:\KhoDriver\Toshiba\esf6u.inf'});Log='C:\log.jsonl'})
    $selected=$ip.FindName('Driver').SelectedItem
    Assert ($selected.Name -ceq 'TOSHIBA e-STUDIO2010AC PCL6' -and $selected.Inf -like '*esf6u.inf' -and $selected.Label -match 'từ thư mục' -and @($ip.FindName('Driver').ItemsSource).Count -eq 3 -and $ip.FindName('Log').Text -match 'log.jsonl') 'A scanned model is listed before installed drivers and selected'
    $ip.FindName('PrinterName').Text='Photocopy tầng 2';$ip.FindName('SetDefault').IsChecked=$true;$ip.FindName('TestPage').IsChecked=$true;$ip.FindName('SetA4').IsChecked=$false
    Click $ip 'Apply'
    $payload=$script:captured.Args[2]
    Assert ($payload.Name -ceq 'Photocopy tầng 2' -and $payload.Inf -like '*esf6u.inf' -and -not $payload.A4 -and $payload.Default -and $payload.TestPage) 'Apply sends the chosen name, INF and options'
    Reset-Job $ip
    $ip.Tag.Action='Apply'
    Complete-DeployPrinterConnectTask $ip ([pscustomobject]@{Message='✓ Đã thêm';Kind='Success';Drivers=@('Microsoft Print To PDF','TOSHIBA Universal Printer 2','TOSHIBA e-STUDIO2010AC PCL6');Log=''})
    Assert ($ip.FindName('Driver').SelectedItem.Name -ceq 'TOSHIBA e-STUDIO2010AC PCL6' -and $ip.FindName('Driver').SelectedItem.Inf -like '*esf6u.inf') 'Refreshing the driver list keeps the selection'
    $ip.FindName('PortNumber').Text='99999'
    Click $ip 'Apply'
    Assert ($null -eq $script:captured -and $ip.FindName('Status').Text -match 'Cổng không hợp lệ') 'An invalid port is refused before any work'

    # Share mode
    Set-DeployPrinterRpcState $share $rpc
    Assert ($share.FindName('RpcEnable').IsEnabled -and -not $share.FindName('RpcUndo').IsEnabled -and $share.FindName('RpcState').Text -match 'RPC over TCP') 'The RPC card shows the current mode and what can be done'
    $share.FindName('SharePath').Text='\\KE-TOAN\Canon2900\x'
    Click $share 'Apply'
    Assert ($null -eq $script:captured -and $share.FindName('Status').Text -match 'không có thư mục con') 'A wrong printer path is refused in the window'
    $share.FindName('SharePath').Text='//KE-TOAN/Canon2900';$share.FindName('Password').Password='Print@2026';$share.FindName('ShareDefault').IsChecked=$true
    Click $share 'Diagnose'
    $payload=$script:captured.Args[2]
    Assert ($script:captured.Args[1] -ceq 'Diagnose' -and $payload.Path -ceq '\\KE-TOAN\Canon2900' -and $payload.Account -ceq 'print' -and $payload.Password -is [Security.SecureString] -and $payload.Password.Length -eq 10) 'Kiểm tra kết nối sends the typed account and password (as SecureString) so the logon can be tried'
    Reset-Job $share
    $share.Tag.Action='Diagnose'
    Complete-DeployPrinterConnectTask $share ([pscustomobject]@{Message='✓ Đăng nhập';Kind='Success';Log=''})
    Assert ($share.FindName('Password').Password -ceq 'Print@2026') 'The password stays after a check so Kết nối máy in can use it'
    Click $share 'Apply'
    $payload=$script:captured.Args[2]
    Assert ($payload.Mode -ceq 'Share' -and $payload.Path -ceq '\\KE-TOAN\Canon2900' -and $payload.Account -ceq 'print' -and $payload.Password -is [Security.SecureString] -and $payload.Password.Length -eq 10 -and $payload.Driver -ceq '' -and $payload.Default -and -not $payload.TestPage) 'Connect sends the path, print account, password as SecureString and the automatic driver'
    Assert (-not ($script:captured.Code -match 'Print@2026')) 'The password is not part of the worker script'
    Reset-Job $share
    $share.FindName('Account').Text=''
    Click $share 'Apply'
    Assert ($null -eq $script:captured -and $share.FindName('Status').Text -match 'Nhập tài khoản') 'A password without an account is refused'
    $share.FindName('Password').Clear()
    Click $share 'Apply'
    Assert ($script:captured.Args[2].Password.Length -eq 0) 'Without a password the saved one will be used'
    Reset-Job $share
    $script:answer=$false
    Click $share 'RpcEnable'
    Assert ($null -eq $script:captured -and $script:prompt -match 'RpcUseNamedPipeProtocol' -and $script:prompt -match 'không tắt bản vá' -and $script:prompt -match 'Print Spooler') 'Enabling RPC mode asks first and explains what changes'
    $script:answer=$true
    Click $share 'RpcEnable'
    Assert ($script:captured.Args[1] -ceq 'RpcEnable' -and -not $share.FindName('Choices').IsEnabled) 'Confirmed RPC mode runs in the background'
    Reset-Job $share
    $share.Tag.Action='RpcEnable'
    Complete-DeployPrinterConnectTask $share ([pscustomobject]@{Message='✓ Đã bật';Kind='Success';Rpc=[pscustomobject]@{Build=22631;Enabled=$true;CanEnable=$false;CanUndo=$true;Text='Đang bật: app đã bật'};Log=''})
    Assert (-not $share.FindName('RpcEnable').IsEnabled -and $share.FindName('RpcUndo').IsEnabled -and $share.FindName('RpcState').Text -match 'app đã bật') 'After enabling, only Undo is offered'
    $script:answer=$false
    Click $share 'RpcUndo'
    Assert ($null -eq $script:captured -and $script:prompt -match 'Khôi phục') 'Undo asks first'
    Write-Host "PASS: $checks network printer UI assertions; per-mode cards and layout, driver list, input checks, worker payloads, folder scan, RPC mode confirmation."
}finally{
    Set-Item Function:Start-DeployWork $originalWorker;Set-Item Function:Confirm-Box $originalConfirm
    foreach($w in $windows){$w.Tag.Job=$null;$w.Tag.Timer.Stop();$w.Close()}
}
