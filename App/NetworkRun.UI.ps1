function Set-DeployNetworkRunView($Window,$State) {
    $view=$Window.Tag;$view.State=$State
    $Window.FindName('Subtitle').Text='Máy '+$State.Computer+': chia sẻ thư mục TechMaster (chỉ đọc) để máy khác trong mạng chạy app không cần USB.'
    $Window.FindName('RootPath').Text=[string]$State.Root
    $Window.FindName('RootNote').Text=if($State.RootError){'✗ '+$State.RootError}
        elseif(@($State.SourceProblems).Count){'✗ Có tệp khác danh sách tệp của app: '+((@($State.SourceProblems) | Select-Object -First 3) -join ', ')+'. Cập nhật lại app trước khi chia sẻ.'}
        elseif($State.Active){'Đang chia sẻ: \\'+$State.Computer+'\TechMaster$ (chỉ đọc) cho '+$State.Account+'.'}
        elseif($State.Share){'Tên TechMaster$ đang chia sẻ '+$State.Share.Path+$(if($State.Share.Ours){'; bấm Chia sẻ TechMaster để chuyển sang thư mục này.'}else{' và không do app tạo.'})}
        else{'Chưa chia sẻ. Chỉ chia sẻ các tệp của app, máy kia không ghi được.'}
    $combo=$Window.FindName('Account');$previous=if($combo.SelectedItem){[string]$combo.SelectedItem.Account}else{''}
    $accounts=@($State.Accounts);$combo.ItemsSource=$accounts
    $pick=if($previous){$previous}elseif($State.Active -and $State.Account){$State.Account}else{''}
    $combo.SelectedItem=@($accounts | Where-Object {$_.Account -ieq $pick})[0]
    if($null -eq $combo.SelectedItem -and $accounts.Count){$combo.SelectedIndex=0}
    $public=@($State.Profiles | Where-Object {$_.Category -eq 'Public'})
    $network=@()
    if($State.ProfileError){$network+=('Chưa đọc được mạng: '+$State.ProfileError)}
    elseif(@($State.Profiles).Count){$network+=@($State.Profiles | ForEach-Object {'• '+$_.Alias+' ('+$_.Name+'): '+$(if($_.Category -eq 'Public'){'Public — máy khác chưa vào được'}elseif($_.Category -eq 'DomainAuthenticated'){'Domain'}else{[string]$_.Category})})}
    else{$network+='Chưa có kết nối mạng.'}
    if($State.FirewallReady){$network+='Luật tường lửa của TechMaster đã bật.'}
    if($State.Server -and $State.Server -ne 'Running'){$network+='Dịch vụ Server (LanmanServer) đang tắt; app sẽ bật khi chia sẻ.'}
    $Window.FindName('NetworkState').Text=$network -join "`n"
    $private=$Window.FindName('MakePrivate');$private.IsEnabled=[bool]$public.Count
    if(-not $public.Count){$private.IsChecked=$false}
    $paths=@($State.ClientPaths)
    $Window.FindName('ClientPath').Text=if($paths.Count){$paths[0]}else{''}
    $Window.FindName('ClientNote').Text=if($paths.Count -gt 1){'Hoặc theo IP: '+((@($paths | Select-Object -Skip 1)) -join '   ')}else{'Máy kia không tìm thấy tên máy thì dùng \\IP-của-máy-này\TechMaster$\App\Chay-Tu-Mang.bat.'}
    $Window.FindName('StopShare').IsEnabled=[bool]($State.Share -and $State.Share.Ours)
    $Window.FindName('Apply').Content=if($State.Active){'Cập nhật chia sẻ'}else{'Chia sẻ TechMaster'}
}
function Set-DeployNetworkRunBusy($Window,[bool]$Busy) {
    $Window.FindName('Choices').IsEnabled=-not $Busy
    foreach($name in 'Apply','Refresh','Close'){$Window.FindName($name).IsEnabled=-not $Busy}
    $state=$Window.Tag.State
    $Window.FindName('StopShare').IsEnabled=(-not $Busy) -and [bool]($state -and $state.Share -and $state.Share.Ours)
}
function Start-DeployNetworkRunTask($Window,[ValidateSet('Inspect','Apply','Stop')][string]$Action) {
    $view=$Window.Tag;if($view.Job){return}
    $status=$Window.FindName('Status');$account='';$private=@()
    if($Action -eq 'Apply'){
        $state=$view.State
        if($state -and $state.RootError){Set-DeployNotice $status $state.RootError 'Attention';return}
        $choice=$Window.FindName('Account').SelectedItem
        if(-not $choice){Set-DeployNotice $status 'Chọn tài khoản máy kia dùng để mở thư mục TechMaster.' 'Attention';return}
        $account=[string]$choice.Account
        if($Window.FindName('MakePrivate').IsChecked -eq $true){$private=@($state.Profiles | Where-Object {$_.Category -eq 'Public'} | ForEach-Object {[int]$_.Index})}
        $message='Chia sẻ '+$view.Root+' thành \\'+$env:COMPUTERNAME+'\TechMaster$ (chỉ đọc) cho '+$account+'?'
        if($Window.FindName('Firewall').IsChecked -eq $true){$message+="`n`nMở tường lửa cho chia sẻ file trong LAN (chỉ mạng Private / Domain)."}
        if($private.Count){$message+="`nChuyển "+$private.Count+' mạng Public sang Private.'}
        if(-not (Confirm-Box $message 'Chạy TechMaster qua mạng' 'Chia sẻ' -Owner $Window)){return}
    }elseif($Action -eq 'Stop'){
        $message='Ngừng chia sẻ \\'+$env:COMPUTERNAME+'\TechMaster$? Máy đang chép dở sẽ báo lỗi; bản đã chép trên máy khác vẫn dùng được.'
        if(-not (Confirm-Box $message 'Chạy TechMaster qua mạng' 'Ngừng chia sẻ' -Owner $Window)){return}
    }
    Set-DeployNetworkRunBusy $Window $true
    Set-DeployNotice $status $(switch($Action){'Apply'{'Đang chia sẻ thư mục TechMaster…'}'Stop'{'Đang ngừng chia sẻ…'}default{'Đang đọc thiết lập…'}}) 'Working'
    try{
        $view.Action=$Action
        $view.Job=Start-DeployWork @'
param($core,$action,$root,$account,$firewall,$private)
$ErrorActionPreference='Stop'
. $core
$message='Đã đọc lại thiết lập.';$kind='Info';$log=''
if($action -ne 'Inspect'){
    $log=Get-DeployWindowsToolsLog 'NetworkRun'
    try{
        $result=if($action -eq 'Apply'){Set-DeployNetworkRunShare $root $account $firewall ([int[]]@($private)) $log}else{Remove-DeployNetworkRunShare $log}
        $message=$result.Message;$kind=$result.Kind
    }catch{$message=$_.Exception.GetBaseException().Message;$kind='Error';Write-DeployWindowsToolsLog $log 'failed' $message}
}
[pscustomobject]@{State=(Get-DeployNetworkRunState $root);Message=$message;Kind=$kind;Log=$log}
'@ @((Join-Path $PSScriptRoot 'NetworkRun.Core.ps1'),$Action,$view.Root,$account,[bool]($Window.FindName('Firewall').IsChecked -eq $true),$private)
        $view.Timer.Start()
    }catch{
        $view.Job=$null;Set-DeployNetworkRunBusy $Window $false
        Set-DeployNotice $status $_.Exception.GetBaseException().Message 'Error'
    }
}
function New-DeployNetworkRunWindow([string]$Root,$Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'NetworkRunWindow.xml')
    $window.Tag=@{Job=$null;Action='';State=$null;Root=$Root;Timer=$null}
    $window.FindName('RootPath').Text=$Root
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $window=$sender.Tag;$view=$window.Tag;$job=$view.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$view.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            Set-DeployNetworkRunView $window $r.State
            if($r.Log){$window.FindName('Log').Text='Nhật ký: '+$r.Log}
            if($view.Action -eq 'Inspect'){
                if($r.State.RootError){$r.Message=$r.State.RootError;$r.Kind='Attention'}
                elseif(@($r.State.SourceProblems).Count){$r.Message='Có tệp chương trình khác danh sách cập nhật; cập nhật lại app trước khi chia sẻ.';$r.Kind='Attention'}
                elseif($r.State.Active){$r.Message='TechMaster đang được chia sẻ. Trên máy kia mở đường dẫn ở phần Trên máy kia.';$r.Kind='Success'}
                else{$r.Message='Chọn tài khoản rồi bấm Chia sẻ TechMaster.';$r.Kind='Info'}
            }
            Set-DeployNotice ($window.FindName('Status')) $r.Message $r.Kind
        }catch{Set-DeployNotice ($window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{Set-DeployNetworkRunBusy $window $false}
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('CopyPath').Add_Click({
        param($sender,$event)
        $window=[Windows.Window]::GetWindow($sender);$text=[string]$window.FindName('ClientPath').Text
        if(-not $text){return}
        try{[Windows.Clipboard]::SetText($text);Set-DeployNotice ($window.FindName('Status')) ('Đã sao chép: '+$text) 'Success'}
        catch{Set-DeployNotice ($window.FindName('Status')) 'Chưa sao chép được; thử lại.' 'Error'}
    })
    $window.FindName('Apply').Add_Click({param($sender,$event)Start-DeployNetworkRunTask ([Windows.Window]::GetWindow($sender)) 'Apply'})
    $window.FindName('StopShare').Add_Click({param($sender,$event)Start-DeployNetworkRunTask ([Windows.Window]::GetWindow($sender)) 'Stop'})
    $window.FindName('Refresh').Add_Click({param($sender,$event)Start-DeployNetworkRunTask ([Windows.Window]::GetWindow($sender)) 'Inspect'})
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_ContentRendered({param($sender,$event)Start-DeployNetworkRunTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployNetworkRun([string]$Root,$Owner=$null){$view=New-DeployNetworkRunWindow $Root $Owner;[void]$view.ShowDialog()}
