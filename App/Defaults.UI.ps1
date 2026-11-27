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
    Set-DeployOfflinePrintersView $Window $Snapshot
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
function Set-DeployOfflinePrintersView($Window,$Snapshot) {
    $state=$Window.Tag;$checked=@{}
    # Keep the user's ticks across refreshes; queues new to the list start from the recommended choice.
    foreach($box in @($state.CleanupBoxes)){if($box -and $box.Tag){$checked[(Get-DeployCleanupKey $box.Tag)]=[bool]$box.IsChecked}}
    $panel=$Window.FindName('CleanupItems');$panel.Children.Clear();$state.CleanupBoxes=@()
    $rows=@($Snapshot.OfflinePrinters | Where-Object {$_})
    foreach($row in $rows){
        $box=New-Object Windows.Controls.CheckBox
        $box.Margin='0,4,0,4';$box.VerticalContentAlignment='Top';$box.Tag=$row
        $key=Get-DeployCleanupKey $row
        $box.IsChecked=$(if($checked.ContainsKey($key)){$checked[$key]}else{[bool]$row.Selected})
        $text=New-Object Windows.Controls.StackPanel
        $title=New-Object Windows.Controls.TextBlock;$title.Text=[string]$row.Name;$title.FontWeight='SemiBold'
        $detail=New-Object Windows.Controls.TextBlock;$detail.Text=[string]$row.Detail;$detail.Foreground='#526880';$detail.FontSize=12;$detail.Margin='0,2,0,0'
        [void]$text.Children.Add($title);[void]$text.Children.Add($detail)
        $box.Content=$text
        [void]$panel.Children.Add($box);$state.CleanupBoxes+=$box
    }
    $queues=@($rows | Where-Object {$_.Kind -ne 'Device'}).Count;$devices=$rows.Count-$queues
    $summary=@()
    if($queues){$summary+=('Windows đang báo '+$queues+' máy in không kết nối')}
    if($devices){$summary+=($devices.ToString()+' thiết bị máy in còn sót (không còn hàng đợi nhưng vẫn hiện trong Devices and Printers)')}
    $Window.FindName('CleanupCurrent').Text=if($Snapshot.PrinterError){'Chưa đọc được máy in: '+$Snapshot.PrinterError}elseif($Snapshot.OfflineError){'Chưa xác định được máy in không kết nối: '+$Snapshot.OfflineError}elseif(-not $rows.Count){'Không có máy in USB / mạng nào đang báo không kết nối (Offline) và không có thiết bị máy in còn sót.'}else{($summary -join '; ')+'. Máy in USB và thiết bị còn sót được chọn sẵn; máy in mạng, máy in mặc định và máy in đang chia sẻ cần tự tích nếu muốn gỡ.'}
    if($Snapshot.OfflineDeviceError){$Window.FindName('CleanupCurrent').Text+=' Chưa đọc được danh sách thiết bị nên chỉ xoá được hàng đợi: '+$Snapshot.OfflineDeviceError}
    foreach($name in 'RemoveOffline','CleanupAll','CleanupNone'){$Window.FindName($name).IsEnabled=[bool]$rows.Count}
}
function Get-DeployCleanupKey($Row) {if([string]$Row.Key){[string]$Row.Key}else{[string]$Row.Name}}
function Update-DeployCleanupProgressView($Window) {
    $state=$Window.Tag;$progress=$state.Progress
    if(-not $progress){return}
    $Window.FindName('CleanupBar').Value=[double]$progress.Percent
    $log=$Window.FindName('CleanupLog')
    while($state.Shown -lt $progress.Lines.Count){
        $log.Text+=$(if($log.Text){"`n"}else{''})+[string]$progress.Lines[$state.Shown];$state.Shown++
    }
    $text=if($progress.Current){'Đang gỡ '+$progress.Index+'/'+$progress.Total+': '+$progress.Current+' — '+$progress.Step+'…'}else{[string]$progress.Step}
    Set-DeployNotice ($Window.FindName('CleanupStatus')) $text 'Working'
}
function Start-DeployDefaultsTask($Window,[ValidateSet('Inspect','Printer','Browser','Pdf','Cleanup')][string]$Action) {
    $state=$Window.Tag;if($state.Job){return}
    $printer=$Window.FindName('Printer').SelectedItem
    $app=if($Action -in 'Browser','Pdf'){$Window.FindName($Action).SelectedItem}else{$null}
    if($Action -eq 'Printer' -and -not $printer){Set-DeployNotice ($Window.FindName('Status')) 'Chọn máy in đã cài đặt trước khi áp dụng.' 'Attention';return}
    if($Action -in 'Browser','Pdf' -and -not $app){Set-DeployNotice ($Window.FindName('Status')) 'Chọn một ứng dụng đã cài và đăng ký trong Windows.' 'Attention';return}
    $remove=[string[]]@()
    if($Action -eq 'Cleanup'){
        $rows=@($state.CleanupBoxes | Where-Object {$_.IsChecked -eq $true} | ForEach-Object {$_.Tag})
        if(-not $rows.Count){Set-DeployNotice ($Window.FindName('Status')) 'Tích ít nhất một máy in không kết nối trước khi gỡ.' 'Attention';return}
        $restart=[bool]$Window.FindName('CleanupRestartSpooler').IsChecked
        if(-not (Confirm-Box (Get-DeployOfflineRemovalPrompt $rows $restart) 'Gỡ máy in không kết nối' 'Gỡ máy in' -Danger -Owner $Window)){return}
        $remove=[string[]]@($rows | ForEach-Object {Get-DeployCleanupKey $_})
    }
    # Progress is shown inside the card: the window's top notice is usually scrolled out of view here.
    $state.Progress=$null;$state.Shown=0
    if($Action -eq 'Cleanup'){
        $state.Progress=[hashtable]::Synchronized(@{Index=0;Total=$remove.Count;Current='';Step='Đang chuẩn bị gỡ '+$remove.Count+' mục…';Percent=0;Lines=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))})
        $Window.FindName('CleanupLog').Text='';$Window.FindName('CleanupBar').Value=0
        $Window.FindName('CleanupProgress').Visibility='Visible'
        Update-DeployCleanupProgressView $Window
        $Window.UpdateLayout();$Window.FindName('CleanupProgress').BringIntoView()
    }
    $Window.FindName('Choices').IsEnabled=$false
    foreach($name in 'Refresh','DefaultsSettings','Close'){$Window.FindName($name).IsEnabled=$false}
    Set-DeployNotice ($Window.FindName('Status')) 'Đang đọc / áp dụng thiết lập…' 'Working'
    try{
        $state.Action=$Action;$state.RequestedApp=$app
        $state.Job=Start-DeployWork @'
param($core,$action,$printer,$a4,$makeDefault,$app,$remove,$progress,$restartSpooler)
$ErrorActionPreference='Stop'
. $core
$message='Đã đọc lại thiết lập hiện tại.';$kind='Info';$log=''
if($action -ne 'Inspect'){
    $log=Get-DeployWindowsToolsLog $(if($action -eq 'Cleanup'){'PrinterCleanup'}else{'Defaults'})
    try{
        $result=if($action -eq 'Printer'){Set-DeployPrinterDefaults $printer $a4 $makeDefault $log}elseif($action -eq 'Cleanup'){Remove-DeployOfflinePrinters ([string[]]@($remove)) $log $progress -RestartSpooler:([bool]$restartSpooler)}else{Open-DeployDefaultAppSettings $app $action $log}
        $message=$result.Message;$kind=$result.Kind
    }catch{
        $message=$_.Exception.GetBaseException().Message;$kind='Error'
        Write-DeployWindowsToolsLog $log 'failed' $message
    }
}
[pscustomobject]@{Snapshot=(Get-DeployDefaultsSnapshot);Message=$message;Kind=$kind;Log=$log}
'@ @((Join-Path $PSScriptRoot 'Defaults.Core.ps1'),$Action,[string]$printer.Name,[bool]$Window.FindName('MakeA4').IsChecked,[bool]$Window.FindName('MakeDefault').IsChecked,$app,$remove,$state.Progress,[bool]$Window.FindName('CleanupRestartSpooler').IsChecked)
        $state.Timer.Start()
    }catch{
        $state.Job=$null;$Window.FindName('Choices').IsEnabled=$true
        foreach($name in 'Refresh','DefaultsSettings','Close'){$Window.FindName($name).IsEnabled=$true}
        Set-DeployNotice ($Window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
        if($state.Progress){Set-DeployNotice ($Window.FindName('CleanupStatus')) $_.Exception.GetBaseException().Message 'Error';$state.Progress=$null}
    }
}
function New-DeployDefaultsWindow($Owner=$null,[string]$Focus='') {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'DefaultsWindow.xml')
    $window.Tag=@{Job=$null;Action='';RequestedApp=$null;Pending=@{};Snapshot=$null;Timer=$null;CleanupBoxes=@();Focus=$Focus;Progress=$null;Shown=0}
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $view=$sender.Tag;$state=$view.Tag;$job=$state.Job
        if(-not $job){return}
        if($state.Progress){Update-DeployCleanupProgressView $view}
        if(-not $job.Async.IsCompleted){return}
        $sender.Stop();$state.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            Set-DeployDefaultsView $view $r.Snapshot
            if($state.Progress){
                Update-DeployCleanupProgressView $view
                $view.FindName('CleanupBar').Value=100
                Set-DeployNotice ($view.FindName('CleanupStatus')) $r.Message $r.Kind
                $state.Progress=$null
            }
            if($state.Focus -ceq 'Cleanup'){$state.Focus='';$view.UpdateLayout();$view.FindName('CleanupCard').BringIntoView()}
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
            }elseif($state.Action -eq 'Inspect' -and ($r.Snapshot.PrinterError -or $r.Snapshot.OfflineError -or $r.Snapshot.AppError -or @($r.Snapshot.Associations.Values | Where-Object {-not $_.Readable}).Count)){
                $r.Message='Đã đọc những thiết lập khả dụng; có mục chưa đọc được. Xem trạng thái trong từng phần.';$r.Kind='Attention'
            }
            Set-DeployNotice ($view.FindName('Status')) $r.Message $r.Kind
        }catch{
            Set-DeployNotice ($view.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
            if($state.Progress){Set-DeployNotice ($view.FindName('CleanupStatus')) $_.Exception.GetBaseException().Message 'Error';$state.Progress=$null}
        }
        finally{$view.FindName('Choices').IsEnabled=$true;foreach($name in 'Refresh','DefaultsSettings','Close'){$view.FindName($name).IsEnabled=$true}}
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('ApplyPrinter').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Printer'})
    $window.FindName('OpenBrowser').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Browser'})
    $window.FindName('OpenPdf').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Pdf'})
    $window.FindName('Refresh').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Inspect'})
    $window.FindName('RemoveOffline').Add_Click({param($sender,$event)Start-DeployDefaultsTask ([Windows.Window]::GetWindow($sender)) 'Cleanup'})
    $window.FindName('CleanupAll').Add_Click({param($sender,$event)foreach($box in @([Windows.Window]::GetWindow($sender).Tag.CleanupBoxes)){$box.IsChecked=$true}})
    $window.FindName('CleanupNone').Add_Click({param($sender,$event)foreach($box in @([Windows.Window]::GetWindow($sender).Tag.CleanupBoxes)){$box.IsChecked=$false}})
    $window.FindName('DefaultsSettings').Add_Click({Start-Process 'ms-settings:defaultapps' -ErrorAction Stop})
    $window.FindName('PrinterSettings').Add_Click({Start-Process 'ms-settings:printers' -ErrorAction Stop})
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_ContentRendered({param($sender,$event)if($sender.Tag.Focus -ceq 'Cleanup'){$sender.FindName('CleanupCard').BringIntoView()};Start-DeployDefaultsTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployDefaults($Owner=$null,[string]$Focus=''){$view=New-DeployDefaultsWindow $Owner $Focus;[void]$view.ShowDialog()}
