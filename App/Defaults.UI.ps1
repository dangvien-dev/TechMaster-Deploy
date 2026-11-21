function Set-DeployDefaultsView($Window,$Snapshot) {
    $state=$Window.Tag
    $Window.FindName('Account').Text='Áp dụng cho tài khoản đang chạy app: '+$Snapshot.User+'. Nếu nâng quyền bằng tài khoản khác, thiết lập thuộc tài khoản đó.'
    $previous=[string]$Window.FindName('Printer').SelectedItem.Name
    $Window.FindName('Printer').ItemsSource=@($Snapshot.Printers)
    $pick=$Snapshot.Printers | Where-Object Name -CEQ $previous | Select-Object -First 1
    if(-not $pick){$pick=$Snapshot.Printers | Where-Object Name -CEQ $Snapshot.DefaultPrinter | Select-Object -First 1}
    if(-not $pick){$pick=$Snapshot.Printers | Select-Object -First 1}
    $Window.FindName('Printer').SelectedItem=$pick
    $Window.FindName('ApplyPrinter').IsEnabled=[bool]$pick
    $Window.FindName('PrinterCurrent').Text=if($Snapshot.PrinterError){'Chưa đọc được máy in: '+$Snapshot.PrinterError}elseif(-not @($Snapshot.Printers).Count){'Chưa có máy in được cài trong Windows.'}elseif($Snapshot.DefaultPrinter){'Máy in mặc định hiện tại: '+$Snapshot.DefaultPrinter}else{'Chưa có máy in mặc định.'}
    foreach($kind in 'Browser','Pdf'){
        $control=$Window.FindName($kind);$previous=$control.SelectedItem
        $apps=@($Snapshot.Apps | Where-Object {if($kind -eq 'Browser'){$_.Http -and $_.Https}else{$_.Pdf}})
        $control.ItemsSource=$apps
        $pick=$apps | Where-Object {$previous -and $_.Name -ceq $previous.Name -and $_.Scope -ceq $previous.Scope} | Select-Object -First 1
        if(-not $pick){$pick=$apps | Where-Object {Test-DeployDefaultAppChoice $_ $kind $Snapshot} | Select-Object -First 1}
        if(-not $pick){$pick=$apps | Select-Object -First 1}
        $control.SelectedItem=$pick
        $Window.FindName('Open'+$kind).IsEnabled=[bool]$pick
    }
    $Window.FindName('BrowserCurrent').Text='HTTP: '+(Get-DeployAssociationLabel $Snapshot.Associations['http'] $Snapshot.Apps 'Http')+"`nHTTPS: "+(Get-DeployAssociationLabel $Snapshot.Associations['https'] $Snapshot.Apps 'Https')
    $Window.FindName('PdfCurrent').Text='PDF hiện tại: '+(Get-DeployAssociationLabel $Snapshot.Associations['.pdf'] $Snapshot.Apps 'Pdf')
    if($Snapshot.AppError){$Window.FindName('PdfCurrent').Text+=' · Chưa đọc được danh sách ứng dụng: '+$Snapshot.AppError}
    elseif(-not @($Snapshot.Apps).Count){$Window.FindName('PdfCurrent').Text+=' · Chưa tìm thấy ứng dụng đăng ký. Cài ứng dụng rồi kiểm tra lại hoặc mở Ứng dụng mặc định trong Windows.'}
    $state.Snapshot=$Snapshot
}
function Start-DeployDefaultsTask($Window,[ValidateSet('Inspect','Printer','Browser','Pdf')][string]$Action) {
    $state=$Window.Tag;if($state.Job){return}
    $printer=$Window.FindName('Printer').SelectedItem
    $app=if($Action -in 'Browser','Pdf'){$Window.FindName($Action).SelectedItem}else{$null}
    if($Action -eq 'Printer' -and -not $printer){Set-DeployNotice ($Window.FindName('Status')) 'Chọn máy in đã cài đặt trước khi áp dụng.' 'Attention';return}
    if($Action -in 'Browser','Pdf' -and -not $app){Set-DeployNotice ($Window.FindName('Status')) 'Chọn một ứng dụng đã cài và đăng ký trong Windows.' 'Attention';return}
    $Window.FindName('Choices').IsEnabled=$false
    foreach($name in 'Refresh','DefaultsSettings','Close'){$Window.FindName($name).IsEnabled=$false}
    Set-DeployNotice ($Window.FindName('Status')) 'Đang đọc / áp dụng thiết lập…' 'Working'
    try{
        $state.Action=$Action;$state.RequestedApp=$app
        $state.Job=Start-DeployWork @'
param($core,$action,$printer,$a4,$makeDefault,$app)
$ErrorActionPreference='Stop'
. $core
$message='Đã đọc lại thiết lập hiện tại.';$kind='Info';$log=''
if($action -ne 'Inspect'){
    $log=Get-DeployWindowsToolsLog 'Defaults'
    try{
        $result=if($action -eq 'Printer'){Set-DeployPrinterDefaults $printer $a4 $makeDefault $log}else{Open-DeployDefaultAppSettings $app $action $log}
        $message=$result.Message;$kind=$result.Kind
    }catch{
        $message=$_.Exception.GetBaseException().Message;$kind='Error'
        Write-DeployWindowsToolsLog $log 'failed' $message
    }
}
[pscustomobject]@{Snapshot=(Get-DeployDefaultsSnapshot);Message=$message;Kind=$kind;Log=$log}
'@ @((Join-Path $PSScriptRoot 'Defaults.Core.ps1'),$Action,[string]$printer.Name,[bool]$Window.FindName('MakeA4').IsChecked,[bool]$Window.FindName('MakeDefault').IsChecked,$app)
        $state.Timer.Start()
    }catch{
        $state.Job=$null;$Window.FindName('Choices').IsEnabled=$true
        foreach($name in 'Refresh','DefaultsSettings','Close'){$Window.FindName($name).IsEnabled=$true}
        Set-DeployNotice ($Window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
    }
}
function New-DeployDefaultsWindow($Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'DefaultsWindow.xml')
    $window.Tag=@{Job=$null;Action='';RequestedApp=$null;Pending=@{};Snapshot=$null;Timer=$null}
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $view=$sender.Tag;$state=$view.Tag;$job=$state.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$state.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            Set-DeployDefaultsView $view $r.Snapshot
            if($r.Log){$view.FindName('Log').Text='Nhật ký: '+$r.Log}
            if($state.Action -in 'Browser','Pdf' -and $r.Kind -ne 'Error'){$state.Pending[$state.Action]=$state.RequestedApp}
            if($state.Action -eq 'Inspect' -and $state.Pending.Count){
                $notes=@();$all=$true
                foreach($kind in @($state.Pending.Keys)){
                    $app=$state.Pending[$kind]
                    if(Test-DeployDefaultAppChoice $app $kind $r.Snapshot){$notes+='Đã xác nhận '+$(if($kind -eq 'Browser'){'HTTP và HTTPS'}else{'.pdf'})+' dùng '+$app.Display+'.';$state.Pending.Remove($kind)}
                    else{$notes+='Chưa xác nhận '+$app.Display+' là mặc định cho '+$(if($kind -eq 'Browser'){'cả HTTP và HTTPS'}else{'.pdf'})+'. Hoàn tất lựa chọn trong Cài đặt rồi kiểm tra lại.';$all=$false}
                }
                $r.Message=$notes -join "`n";$r.Kind=if($all){'Success'}else{'Attention'}
            }elseif($state.Action -eq 'Inspect' -and ($r.Snapshot.PrinterError -or $r.Snapshot.AppError -or @($r.Snapshot.Associations.Values | Where-Object {-not $_.Readable}).Count)){
                $r.Message='Đã đọc những thiết lập khả dụng; có mục chưa đọc được. Xem trạng thái trong từng phần.';$r.Kind='Attention'
            }
            Set-DeployNotice ($view.FindName('Status')) $r.Message $r.Kind
        }catch{Set-DeployNotice ($view.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{$view.FindName('Choices').IsEnabled=$true;foreach($name in 'Refresh','DefaultsSettings','Close'){$view.FindName($name).IsEnabled=$true}}
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('ApplyPrinter').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Printer'})
    $window.FindName('OpenBrowser').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Browser'})
    $window.FindName('OpenPdf').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Pdf'})
    $window.FindName('Refresh').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Inspect'})
    $window.FindName('DefaultsSettings').Add_Click({Start-Process 'ms-settings:defaultapps' -ErrorAction Stop})
    $window.FindName('PrinterSettings').Add_Click({Start-Process 'ms-settings:printers' -ErrorAction Stop})
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_ContentRendered({param($sender,$event)Start-DeployDefaultsTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployDefaults($Owner=$null){$view=New-DeployDefaultsWindow $Owner;[void]$view.ShowDialog()}
