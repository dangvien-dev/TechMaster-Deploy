# Local accounts used only for LAN sharing: copiers scanning to a folder, file shares, shared printers.
# They can sign in over the network only: local, Remote Desktop, batch and service logons are denied and
# the accounts are hidden from the sign-in screen. Folders, share permissions and firewall stay manual.
# An existing account with the same name that TechMaster did not create is never changed.
. (Join-Path $PSScriptRoot 'Windows.Tools.ps1')
$script:DeployLanMarker='TechMaster LAN:'
$script:DeployLanRoles=@(
    [pscustomobject]@{Role='Scan';Name='scan';Label='Scan vào thư mục';Purpose='Máy photocopy / máy scan lưu file vào thư mục chia sẻ'},
    [pscustomobject]@{Role='Share';Name='share';Label='Chia sẻ file';Purpose='Máy khác mở thư mục chia sẻ'},
    [pscustomobject]@{Role='Print';Name='print';Label='Chia sẻ máy in';Purpose='Máy khác kết nối máy in chia sẻ'})
$script:DeployLanDenyRights=@('SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight','SeDenyBatchLogonRight','SeDenyServiceLogonRight')
$script:DeployLanUsersSid='S-1-5-32-545'
$script:DeployLanAdminsSid='S-1-5-32-544'
function Initialize-DeployLanNative {
    if(-not ('TechMaster.LanAccountsNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'LanAccounts.Native.cs')}
}
function Assert-DeployLanAdmin {
    $who=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not ([Security.Principal.WindowsPrincipal]::new($who)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Mở TechMaster Deploy bằng quyền Administrator để tạo tài khoản.'}
}
function Get-DeployLanAccountRights([string]$Sid) {Initialize-DeployLanNative;@([TechMaster.LanAccountsNative]::GetRights($Sid))}
function Add-DeployLanAccountRights([string]$Sid,[string[]]$Rights) {Initialize-DeployLanNative;[TechMaster.LanAccountsNative]::AddRights($Sid,$Rights)}
function Remove-DeployLanAccountRights([string]$Sid) {Initialize-DeployLanNative;[TechMaster.LanAccountsNative]::RemoveAllRights($Sid)}
function Get-DeployLanGroupSids([string]$Name) {Initialize-DeployLanNative;@([TechMaster.LanAccountsNative]::LocalGroupSids($Name))}
function Test-DeployLanPasswordMatch([Security.SecureString]$Password,[Security.SecureString]$Confirm) {Initialize-DeployLanNative;[TechMaster.LanAccountsNative]::SecureEquals($Password,$Confirm)}
function Open-DeployLanHiddenKey([bool]$Write) {
    $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
    $root=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
    try{
        $path='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if($Write){$root.CreateSubKey($path)}else{$root.OpenSubKey($path)}
    }finally{$root.Dispose()}
}
function Get-DeployLanHidden([string]$Name) {
    $key=Open-DeployLanHiddenKey $false
    if(-not $key){return $false}
    try{return ($Name -in @($key.GetValueNames())) -and $key.GetValueKind($Name) -eq [Microsoft.Win32.RegistryValueKind]::DWord -and [int]$key.GetValue($Name) -eq 0}finally{$key.Dispose()}
}
function Set-DeployLanHidden([string]$Name) {
    $key=Open-DeployLanHiddenKey $true
    try{$key.SetValue($Name,0,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()}finally{$key.Dispose()}
}
function Remove-DeployLanHidden([string]$Name) {
    $key=Open-DeployLanHiddenKey $true
    try{$key.DeleteValue($Name,$false)}finally{$key.Dispose()}
}
function Get-DeployLanRole([string]$Role) {
    $spec=@($script:DeployLanRoles | Where-Object {$_.Role -ceq $Role})
    if($spec.Count -ne 1){throw ('Chức năng không hợp lệ: '+$Role)}
    return $spec[0]
}
function Find-DeployLanUser([string]$Name) {@(Get-LocalUser -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $Name})[0]}
function Test-DeployLanOwned($User) {[bool]($User -and ([string]$User.Description).StartsWith($script:DeployLanMarker))}
function Get-DeployLanAccountState {
    foreach($spec in $script:DeployLanRoles){
        $state=[pscustomobject]@{Role=$spec.Role;Name=$spec.Name;Label=$spec.Label;Purpose=$spec.Purpose;Exists=$false;Owned=$false;Enabled=$false;Admin=$false;Hidden=$false;Locked=$false;CanApply=$true;Status='';Error=''}
        try{
            $user=Find-DeployLanUser $spec.Name
            if(-not $user){$state.Status='Chưa có: sẽ tạo mới';$state;continue}
            $state.Exists=$true;$state.Owned=Test-DeployLanOwned $user;$state.Enabled=[bool]$user.Enabled
            if(-not $state.Owned){
                $state.CanApply=$false
                $state.Status="Đã có tài khoản '$($spec.Name)' không do TechMaster tạo: không thay đổi. Kiểm tra tài khoản này trong Quản lý tài khoản."
                $state;continue
            }
            $sid=[string]$user.SID.Value
            $state.Admin=@(Get-DeployLanGroupSids $spec.Name) -contains $script:DeployLanAdminsSid
            $rights=@(Get-DeployLanAccountRights $sid)
            $state.Locked=-not @($script:DeployLanDenyRights | Where-Object {$rights -notcontains $_}).Count
            $state.Hidden=Get-DeployLanHidden $spec.Name
            if($state.Admin){$state.CanApply=$false;$state.Status='Tài khoản đang thuộc nhóm Administrators: không dùng cho chia sẻ. Gỡ khỏi nhóm này trước.'}
            else{
                $issues=@()
                if(-not $state.Enabled){$issues+='đang bị tắt'}
                if(-not $state.Locked){$issues+='chưa chặn đăng nhập trực tiếp'}
                if(-not $state.Hidden){$issues+='chưa ẩn khỏi màn hình đăng nhập'}
                $state.Status='Đã có (TechMaster tạo)'+$(if($issues.Count){': '+($issues -join ', ')+'. Nhập mật khẩu để cập nhật.'}else{'. Nhập mật khẩu mới nếu muốn đổi.'})
            }
        }catch{
            $state.CanApply=$false;$state.Error=$_.Exception.GetBaseException().Message
            $state.Status='Chưa đọc được tài khoản: '+$state.Error
        }
        $state
    }
}
function ConvertTo-DeployLanError([string]$Message) {
    if($Message -match '(?i)password'){return 'Mật khẩu chưa đạt chính sách mật khẩu của Windows (độ dài / độ phức tạp). Dùng mật khẩu dài hơn, có chữ hoa, chữ thường và số. Chi tiết: '+$Message}
    return $Message
}
function Set-DeployLanAccount([string]$Role,[Security.SecureString]$Password,[string]$LogPath) {
    $spec=Get-DeployLanRole $Role
    $name=$spec.Name
    # Windows refuses network sign-in for accounts with a blank password.
    if(-not $Password -or $Password.Length -eq 0){throw ('Nhập mật khẩu cho tài khoản '+$name+'.')}
    $user=Find-DeployLanUser $name
    if($user -and -not (Test-DeployLanOwned $user)){throw "Đã có tài khoản '$name' không do TechMaster tạo; app không thay đổi tài khoản này."}
    if($user -and (@(Get-DeployLanGroupSids $name) -contains $script:DeployLanAdminsSid)){throw "Tài khoản '$name' đang thuộc nhóm Administrators; app không dùng tài khoản quản trị cho chia sẻ."}
    $created=$false;$sid=''
    Write-DeployWindowsToolsLog $LogPath 'lan-account-request' @{Role=$Role;Name=$name;Exists=[bool]$user}
    try{
        if(-not $user){
            try{New-LocalUser -Name $name -Password $Password -FullName ('Chia sẻ LAN - '+$spec.Label) -Description ($script:DeployLanMarker+' '+$name) -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires -ErrorAction Stop | Out-Null}
            catch{throw (ConvertTo-DeployLanError $_.Exception.GetBaseException().Message)}
            $created=$true
            Write-DeployWindowsToolsLog $LogPath 'lan-account-created' @{Name=$name}
        }else{
            try{Set-LocalUser -Name $name -Password $Password -PasswordNeverExpires $true -UserMayChangePassword $false -AccountNeverExpires -ErrorAction Stop}
            catch{throw (ConvertTo-DeployLanError $_.Exception.GetBaseException().Message)}
            if(-not $user.Enabled){Enable-LocalUser -Name $name -ErrorAction Stop}
            Write-DeployWindowsToolsLog $LogPath 'lan-account-updated' @{Name=$name;WasEnabled=[bool]$user.Enabled}
        }
        $user=Find-DeployLanUser $name
        if(-not $user){throw ('Windows chưa ghi nhận tài khoản '+$name+'.')}
        $sid=[string]$user.SID.Value
        if(@(Get-DeployLanGroupSids $name) -notcontains $script:DeployLanUsersSid){Add-LocalGroupMember -SID $script:DeployLanUsersSid -Member $name -ErrorAction Stop}
        Add-DeployLanAccountRights $sid $script:DeployLanDenyRights
        Set-DeployLanHidden $name
        # Read everything back: success is only reported for what Windows confirms.
        $rights=@(Get-DeployLanAccountRights $sid)
        $missing=@($script:DeployLanDenyRights | Where-Object {$rights -notcontains $_})
        $groups=@(Get-DeployLanGroupSids $name)
        $after=Find-DeployLanUser $name
        $problems=@()
        if($missing.Count){$problems+=('chưa chặn: '+($missing -join ', '))}
        if(-not (Get-DeployLanHidden $name)){$problems+='chưa ẩn khỏi màn hình đăng nhập'}
        if(-not $after.Enabled){$problems+='tài khoản đang tắt'}
        if($null -ne $after.PasswordExpires){$problems+='mật khẩu vẫn có hạn'}
        if($groups -contains $script:DeployLanAdminsSid){$problems+='thuộc nhóm Administrators'}
        if($groups -notcontains $script:DeployLanUsersSid){$problems+='chưa thuộc nhóm Users'}
        Write-DeployWindowsToolsLog $LogPath 'lan-account-verified' @{Name=$name;Sid=$sid;Rights=$rights;Groups=$groups;Problems=$problems}
        if($problems.Count){throw ('Windows chưa xác nhận đủ thiết lập cho '+$name+': '+($problems -join '; ')+'.')}
    }catch{
        $failure=$_.Exception.GetBaseException().Message
        Write-DeployWindowsToolsLog $LogPath 'lan-account-failed' @{Name=$name;Created=$created;Error=$failure}
        if($created){
            # Never leave a half-configured new account that could sign in locally.
            $undo=@()
            try{Remove-LocalUser -Name $name -ErrorAction Stop}catch{$undo+=('xoá tài khoản: '+$_.Exception.GetBaseException().Message)}
            if($sid){try{Remove-DeployLanAccountRights $sid}catch{$undo+=('gỡ quyền: '+$_.Exception.GetBaseException().Message)}}
            try{Remove-DeployLanHidden $name}catch{$undo+=('bỏ ẩn: '+$_.Exception.GetBaseException().Message)}
            Write-DeployWindowsToolsLog $LogPath 'lan-account-rolled-back' @{Name=$name;Problems=$undo}
            $failure+=$(if($undo.Count){' Chưa hoàn tác được: '+($undo -join '; ')+'. Xoá tài khoản '+$name+' trong Quản lý tài khoản.'}else{' Đã xoá tài khoản vừa tạo.'})
        }
        throw $failure
    }
    [pscustomobject]@{Name=$name;Created=$created;Logon=($env:COMPUTERNAME+'\'+$name)}
}
function Invoke-DeployLanAccounts($Requests,[string]$LogPath) {
    Assert-DeployLanAdmin
    $items=@($Requests | Where-Object {$_})
    if(-not $items.Count){throw 'Chọn ít nhất một tài khoản.'}
    $lines=@();$done=0;$failed=0
    foreach($item in $items){
        $name=[string]$item.Role
        try{$name=(Get-DeployLanRole $item.Role).Name}catch{}
        try{
            $result=Set-DeployLanAccount $item.Role $item.Password $LogPath
            $done++
            $lines+=('✓ '+$result.Name+': '+$(if($result.Created){'đã tạo'}else{'đã cập nhật mật khẩu và thiết lập'})+'. Đăng nhập từ máy khác / máy photocopy: '+$result.Logon)
        }catch{
            $failed++
            $lines+=('✗ '+$name+': '+$_.Exception.GetBaseException().Message)
        }
    }
    if($done){$lines+='Tài khoản chỉ đăng nhập qua mạng LAN: không đăng nhập tại máy / Remote Desktop, ẩn khỏi màn hình đăng nhập, mật khẩu không hết hạn. Thư mục chia sẻ, quyền và tường lửa vẫn cấu hình riêng.'}
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($failed){if($done){'Attention'}else{'Error'}}else{'Success'});Log=$LogPath}
}
