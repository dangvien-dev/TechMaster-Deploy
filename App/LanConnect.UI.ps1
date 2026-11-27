function Set-DeployConnectDrives($Window) {
    $combo=$Window.FindName('Drive');$previous=[string]$combo.SelectedItem
    $items=@('Không')
    try{$items+=@(Get-DeployFreeDriveLetters | ForEach-Object {$_+':'})}catch{}
    $combo.ItemsSource=$items
    $combo.SelectedItem=if($previous -and $items -contains $previous){$previous}else{'Không'}
}
function Set-DeployConnectBusy($Window,[bool]$Busy) {
    $Window.FindName('Choices').IsEnabled=-not $Busy
    foreach($name in 'Connect','RemoveSaved','Close'){$Window.FindName($name).IsEnabled=-not $Busy}
}
function Start-DeployConnectTask($Window,[ValidateSet('Connect','Remove')][string]$Action) {
    $view=$Window.Tag;if($view.Job){return}
    $status=$Window.FindName('Status')
    $path=([string]$Window.FindName('UncPath').Text).Trim()
    try{$target=ConvertFrom-DeployShareUnc $path}catch{Set-DeployNotice $status $_.Exception.GetBaseException().Message 'Attention';return}
    $account=([string]$Window.FindName('Account').Text).Trim();$password=$null;$drive=''
    if($Action -eq 'Connect'){
        if(-not $account){Set-DeployNotice $status 'Nhập tài khoản trên máy chia sẻ (ví dụ share).' 'Attention';return}
        $password=$Window.FindName('Password').SecurePassword
        if($password.Length -eq 0){Set-DeployNotice $status 'Nhập mật khẩu của tài khoản trên máy chia sẻ.' 'Attention';return}
        $password.MakeReadOnly()
        $choice=[string]$Window.FindName('Drive').SelectedItem
        if($choice -and $choice -ne 'Không'){$drive=$choice}
    }elseif(-not (Confirm-Box ('Xoá mật khẩu đã lưu cho máy '+$target.Server+'? Lần sau mở thư mục chia sẻ trên máy đó sẽ phải nhập lại.') 'Kết nối thư mục chia sẻ' 'Xoá' -Owner $Window)){return}
    Set-DeployConnectBusy $Window $true
    Set-DeployNotice $status $(if($Action -eq 'Connect'){'Đang thử đăng nhập '+$target.Unc+'…'}else{'Đang xoá mật khẩu đã lưu…'}) 'Working'
    try{
        $view.Action=$Action
        $view.Job=Start-DeployWork @'
param($core,$action,$path,$account,$password,$shortcut,$drive)
$ErrorActionPreference='Stop'
. $core
$log=Get-DeployWindowsToolsLog 'LanConnect'
try{
    $result=if($action -eq 'Connect'){Connect-DeployLanShare $path $account $password $shortcut $drive $log}else{Remove-DeployLanConnection $path $log}
    [pscustomobject]@{Message=$result.Message;Kind=$result.Kind;Log=$log}
}catch{
    $message=$_.Exception.GetBaseException().Message
    Write-DeployWindowsToolsLog $log 'failed' $message
    [pscustomobject]@{Message=$message;Kind='Error';Log=$log}
}
'@ @((Join-Path $PSScriptRoot 'LanConnect.Core.ps1'),$Action,$path,$account,$password,[bool]($Window.FindName('Shortcut').IsChecked -eq $true),$drive)
        $view.Timer.Start()
    }catch{
        $view.Job=$null;Set-DeployConnectBusy $Window $false
        Set-DeployNotice $status $_.Exception.GetBaseException().Message 'Error'
    }
}
function New-DeployConnectWindow($Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'LanConnectWindow.xml')
    $window.Tag=@{Job=$null;Action='';Timer=$null}
    $window.FindName('Account').Text='share'
    $window.FindName('Subtitle').Text='Lưu cho tài khoản Windows '+[Security.Principal.WindowsIdentity]::GetCurrent().Name+' trên máy này: người dùng mở thư mục chia sẻ không phải nhập mật khẩu.'
    Set-DeployConnectDrives $window
    Set-DeployNotice ($window.FindName('Status')) 'Nhập đường dẫn, tài khoản và mật khẩu của máy chia sẻ rồi bấm Kiểm tra & lưu.' 'Info'
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $window=$sender.Tag;$view=$window.Tag;$job=$view.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$view.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            if($r.Log){$window.FindName('Log').Text='Nhật ký: '+$r.Log}
            Set-DeployNotice ($window.FindName('Status')) $r.Message $r.Kind
        }catch{Set-DeployNotice ($window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{
            # The password never stays on screen after an attempt.
            $window.FindName('Password').Clear()
            Set-DeployConnectDrives $window
            Set-DeployConnectBusy $window $false
        }
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    $window.FindName('Connect').Add_Click({param($sender,$event)Start-DeployConnectTask ([Windows.Window]::GetWindow($sender)) 'Connect'})
    $window.FindName('RemoveSaved').Add_Click({param($sender,$event)Start-DeployConnectTask ([Windows.Window]::GetWindow($sender)) 'Remove'})
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null;$sender.FindName('Password').Clear()})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployConnect($Owner=$null){$view=New-DeployConnectWindow $Owner;[void]$view.ShowDialog()}
