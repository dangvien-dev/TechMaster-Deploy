function Select-DeployFolder([string]$Description,[string]$Start='') {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    try{
        $dialog.Description=$Description;$dialog.ShowNewFolderButton=$true
        if($Start -and (Test-Path -LiteralPath $Start)){$dialog.SelectedPath=$Start}
        if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return $dialog.SelectedPath}
        return $null
    }finally{$dialog.Dispose()}
}
function Set-DeployShareAccessChoice($Combo,[string]$Access) {
    foreach($item in $Combo.Items){if([string]$item.Tag -ceq $Access){$Combo.SelectedItem=$item;return}}
    $Combo.SelectedIndex=0
}
function Get-DeployShareAccessChoice($Combo) {if($Combo.SelectedItem){[string]$Combo.SelectedItem.Tag}else{'None'}}
function Set-DeployShareView($Window,$State) {
    $view=$Window.Tag;$view.State=$State
    $computer=[string]$State.Computer
    $Window.FindName('Subtitle').Text='Máy '+$computer+': chia sẻ thư mục cho tài khoản scan / share / print trong mạng LAN.'
    $folder=$State.Folder
    $Window.FindName('FolderNote').Text=if($State.FolderError){'✗ '+$State.FolderError}elseif(-not $folder){'Bấm Chọn thư mục… để chọn thư mục cần chia sẻ.'}elseif($State.Existing){'Thư mục đang được chia sẻ là \\'+$computer+'\'+$State.Existing.Name+'; bấm áp dụng để cập nhật quyền.'+$(if($folder.Warning){' '+$folder.Warning}else{''})}else{$(if($folder.Warning){'! '+$folder.Warning}else{'Thư mục chưa được chia sẻ.'})}
    # A newly chosen folder loads its current share name and permissions; the same folder keeps what was typed.
    if($folder -and $view.LoadedPath -ine $folder.Path){
        $view.LoadedPath=$folder.Path
        $Window.FindName('FolderPath').Text=$folder.Path
        $Window.FindName('ShareName').Text=if($State.Existing){[string]$State.Existing.Name}else{[string]$folder.DefaultName}
        foreach($account in @($State.Accounts)){
            $access=if($State.Existing -and $State.CurrentAccess.ContainsKey($account.Account)){[string]$State.CurrentAccess[$account.Account]}elseif($account.Role -eq 'Share' -and $account.Exists){'Change'}else{'None'}
            Set-DeployShareAccessChoice ($Window.FindName('Access'+$account.Role)) $access
        }
    }
    foreach($account in @($State.Accounts)){
        $combo=$Window.FindName('Access'+$account.Role)
        $combo.IsEnabled=[bool]$account.Exists
        if(-not $account.Exists){Set-DeployShareAccessChoice $combo 'None'}
        if($null -eq $combo.SelectedItem){Set-DeployShareAccessChoice $combo 'None'}
        $Window.FindName('AccessNote'+$account.Role).Text=if($account.Exists){'Đăng nhập: '+$account.Account}else{'Chưa có tài khoản: tạo ở Tài khoản chia sẻ LAN.'}
    }
    $Window.FindName('ShareHint').Text='Máy khác vào bằng \\'+$computer+'\'+([string]$Window.FindName('ShareName').Text).Trim()
    $public=@($State.Profiles | Where-Object {$_.Category -eq 'Public'})
    $profiles=@($State.Profiles | ForEach-Object {'• '+$_.Alias+' ('+$_.Name+'): '+$(switch($_.Category){'Public'{'Public — máy khác chưa vào được'}'Private'{'Private'}'DomainAuthenticated'{'Domain'}default{[string]$_.Category}})})
    $network=@()
    if($State.ProfileError){$network+=('Chưa đọc được mạng: '+$State.ProfileError)}elseif($profiles.Count){$network+=$profiles}else{$network+='Chưa có kết nối mạng.'}
    if($State.FirewallReady){$network+='Luật tường lửa của TechMaster đã bật.'}
    if($State.Server -and $State.Server -ne 'Running'){$network+='Dịch vụ Server (LanmanServer) đang tắt; app sẽ bật khi chia sẻ.'}
    $Window.FindName('NetworkState').Text=$network -join "`n"
    $private=$Window.FindName('MakePrivate');$private.IsEnabled=[bool]$public.Count
    if(-not $public.Count){$private.IsChecked=$false}
    $Window.FindName('SharesList').Text=if($State.SharesError){'Chưa đọc được: '+$State.SharesError}elseif(@($State.Shares).Count){(@($State.Shares | ForEach-Object {'\\'+$computer+'\'+$_.Name+'  →  '+$_.Path}) -join "`n")}else{'Chưa có thư mục nào được chia sẻ.'}
}
function Set-DeployShareBusy($Window,[bool]$Busy) {
    $Window.FindName('Choices').IsEnabled=-not $Busy
    foreach($name in 'Apply','Refresh','Close'){$Window.FindName($name).IsEnabled=-not $Busy}
}
function Start-DeployShareTask($Window,[ValidateSet('Inspect','Apply')][string]$Action) {
    $view=$Window.Tag;if($view.Job){return}
    $path=([string]$Window.FindName('FolderPath').Text).Trim()
    $name=([string]$Window.FindName('ShareName').Text).Trim()
    $grants=@();$private=@()
    if($Action -eq 'Apply'){
        $status=$Window.FindName('Status')
        if(-not $path){Set-DeployNotice $status 'Chọn thư mục cần chia sẻ.' 'Attention';return}
        if(-not (Test-DeployShareName $name)){Set-DeployNotice $status 'Tên chia sẻ không hợp lệ: 1–80 ký tự, không chứa \ / [ ] : | < > + = ; , ? * " và không kết thúc bằng $ hoặc dấu chấm.' 'Attention';return}
        foreach($spec in $script:DeployLanRoles){$grants+=[pscustomobject]@{Role=$spec.Role;Access=(Get-DeployShareAccessChoice ($Window.FindName('Access'+$spec.Role)))}}
        $given=@($grants | Where-Object {$_.Access -ne 'None'})
        if(-not $given.Count){Set-DeployNotice $status 'Chọn Chỉ đọc hoặc Đọc & ghi cho ít nhất một tài khoản.' 'Attention';return}
        if($Window.FindName('MakePrivate').IsChecked -eq $true){$private=@($view.State.Profiles | Where-Object {$_.Category -eq 'Public'} | ForEach-Object {[int]$_.Index})}
        $summary=@($grants | ForEach-Object {'• '+(Get-DeployLanRole $_.Role).Name+': '+$script:DeployShareAccessLabels[$_.Access]})
        $message='Chia sẻ '+$path+' thành \\'+$env:COMPUTERNAME+'\'+$name+'?'+"`n`n"+($summary -join "`n")
        if($Window.FindName('Firewall').IsChecked -eq $true){$message+="`n`nMở tường lửa cho chia sẻ file trong LAN (chỉ mạng Private / Domain)."}
        if($private.Count){$message+="`nChuyển "+$private.Count+' mạng Public sang Private.'}
        if(-not (Confirm-Box $message 'Chia sẻ thư mục' 'Chia sẻ' -Owner $Window)){return}
    }
    Set-DeployShareBusy $Window $true
    Set-DeployNotice ($Window.FindName('Status')) $(if($Action -eq 'Apply'){'Đang chia sẻ và cấp quyền…'}else{'Đang đọc thiết lập chia sẻ…'}) 'Working'
    try{
        $view.Action=$Action
        $view.Job=Start-DeployWork @'
param($core,$action,$path,$name,$grants,$firewall,$private)
$ErrorActionPreference='Stop'
. $core
$message='Đã đọc lại thiết lập chia sẻ.';$kind='Info';$log=''
if($action -eq 'Apply'){
    $log=Get-DeployWindowsToolsLog 'LanShare'
    try{$result=Set-DeployFolderShare $path $name $grants $firewall ([int[]]@($private)) $log;$message=$result.Message;$kind=$result.Kind}
    catch{$message=$_.Exception.GetBaseException().Message;$kind='Error';Write-DeployWindowsToolsLog $log 'failed' $message}
}
$state=Get-DeployShareState $path
[pscustomobject]@{State=$state;Message=$message;Kind=$kind;Log=$log}
'@ @((Join-Path $PSScriptRoot 'LanShare.Core.ps1'),$Action,$path,$name,$grants,[bool]($Window.FindName('Firewall').IsChecked -eq $true),$private)
        $view.Timer.Start()
    }catch{
        $view.Job=$null;Set-DeployShareBusy $Window $false
        Set-DeployNotice ($Window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
    }
}
function New-DeployShareWindow($Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'LanShareWindow.xml')
    $window.Tag=@{Job=$null;Action='';State=$null;LoadedPath='';Timer=$null}
    foreach($spec in $script:DeployLanRoles){Set-DeployShareAccessChoice ($window.FindName('Access'+$spec.Role)) 'None'}
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $window=$sender.Tag;$view=$window.Tag;$job=$view.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$view.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            Set-DeployShareView $window $r.State
            if($r.Log){$window.FindName('Log').Text='Nhật ký: '+$r.Log}
            if($view.Action -eq 'Inspect' -and $r.State.FolderError){$r.Message=$r.State.FolderError;$r.Kind='Attention'}
            Set-DeployNotice ($window.FindName('Status')) $r.Message $r.Kind
        }catch{Set-DeployNotice ($window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{Set-DeployShareBusy $window $false}
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('Browse').Add_Click({
        param($sender,$event)
        $window=[Windows.Window]::GetWindow($sender)
        $picked=Select-DeployFolder 'Chọn thư mục cần chia sẻ trong mạng LAN' ([string]$window.FindName('FolderPath').Text)
        if(-not $picked){return}
        $window.FindName('FolderPath').Text=$picked
        Start-DeployShareTask $window 'Inspect'
    })
    $window.FindName('ShareName').Add_TextChanged({
        param($sender,$event)
        $window=[Windows.Window]::GetWindow($sender)
        if($window -and $window.Tag.State){$window.FindName('ShareHint').Text='Máy khác vào bằng \\'+$window.Tag.State.Computer+'\'+([string]$sender.Text).Trim()}
    })
    $window.FindName('Apply').Add_Click({param($sender,$event)Start-DeployShareTask ([Windows.Window]::GetWindow($sender)) 'Apply'})
    $window.FindName('Refresh').Add_Click({param($sender,$event)Start-DeployShareTask ([Windows.Window]::GetWindow($sender)) 'Inspect'})
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_ContentRendered({param($sender,$event)Start-DeployShareTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployShare($Owner=$null){$view=New-DeployShareWindow $Owner;[void]$view.ShowDialog()}
