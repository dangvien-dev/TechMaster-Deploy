# Credential Manager, connection test, desktop session and drive mapping are mocked; the shortcut is created for real in a temporary folder.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LanConnect.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m,$pattern=''){$failed=$false;$text='';try{& $action | Out-Null}catch{$failed=$true;$text=$_.Exception.GetBaseException().Message};Assert ($failed -and (-not $pattern -or $text -match $pattern)) "$m ($text)"}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-connect-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
try{
    $log=Join-Path $temp 'connect.jsonl'
    $secret='Share@2026'
    $password=ConvertTo-SecureString $secret -AsPlainText -Force
    $target=ConvertFrom-DeployShareUnc '\\KY-THUAT\KeToan'
    Assert ($target.Server -ceq 'KY-THUAT' -and $target.Share -ceq 'KeToan' -and $target.Unc -ceq '\\KY-THUAT\KeToan') 'A computer-name path is parsed'
    $target=ConvertFrom-DeployShareUnc ' //192.168.1.10/Scan/2026/ '
    Assert ($target.Server -ceq '192.168.1.10' -and $target.Share -ceq 'Scan' -and $target.Unc -ceq '\\192.168.1.10\Scan\2026') 'An IP path with forward slashes and a subfolder is normalised'
    Throws {ConvertFrom-DeployShareUnc 'KY-THUAT\KeToan'} 'A path without \\ is refused' 'TÊN-MÁY'
    Throws {ConvertFrom-DeployShareUnc '\\KY-THUAT'} 'A path without a share name is refused' 'TÊN-MÁY'
    Assert ((Get-DeployShareLogonError 1326) -match 'Sai tài khoản hoặc mật khẩu' -and (Get-DeployShareLogonError 53) -match 'tường lửa' -and (Get-DeployShareLogonError 5) -match 'quyền' -and (Get-DeployShareLogonError 1219) -match 'tài khoản khác' -and (Get-DeployShareLogonError 1234) -match 'mã 1234') 'Connection errors are explained in Vietnamese with their code'

    $script:calls=New-Object Collections.ArrayList;$script:creds=@{'KY-THUAT'='olduser'};$script:logonCode=0;$script:desktopSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:drives=@{};$script:usedLetters=@('C','D');$script:credentialDrift=$false
    function Test-DeployShareLogon([string]$Unc,[string]$User,[Security.SecureString]$Password){[void]$script:calls.Add('Test:'+$Unc+':'+$User);Assert ($Password -is [Security.SecureString] -and $Password.Length -gt 0) 'The connection test receives the password only as SecureString';$script:logonCode}
    function Save-DeployShareCredential([string]$Server,[string]$User,[Security.SecureString]$Password){[void]$script:calls.Add('Save:'+$Server+':'+$User);$script:creds[$Server]=$User}
    function Get-DeployShareCredentialUser([string]$Server){if($script:credentialDrift){'someone-else'}elseif($script:creds.ContainsKey($Server)){$script:creds[$Server]}else{$null}}
    function Remove-DeployShareCredential([string]$Server){[void]$script:calls.Add('Remove:'+$Server);if($script:creds.ContainsKey($Server)){$script:creds.Remove($Server);$true}else{$false}}
    function Get-DeployDesktopUserSid {$script:desktopSid}
    function Get-DeployDesktopPath {$temp}
    function Get-DeployUsedDriveLetters {@($script:usedLetters)+@($script:drives.Keys)}
    function Get-DeployDriveMapping([string]$Letter){if($script:drives.ContainsKey($Letter)){$script:drives[$Letter]}else{''}}
    function Write-DeployDriveMapping([string]$Letter,[string]$Unc){[void]$script:calls.Add('Drive:'+$Letter);$script:drives[$Letter]=$Unc}

    $r=Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $true 'Z:' $log
    $test=$script:calls.IndexOf('Test:\\KY-THUAT\KeToan:share');$save=$script:calls.IndexOf('Save:KY-THUAT:share')
    Assert ($r.Kind -eq 'Success' -and $test -ge 0 -and $save -gt $test -and $script:creds['KY-THUAT'] -ceq 'share') 'The account is tested first and only then saved for the server'
    Assert ($r.Message -match 'Credential Manager' -and $r.Message -match 'olduser' -and $r.Message -match 'không phải nhập mật khẩu') 'Result explains where the password is kept and which saved account it replaced'
    $shortcut=Join-Path $temp 'KeToan trên KY-THUAT.lnk'
    Assert ((Test-Path -LiteralPath $shortcut) -and $r.Message -match 'lối tắt') 'A real desktop shortcut is created'
    $shell=New-Object -ComObject WScript.Shell
    try{Assert ($shell.CreateShortcut($shortcut).TargetPath -ceq '\\KY-THUAT\KeToan') 'The shortcut opens the share'}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    Assert ($script:drives['Z'] -ceq '\\KY-THUAT\KeToan' -and $r.Message -match 'ổ Z:') 'The drive letter is stored for reconnection at sign-in'
    Assert (-not ([IO.File]::ReadAllText($log).Contains($secret))) 'The password never reaches the log'

    $script:logonCode=1326;$before=$script:calls.Count;$script:creds['KY-THUAT']='share'
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $true '' $log} 'A wrong password is reported' 'Sai tài khoản hoặc mật khẩu'
    Assert (@($script:calls | Select-Object -Skip $before | Where-Object {$_ -like 'Save:*'}).Count -eq 0 -and $script:creds['KY-THUAT'] -ceq 'share') 'A failed test never replaces the password already saved'
    $script:logonCode=0

    $script:desktopSid='S-1-5-21-1-2-3-4444';$before=$script:calls.Count
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $true '' $log} 'Saving for another Windows account than the one using the computer is refused' 'không có tác dụng'
    Assert ($script:calls.Count -eq $before) 'Nothing is tested or saved for the wrong account'
    $script:desktopSid=''
    $r=Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $false '' $log
    Assert ($r.Kind -eq 'Success') 'When the desktop user cannot be read, the app account is used'

    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $false 'D:' $log} 'A drive letter of a local disk is refused' 'Ổ đĩa không hợp lệ|đang được dùng'
    $script:drives['Y']='\\OTHER\Data'
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $false 'Y' $log} 'A drive letter mapped to another share is refused' 'đang được dùng'
    $r=Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $false 'Z' $log
    Assert ($r.Kind -eq 'Success') 'The same drive letter for the same share can be applied again'
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' '' $password $false '' $log} 'An empty account is refused' 'tài khoản'
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' (New-Object Security.SecureString) $false '' $log} 'An empty password is refused' 'mật khẩu'
    $script:credentialDrift=$true
    Throws {Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $false '' $log} 'A password Windows did not keep is reported' 'chưa xác nhận'
    $script:credentialDrift=$false
    function Get-DeployDesktopPath {Join-Path $temp 'missing\nested'}
    $r=Connect-DeployLanShare '\\KY-THUAT\KeToan' 'share' $password $true '' $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match '✗ Lối tắt') 'A shortcut that cannot be created is reported without undoing the saved password'

    $r=Remove-DeployLanConnection '\\KY-THUAT\KeToan' $log
    Assert ($r.Kind -eq 'Success' -and -not $script:creds.ContainsKey('KY-THUAT')) 'The saved password for a server can be removed'
    $r=Remove-DeployLanConnection '\\KY-THUAT\KeToan' $log
    Assert ($r.Kind -eq 'Info' -and $r.Message -match 'Chưa có mật khẩu') 'Removing when nothing is saved is reported plainly'
    Assert (-not ([IO.File]::ReadAllText($log).Contains($secret))) 'No step writes the password to the log'
    Write-Host "PASS: $checks LAN connection assertions; UNC parsing, error codes, test-before-save, desktop account guard, real shortcut, drive letter and removal."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
