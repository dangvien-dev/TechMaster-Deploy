# Client side of LAN sharing: test the account once, save it in Windows Credential Manager for the signed-in
# user, then add a desktop shortcut and, if asked, a drive letter Windows reconnects at sign-in. The user then
# opens the share without typing the password; the app never writes the password anywhere itself.
. (Join-Path $PSScriptRoot 'Windows.Tools.ps1')
function Initialize-DeployConnectNative {
    if(-not ('TechMaster.LanConnectNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'LanConnect.Native.cs')}
}
function Test-DeployShareLogon([string]$Unc,[string]$User,[Security.SecureString]$Password) {Initialize-DeployConnectNative;[int][TechMaster.LanConnectNative]::TestConnection($Unc,$User,$Password)}
function Save-DeployShareCredential([string]$Server,[string]$User,[Security.SecureString]$Password) {Initialize-DeployConnectNative;[TechMaster.LanConnectNative]::SavePassword($Server,$User,$Password)}
function Get-DeployShareCredentialUser([string]$Server) {Initialize-DeployConnectNative;[TechMaster.LanConnectNative]::SavedUser($Server)}
function Remove-DeployShareCredential([string]$Server) {Initialize-DeployConnectNative;[TechMaster.LanConnectNative]::DeletePassword($Server)}
function ConvertFrom-DeployShareUnc([string]$Path) {
    $value=([string]$Path).Trim().Replace('/','\').TrimEnd('\')
    if($value -notmatch '^\\\\([^\\\s]+)\\([^\\]+)(\\.*)?$'){throw 'Nhập đường dẫn dạng \\TÊN-MÁY\TênChiaSẻ hoặc \\192.168.1.10\TênChiaSẻ.'}
    $server=$Matches[1];$share=$Matches[2]
    if($server -match '[<>"|*?:]'){throw 'Tên máy / IP không hợp lệ.'}
    [pscustomobject]@{Server=$server;Share=$share;Unc=$value}
}
function Get-DeployShareLogonError([int]$Code) {
    switch($Code){
        5 {return 'Tài khoản chưa có quyền vào thư mục này (5). Cấp quyền ở Chia sẻ thư mục trên máy chia sẻ.'}
        53 {return 'Không tìm thấy máy chia sẻ (53). Kiểm tra tên máy / IP, cùng mạng LAN và tường lửa trên máy chia sẻ.'}
        67 {return 'Máy chia sẻ không có thư mục chia sẻ tên này (67).'}
        86 {return 'Sai mật khẩu (86).'}
        1219 {return 'Máy này đang mở máy chia sẻ bằng tài khoản khác (1219). Đóng các cửa sổ đang mở thư mục đó hoặc khởi động lại máy rồi thử lại.'}
        1272 {return 'Máy chia sẻ chỉ cho vào kiểu Guest không mật khẩu; Windows chặn vì không an toàn (1272). Dùng tài khoản có mật khẩu.'}
        1326 {return 'Sai tài khoản hoặc mật khẩu (1326).'}
        1327 {return 'Tài khoản bị hạn chế đăng nhập trên máy chia sẻ (1327).'}
        1331 {return 'Tài khoản đang bị tắt trên máy chia sẻ (1331).'}
        1909 {return 'Tài khoản bị khoá trên máy chia sẻ do nhập sai nhiều lần (1909).'}
    }
    return ('Chưa kết nối được (mã '+$Code+'): '+([ComponentModel.Win32Exception]::new($Code)).Message)
}
function Get-DeployDesktopUserSid {
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    foreach($item in @(Get-CimInstance Win32_Process -Filter ("Name='explorer.exe' AND SessionId="+$session) -ErrorAction Stop)){
        $owner=Invoke-CimMethod -InputObject $item -MethodName GetOwnerSid -ErrorAction Stop
        if($owner.ReturnValue -eq 0 -and $owner.Sid){return [string]$owner.Sid}
    }
    return ''
}
# Saved passwords belong to one Windows account: when the app was elevated with another administrator,
# saving would help that administrator, not the person using the computer.
function Assert-DeployConnectUser {
    $me=[Security.Principal.WindowsIdentity]::GetCurrent()
    $desktop='';try{$desktop=[string](Get-DeployDesktopUserSid)}catch{}
    if($desktop -and $desktop -ne $me.User.Value){
        $name=$desktop;try{$name=([Security.Principal.SecurityIdentifier]$desktop).Translate([Security.Principal.NTAccount]).Value}catch{}
        throw ('App đang chạy bằng tài khoản '+$me.Name+', còn người đang dùng máy là '+$name+'; mật khẩu lưu sẽ không có tác dụng cho người dùng. Đăng nhập Windows bằng tài khoản người dùng rồi mở app, hoặc để người dùng tự mở thư mục một lần và tích "Remember my credentials" / "Ghi nhớ thông tin đăng nhập".')
    }
}
function Get-DeployDesktopPath {[Environment]::GetFolderPath('Desktop')}
function New-DeployShareShortcut([string]$Unc,[string]$Label) {
    $name=($Label -replace '[\\/:*?"<>|]','_').Trim()
    $file=Join-Path (Get-DeployDesktopPath) ($name+'.lnk')
    $shell=New-Object -ComObject WScript.Shell
    try{$link=$shell.CreateShortcut($file);$link.TargetPath=$Unc;$link.Description=('Thư mục chia sẻ '+$Unc);$link.Save()}
    finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    if(-not (Test-Path -LiteralPath $file)){throw 'Chưa tạo được lối tắt trên Desktop.'}
    return $file
}
function Get-DeployUsedDriveLetters {
    $used=@([IO.DriveInfo]::GetDrives() | ForEach-Object {$_.Name.Substring(0,1).ToUpperInvariant()})
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Network')
    if($key){try{$used+=@($key.GetSubKeyNames() | ForEach-Object {$_.ToUpperInvariant()})}finally{$key.Dispose()}}
    @($used | Select-Object -Unique)
}
function Get-DeployFreeDriveLetters {
    $used=@(Get-DeployUsedDriveLetters)
    @('Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K','J','I','H','G') | Where-Object {$used -notcontains $_}
}
function Get-DeployDriveMapping([string]$Letter) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Network\'+$Letter)
    if(-not $key){return ''}
    try{return [string]$key.GetValue('RemotePath')}finally{$key.Dispose()}
}
# The values net use /persistent:yes stores: Windows reconnects the drive at sign-in with the saved password.
function Write-DeployDriveMapping([string]$Letter,[string]$Unc) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Network\'+$Letter)
    try{
        $key.SetValue('RemotePath',$Unc,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('UserName','',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('ProviderName','Microsoft Windows Network',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('ProviderType',0x20000,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('ConnectionType',1,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('DeferFlags',4,[Microsoft.Win32.RegistryValueKind]::DWord)
    }finally{$key.Dispose()}
}
function Connect-DeployLanShare([string]$Path,[string]$Account,[Security.SecureString]$Password,[bool]$Shortcut,[string]$Drive,[string]$LogPath) {
    $target=ConvertFrom-DeployShareUnc $Path
    $user=([string]$Account).Trim()
    if(-not $user){throw 'Nhập tài khoản trên máy chia sẻ (ví dụ share).'}
    if(-not $Password -or $Password.Length -eq 0){throw 'Nhập mật khẩu của tài khoản trên máy chia sẻ.'}
    $letter=([string]$Drive).Trim().TrimEnd(':').ToUpperInvariant()
    if($letter){
        if($letter -notmatch '^[G-Z]$'){throw ('Ổ đĩa không hợp lệ: '+$Drive)}
        if(@(Get-DeployUsedDriveLetters) -contains $letter -and (Get-DeployDriveMapping $letter) -ine $target.Unc){throw ('Ổ '+$letter+': đang được dùng. Chọn ổ khác.')}
    }
    Assert-DeployConnectUser
    Write-DeployWindowsToolsLog $LogPath 'connect-request' @{Unc=$target.Unc;Server=$target.Server;User=$user;Shortcut=$Shortcut;Drive=$letter}
    # Test before saving: a password that is already saved is only replaced by one that works.
    $code=[int](Test-DeployShareLogon $target.Unc $user $Password)
    Write-DeployWindowsToolsLog $LogPath 'connect-test' @{Unc=$target.Unc;Code=$code}
    if($code -ne 0){throw (Get-DeployShareLogonError $code)}
    $previous=[string](Get-DeployShareCredentialUser $target.Server)
    Save-DeployShareCredential $target.Server $user $Password
    if([string](Get-DeployShareCredentialUser $target.Server) -cne $user){throw 'Windows chưa xác nhận mật khẩu đã lưu.'}
    Write-DeployWindowsToolsLog $LogPath 'credential-saved' @{Server=$target.Server;User=$user;Replaced=$previous}
    $who=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $lines=@('✓ Đăng nhập '+$target.Unc+' bằng '+$user+' thành công; đã lưu mật khẩu cho máy '+$target.Server+' vào Windows Credential Manager của '+$who+'.')
    if($previous -and $previous -cne $user){$lines+=('Thay cho tài khoản đã lưu trước đó: '+$previous+'.')}
    $problems=@()
    if($Shortcut){
        try{$file=New-DeployShareShortcut $target.Unc ($target.Share+' trên '+$target.Server);$lines+=('✓ Đã tạo lối tắt trên Desktop: '+[IO.Path]::GetFileName($file));Write-DeployWindowsToolsLog $LogPath 'shortcut-created' $file}
        catch{$problems+=('Lối tắt: '+$_.Exception.GetBaseException().Message)}
    }
    if($letter){
        try{
            Write-DeployDriveMapping $letter $target.Unc
            if((Get-DeployDriveMapping $letter) -ine $target.Unc){throw 'Windows chưa ghi nhận ổ đĩa.'}
            $lines+=('✓ Đã gán ổ '+$letter+': cho '+$target.Unc+'; ổ hiện sau khi đăng xuất / đăng nhập lại.')
            Write-DeployWindowsToolsLog $LogPath 'drive-mapped' @{Letter=$letter;Unc=$target.Unc}
        }catch{$problems+=('Ổ đĩa: '+$_.Exception.GetBaseException().Message)}
    }
    $lines+=('Người dùng mở lối tắt hoặc '+$target.Unc+' là vào, không phải nhập mật khẩu. Mật khẩu áp dụng cho mọi thư mục chia sẻ trên '+$target.Server+'. Khi đổi mật khẩu tài khoản trên máy chia sẻ, chạy lại bước này trên từng máy.')
    $lines+=@($problems | ForEach-Object {'✗ '+$_})
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($problems.Count){'Attention'}else{'Success'});Log=$LogPath}
}
function Remove-DeployLanConnection([string]$Path,[string]$LogPath) {
    $target=ConvertFrom-DeployShareUnc $Path
    Assert-DeployConnectUser
    $removed=[bool](Remove-DeployShareCredential $target.Server)
    Write-DeployWindowsToolsLog $LogPath 'credential-removed' @{Server=$target.Server;Removed=$removed}
    if(-not $removed){return [pscustomobject]@{Message=('Chưa có mật khẩu nào được lưu cho máy '+$target.Server+'.');Kind='Info';Log=$LogPath}}
    [pscustomobject]@{Message=('✓ Đã xoá mật khẩu đã lưu cho máy '+$target.Server+'. Lần sau mở thư mục chia sẻ trên máy đó sẽ phải nhập lại. Lối tắt và ổ đĩa đã gán vẫn giữ.');Kind='Success';Log=$LogPath}
}
