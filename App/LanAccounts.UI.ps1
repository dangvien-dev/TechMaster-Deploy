function Set-DeployLanAccountsView($Window,$States) {
    $Window.Tag.States=@($States)
    $computer=[string]$env:COMPUTERNAME
    $Window.FindName('Computer').Text='Máy '+$computer+': máy khác / máy photocopy đăng nhập bằng '+$computer+'\scan, '+$computer+'\share hoặc '+$computer+'\print với mật khẩu bạn đặt.'
    foreach($state in @($States | Where-Object {$_})){
        $role=[string]$state.Role
        if(-not $Window.FindName('Use'+$role)){continue}
        $Window.FindName('State'+$role).Text=[string]$state.Status
        $allowed=[bool]$state.CanApply
        $Window.FindName('Use'+$role).IsEnabled=$allowed
        if(-not $allowed){$Window.FindName('Use'+$role).IsChecked=$false}
        foreach($name in 'Password','Confirm'){$Window.FindName($name+$role).IsEnabled=$allowed}
    }
}
function Get-DeployLanAccountRequests($Window) {
    $requests=@();$problems=@()
    foreach($spec in $script:DeployLanRoles){
        if($Window.FindName('Use'+$spec.Role).IsChecked -ne $true){continue}
        $password=$Window.FindName('Password'+$spec.Role).SecurePassword
        $confirm=$Window.FindName('Confirm'+$spec.Role).SecurePassword
        try{
            if($password.Length -eq 0){$problems+=('Nhập mật khẩu cho '+$spec.Name+'.');continue}
            if(-not (Test-DeployLanPasswordMatch $password $confirm)){$problems+=('Hai ô mật khẩu của '+$spec.Name+' chưa khớp.');continue}
        }finally{$confirm.Dispose()}
        $password.MakeReadOnly()
        $requests+=[pscustomobject]@{Role=$spec.Role;Password=$password}
    }
    [pscustomobject]@{Requests=$requests;Problems=$problems}
}
function Clear-DeployLanPasswords($Window) {
    foreach($spec in $script:DeployLanRoles){
        foreach($name in 'Password','Confirm'){$Window.FindName($name+$spec.Role).Clear()}
        $Window.FindName('Use'+$spec.Role).IsChecked=$false
    }
}
function Set-DeployLanAccountsBusy($Window,[bool]$Busy) {
    $Window.FindName('Choices').IsEnabled=-not $Busy
    foreach($name in 'Apply','Refresh','OpenManager','Close'){$Window.FindName($name).IsEnabled=-not $Busy}
}
function Start-DeployLanAccountsTask($Window,[ValidateSet('Inspect','Apply')][string]$Action) {
    $state=$Window.Tag;if($state.Job){return}
    $requests=@()
    if($Action -eq 'Apply'){
        $form=Get-DeployLanAccountRequests $Window
        if(@($form.Problems).Count){Set-DeployNotice ($Window.FindName('Status')) (@($form.Problems) -join "`n") 'Attention';return}
        $requests=@($form.Requests)
        if(-not $requests.Count){Set-DeployNotice ($Window.FindName('Status')) 'Tích ít nhất một tài khoản và nhập mật khẩu.' 'Attention';return}
        $names=@($requests | ForEach-Object {'• '+(Get-DeployLanRole $_.Role).Name})
        $message='Tạo / cập nhật tài khoản chia sẻ LAN trên máy '+$env:COMPUTERNAME+'?'+"`n`n"+($names -join "`n")+"`n`n"+'Tài khoản chỉ đăng nhập qua mạng LAN: không đăng nhập tại máy, không Remote Desktop, ẩn khỏi màn hình đăng nhập, mật khẩu không hết hạn. Tài khoản đã có (do TechMaster tạo) sẽ được đặt mật khẩu mới.'
        if(-not (Confirm-Box $message 'Tài khoản chia sẻ LAN' 'Tạo / cập nhật' -Owner $Window)){return}
    }
    Set-DeployLanAccountsBusy $Window $true
    Set-DeployNotice ($Window.FindName('Status')) $(if($Action -eq 'Apply'){'Đang tạo / cập nhật tài khoản…'}else{'Đang đọc tài khoản…'}) 'Working'
    try{
        $state.Action=$Action
        $state.Job=Start-DeployWork @'
param($core,$action,$requests)
$ErrorActionPreference='Stop'
. $core
$message='Đã đọc lại tài khoản.';$kind='Info';$log=''
if($action -eq 'Apply'){
    $log=Get-DeployWindowsToolsLog 'LanAccounts'
    try{$result=Invoke-DeployLanAccounts $requests $log;$message=$result.Message;$kind=$result.Kind}
    catch{$message=$_.Exception.GetBaseException().Message;$kind='Error';Write-DeployWindowsToolsLog $log 'failed' $message}
}
$states=@();$stateError=''
try{$states=@(Get-DeployLanAccountState)}catch{$stateError=$_.Exception.GetBaseException().Message}
[pscustomobject]@{States=$states;StateError=$stateError;Message=$message;Kind=$kind;Log=$log}
'@ @((Join-Path $PSScriptRoot 'LanAccounts.Core.ps1'),$Action,$requests)
        $state.Timer.Start()
    }catch{
        $state.Job=$null;Set-DeployLanAccountsBusy $Window $false
        Set-DeployNotice ($Window.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
    }
}
function New-DeployLanAccountsWindow($Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'LanAccountsWindow.xml')
    $window.Tag=@{Job=$null;Action='';States=@();Timer=$null}
    $timer=New-DeployTimer 200 {
        param($sender,$event)
        $view=$sender.Tag;$state=$view.Tag;$job=$state.Job
        if(-not $job -or -not $job.Async.IsCompleted){return}
        $sender.Stop();$state.Job=$null
        try{
            $r=@(Receive-DeployWork $job)[-1]
            Set-DeployLanAccountsView $view $r.States
            if($r.Log){$view.FindName('Log').Text='Nhật ký: '+$r.Log}
            # Passwords never stay on screen after an attempt.
            if($state.Action -eq 'Apply'){Clear-DeployLanPasswords $view}
            if($r.StateError){$r.Message+="`nChưa đọc được danh sách tài khoản: "+$r.StateError;if($r.Kind -ne 'Error'){$r.Kind='Attention'}}
            elseif($state.Action -eq 'Inspect' -and @($r.States | Where-Object {$_.Error}).Count){$r.Message='Đã đọc tài khoản; có mục chưa đọc được. Xem trạng thái từng tài khoản.';$r.Kind='Attention'}
            Set-DeployNotice ($view.FindName('Status')) $r.Message $r.Kind
        }catch{Set-DeployNotice ($view.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'}
        finally{Set-DeployLanAccountsBusy $view $false;Set-DeployLanAccountsView $view $state.States}
    }
    $timer.Tag=$window;$window.Tag.Timer=$timer
    foreach($spec in $script:DeployLanRoles){
        # Typing a password selects that account.
        $window.FindName('Password'+$spec.Role).Add_PasswordChanged({
            param($sender,$event)
            $view=[Windows.Window]::GetWindow($sender);$box=$view.FindName('Use'+[string]$sender.Tag)
            if($box.IsEnabled -and $sender.SecurePassword.Length -gt 0){$box.IsChecked=$true}
        })
    }
    $window.FindName('Apply').Add_Click({param($sender,$event)Start-DeployLanAccountsTask ([Windows.Window]::GetWindow($sender)) 'Apply'})
    $window.FindName('Refresh').Add_Click({param($sender,$event)Start-DeployLanAccountsTask ([Windows.Window]::GetWindow($sender)) 'Inspect'})
    $window.FindName('OpenManager').Add_Click({
        # Local Users and Groups is missing on Home editions; netplwiz exists on every edition.
        $console=Join-Path $env:WINDIR 'System32\lusrmgr.msc'
        if(Test-Path -LiteralPath $console){Start-Process -FilePath $console -ErrorAction Stop}else{Start-Process -FilePath 'netplwiz.exe' -ErrorAction Stop}
    })
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    $window.Add_ContentRendered({param($sender,$event)Start-DeployLanAccountsTask $sender 'Inspect'})
    $window.Add_Closing({param($sender,$event)if($sender.Tag.Job){$event.Cancel=$true}})
    $window.Add_Closed({param($sender,$event)$sender.Tag.Timer.Stop();$sender.Tag.Timer.Tag=$null;Clear-DeployLanPasswords $sender})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployLanAccounts($Owner=$null){$view=New-DeployLanAccountsWindow $Owner;[void]$view.ShowDialog()}
