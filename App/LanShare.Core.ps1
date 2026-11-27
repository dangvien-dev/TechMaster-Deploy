# Share a local folder on the LAN for the TechMaster accounts (scan / share / print): share and NTFS
# permissions per account, a LAN-only firewall rule and, only when asked, a Public network made Private.
# Password-protected sharing stays on; Everyone / Guest access is never added.
. (Join-Path $PSScriptRoot 'LanAccounts.Core.ps1')
$script:DeployShareFirewallGroup='TechMaster LAN'
$script:DeployShareFirewallRules=@(
    [pscustomobject]@{Name='TechMaster-LAN-SMB-TCP';DisplayName='TechMaster - Chia sẻ file trong LAN (TCP 139, 445)';Protocol='TCP';Ports=@('139','445')},
    [pscustomobject]@{Name='TechMaster-LAN-NetBIOS-UDP';DisplayName='TechMaster - Tên máy trong LAN (UDP 137, 138)';Protocol='UDP';Ports=@('137','138')})
$script:DeployShareAccessLabels=@{None='Không';Read='Chỉ đọc';Change='Đọc & ghi'}
function Get-DeployShareFolderCheck([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Chọn thư mục cần chia sẻ.'}
    $Path=$Path.Trim()
    if($Path.StartsWith('\\')){throw 'Chỉ chia sẻ thư mục trên ổ của máy này, không chọn đường dẫn mạng.'}
    $full=[IO.Path]::GetFullPath($Path)
    if($full.Length -gt 3){$full=$full.TrimEnd('\')}
    if($full -notmatch '^[A-Za-z]:\\'){throw 'Chọn thư mục trên ổ đĩa của máy này (dạng D:\TenThuMuc).'}
    if(-not (Test-Path -LiteralPath $full -PathType Container)){throw ('Không tìm thấy thư mục: '+$full)}
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Thư mục là liên kết (junction / symlink); chọn thư mục thật.'}
    if((Get-DeployShareDriveType $full) -ne 'Fixed'){throw 'Chỉ chia sẻ thư mục trên ổ cứng trong máy (không phải USB, ổ mạng, ổ CD).'}
    $system=([string]$env:SystemDrive).TrimEnd('\')+'\'
    $windows=([string]$env:WINDIR).TrimEnd('\')
    $usersRoot=Join-Path $system 'Users'
    $blocked=@($system,$usersRoot,[string]$env:ProgramFiles,[string]${env:ProgramFiles(x86)},[string]$env:ProgramData) | Where-Object {$_} | ForEach-Object {$_.TrimEnd('\')}
    $compare=$full.TrimEnd('\')
    if($compare -ieq $system.TrimEnd('\') -or $compare -ieq $windows -or $compare.StartsWith($windows+'\',[StringComparison]::OrdinalIgnoreCase) -or ($blocked -icontains $compare)){throw ('Không chia sẻ thư mục hệ thống: '+$full)}
    # A whole profile (C:\Users\<name>) exposes AppData, browser data and saved passwords.
    $parent=if($full -match '^[A-Za-z]:\\$'){''}else{[string][IO.Path]::GetDirectoryName($full)}
    if($parent -ieq $usersRoot){throw ('Không chia sẻ cả thư mục người dùng '+$full+'; chọn thư mục con, ví dụ Documents\ChiaSe.')}
    $warning=if($full -match '^[A-Za-z]:\\$'){'Đang chia sẻ cả ổ '+$full.Substring(0,2)+'; nên chia sẻ một thư mục riêng.'}else{''}
    [pscustomobject]@{Path=$full;Warning=$warning;DefaultName=(ConvertTo-DeployShareName $full)}
}
function Get-DeployShareDriveType([string]$Path) {[string]([IO.DriveInfo]::new($Path.Substring(0,1))).DriveType}
function ConvertTo-DeployShareName([string]$Path) {
    $leaf=if($Path -match '^([A-Za-z]):\\$'){'Data_'+$Matches[1].ToUpperInvariant()}else{Split-Path -Leaf $Path}
    # Copiers and old devices handle plain ASCII names best.
    $plain=($leaf -creplace 'đ','d' -creplace 'Đ','D').Normalize([Text.NormalizationForm]::FormD)
    $plain=-join @($plain.ToCharArray() | Where-Object {[Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark})
    $plain=($plain -replace '[\\/\[\]:|<>+=;,?*"]','_' -replace '\s+','_').Trim('_','.',' ')
    if($plain.Length -gt 40){$plain=$plain.Substring(0,40)}
    if(-not $plain){$plain='ChiaSe'}
    return $plain
}
function Test-DeployShareName([string]$Name) {
    if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 80){return $false}
    if($Name -match '[\\/\[\]:|<>+=;,?*"]' -or $Name.EndsWith('$') -or $Name.EndsWith('.') -or $Name -ne $Name.Trim()){return $false}
    return -not ($Name -in 'ADMIN','IPC','PRINT','FAX','NETLOGON','SYSVOL')
}
function ConvertTo-DeploySharePath([string]$Path) {([string]$Path).TrimEnd('\') + $(if(([string]$Path).TrimEnd('\') -match '^[A-Za-z]:$'){'\'}else{''})}
function Get-DeployAdminsAccount {([Security.Principal.SecurityIdentifier]$script:DeployLanAdminsSid).Translate([Security.Principal.NTAccount]).Value}
function Get-DeployShareRights([string]$Access) {if($Access -eq 'Change'){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute}}
function Get-DeployFolderSddl([string]$Path) {
    [IO.DirectoryInfo]::new($Path).GetAccessControl([Security.AccessControl.AccessControlSections]::Access).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
}
# Replaces only the explicit entries of this account on the folder; inherited and other entries stay.
function Set-DeployFolderAccess([string]$Path,[string]$Account,[ValidateSet('None','Read','Change')][string]$Access) {
    $dir=[IO.DirectoryInfo]::new($Path)
    $security=$dir.GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
    $identity=[Security.Principal.NTAccount]::new($Account)
    $security.PurgeAccessRules($identity)
    if($Access -ne 'None'){
        $inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($identity,(Get-DeployShareRights $Access),$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $security.AddAccessRule($rule)
    }
    $dir.SetAccessControl($security)
}
function Get-DeployFolderAccess([string]$Path,[string]$Account) {
    $security=[IO.DirectoryInfo]::new($Path).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
    $sid=[Security.Principal.NTAccount]::new($Account).Translate([Security.Principal.SecurityIdentifier])
    $best='None'
    foreach($rule in $security.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])){
        if($rule.IdentityReference -ne $sid -or $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
        if(([int]$rule.InheritanceFlags -band 3) -ne 3){continue}
        $rights=[int]$rule.FileSystemRights
        if(($rights -band [int][Security.AccessControl.FileSystemRights]::Modify) -eq [int][Security.AccessControl.FileSystemRights]::Modify){$best='Change'}
        elseif($best -eq 'None' -and ($rights -band [int][Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [int][Security.AccessControl.FileSystemRights]::ReadAndExecute){$best='Read'}
    }
    return $best
}
function Get-DeployShareAccessMap([string]$Name,$Accounts,[switch]$Raw) {
    $map=@{}
    foreach($account in @($Accounts)){$map[[string]$account]='None'}
    foreach($entry in @(Get-SmbShareAccess -Name $Name -ErrorAction Stop)){
        if([string]$entry.AccessControlType -ne 'Allow'){continue}
        foreach($account in @($Accounts)){
            if([string]$entry.AccountName -ine [string]$account){continue}
            $right=[string]$entry.AccessRight
            # Raw keeps Full apart so an update can lower it; the UI shows Full as read & write.
            $map[[string]$account]=if($Raw -and $right -in 'Full','Change','Read'){$right}elseif($right -in 'Full','Change'){'Change'}elseif($right -eq 'Read'){'Read'}else{'None'}
        }
    }
    return $map
}
function Get-DeployShareFirewallState {
    foreach($spec in $script:DeployShareFirewallRules){
        $rule=@(Get-NetFirewallRule -Name $spec.Name -ErrorAction SilentlyContinue)[0]
        [pscustomobject]@{Name=$spec.Name;Exists=[bool]$rule;Enabled=[bool]($rule -and [string]$rule.Enabled -eq 'True')}
    }
}
function Enable-DeployShareFirewall([string]$LogPath) {
    foreach($spec in $script:DeployShareFirewallRules){
        $rule=@(Get-NetFirewallRule -Name $spec.Name -ErrorAction SilentlyContinue)[0]
        # Own rules: LAN subnet only, never the Public profile; built-in rules are left untouched.
        if(-not $rule){New-NetFirewallRule -Name $spec.Name -DisplayName $spec.DisplayName -Group $script:DeployShareFirewallGroup -Direction Inbound -Action Allow -Protocol $spec.Protocol -LocalPort $spec.Ports -Profile Private,Domain -RemoteAddress LocalSubnet -ErrorAction Stop | Out-Null;Write-DeployWindowsToolsLog $LogPath 'firewall-rule-created' $spec.Name}
        elseif([string]$rule.Enabled -ne 'True'){Enable-NetFirewallRule -Name $spec.Name -ErrorAction Stop;Write-DeployWindowsToolsLog $LogPath 'firewall-rule-enabled' $spec.Name}
    }
}
function Get-DeployNetworkProfiles {
    @(Get-NetConnectionProfile -ErrorAction Stop | ForEach-Object {[pscustomobject]@{Index=[int]$_.InterfaceIndex;Alias=[string]$_.InterfaceAlias;Name=[string]$_.Name;Category=[string]$_.NetworkCategory}})
}
function Get-DeployShareAddresses($Profiles) {
    $addresses=@()
    foreach($profile in @($Profiles | Where-Object {$_.Category -ne 'Public'})){
        try{$addresses+=@(Get-NetIPAddress -InterfaceIndex $profile.Index -AddressFamily IPv4 -ErrorAction Stop | Where-Object {[string]$_.IPAddress -notmatch '^(169\.254|127)\.'} | ForEach-Object {[string]$_.IPAddress})}catch{}
    }
    @($addresses | Select-Object -Unique)
}
function Get-DeployShareState([string]$Path='') {
    $computer=[string]$env:COMPUTERNAME
    $accounts=foreach($spec in $script:DeployLanRoles){
        $exists=$false;try{$exists=[bool](Find-DeployLanUser $spec.Name)}catch{}
        [pscustomobject]@{Role=$spec.Role;Name=$spec.Name;Account=($computer+'\'+$spec.Name);Exists=$exists}
    }
    $folder=$null;$folderError=''
    if($Path){try{$folder=Get-DeployShareFolderCheck $Path}catch{$folderError=$_.Exception.GetBaseException().Message}}
    $shares=@();$sharesError=''
    try{$shares=@(Get-SmbShare -ErrorAction Stop | Where-Object {-not $_.Special -and -not ([string]$_.Name).EndsWith('$')} | ForEach-Object {[pscustomobject]@{Name=[string]$_.Name;Path=[string]$_.Path}})}catch{$sharesError=$_.Exception.GetBaseException().Message}
    $existing=$null;$current=@{}
    if($folder){
        $existing=@($shares | Where-Object {(ConvertTo-DeploySharePath $_.Path) -ieq $folder.Path})[0]
        if($existing){try{$current=Get-DeployShareAccessMap $existing.Name @($accounts | ForEach-Object {$_.Account})}catch{}}
    }
    $firewall=@();try{$firewall=@(Get-DeployShareFirewallState)}catch{}
    $profiles=@();$profileError=''
    try{$profiles=@(Get-DeployNetworkProfiles)}catch{$profileError=$_.Exception.GetBaseException().Message}
    $server='';try{$server=[string](Get-Service -Name LanmanServer -ErrorAction Stop).Status}catch{}
    [pscustomobject]@{Computer=$computer;Accounts=@($accounts);Folder=$folder;FolderError=$folderError;Shares=$shares;SharesError=$sharesError;Existing=$existing;CurrentAccess=$current;Firewall=$firewall;FirewallReady=[bool](@($firewall).Count -and -not @($firewall | Where-Object {-not $_.Enabled}).Count);Profiles=$profiles;ProfileError=$profileError;Server=$server}
}
function Set-DeployFolderShare([string]$Path,[string]$ShareName,$Grants,[bool]$Firewall,[int[]]$MakePrivate,[string]$LogPath) {
    Assert-DeployLanAdmin
    $folder=Get-DeployShareFolderCheck $Path
    $ShareName=([string]$ShareName).Trim()
    if(-not (Test-DeployShareName $ShareName)){throw 'Tên chia sẻ không hợp lệ: 1–80 ký tự, không chứa \ / [ ] : | < > + = ; , ? * " và không kết thúc bằng $ hoặc dấu chấm.'}
    $computer=[string]$env:COMPUTERNAME
    # PowerShell names are case-insensitive: read the parameter before reusing the name for the checked list.
    $requestedGrants=@($Grants | Where-Object {$_})
    $grants=@()
    foreach($grant in $requestedGrants){
        $spec=Get-DeployLanRole $grant.Role
        if($grant.Access -notin 'None','Read','Change'){throw ('Quyền không hợp lệ cho '+$spec.Name)}
        $exists=[bool](Find-DeployLanUser $spec.Name)
        if(-not $exists){
            if($grant.Access -ne 'None'){throw ('Chưa có tài khoản '+$spec.Name+'. Tạo ở Tài khoản chia sẻ LAN trước.')}
            continue
        }
        $grants+=[pscustomobject]@{Role=$spec.Role;Name=$spec.Name;Account=($computer+'\'+$spec.Name);Access=[string]$grant.Access}
    }
    if(-not @($grants | Where-Object {$_.Access -ne 'None'}).Count){throw 'Chọn Chỉ đọc hoặc Đọc & ghi cho ít nhất một tài khoản.'}
    $existing=@(Get-SmbShare -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $ShareName})[0]
    if($existing -and (ConvertTo-DeploySharePath $existing.Path) -ine $folder.Path){throw ("Tên chia sẻ '$ShareName' đang dùng cho thư mục khác ("+$existing.Path+'). Chọn tên khác.')}
    Write-DeployWindowsToolsLog $LogPath 'share-request' @{Path=$folder.Path;Share=$ShareName;Grants=$grants;Firewall=$Firewall;MakePrivate=$MakePrivate;Existing=[bool]$existing;NtfsBefore=(Get-DeployFolderSddl $folder.Path)}
    foreach($grant in $grants){Set-DeployFolderAccess $folder.Path $grant.Account $grant.Access}
    Write-DeployWindowsToolsLog $LogPath 'ntfs-updated' @{Path=$folder.Path;NtfsAfter=(Get-DeployFolderSddl $folder.Path)}
    if(-not $existing){
        $splat=@{Name=$ShareName;Path=$folder.Path;FullAccess=@(Get-DeployAdminsAccount);FolderEnumerationMode='AccessBased';Description='TechMaster LAN';ErrorAction='Stop'}
        $change=@($grants | Where-Object {$_.Access -eq 'Change'} | ForEach-Object {$_.Account})
        $read=@($grants | Where-Object {$_.Access -eq 'Read'} | ForEach-Object {$_.Account})
        if($change.Count){$splat.ChangeAccess=$change}
        if($read.Count){$splat.ReadAccess=$read}
        New-SmbShare @splat | Out-Null
        Write-DeployWindowsToolsLog $LogPath 'share-created' @{Share=$ShareName;Change=$change;Read=$read}
    }else{
        $current=Get-DeployShareAccessMap $ShareName @($grants | ForEach-Object {$_.Account}) -Raw
        foreach($grant in $grants){
            if($current[$grant.Account] -eq $grant.Access){continue}
            if($current[$grant.Account] -ne 'None'){Revoke-SmbShareAccess -Name $ShareName -AccountName $grant.Account -Force -ErrorAction Stop | Out-Null}
            if($grant.Access -ne 'None'){Grant-SmbShareAccess -Name $ShareName -AccountName $grant.Account -AccessRight $grant.Access -Force -ErrorAction Stop | Out-Null}
        }
        Write-DeployWindowsToolsLog $LogPath 'share-updated' @{Share=$ShareName;Before=$current}
    }
    $lines=@();$problems=@()
    $service=Get-Service -Name LanmanServer -ErrorAction Stop
    if([string]$service.Status -ne 'Running'){
        if([string]$service.StartType -eq 'Disabled'){Set-Service -Name LanmanServer -StartupType Automatic -ErrorAction Stop}
        Start-Service -Name LanmanServer -ErrorAction Stop
        $lines+='✓ Đã bật dịch vụ Server (LanmanServer) để chia sẻ file.'
    }
    if($Firewall){
        try{Enable-DeployShareFirewall $LogPath;$lines+='✓ Đã mở tường lửa cho chia sẻ file trong LAN: TCP 139, 445 và UDP 137, 138; chỉ mạng Private / Domain, chỉ máy cùng dải mạng.'}
        catch{$problems+=('Tường lửa: '+$_.Exception.GetBaseException().Message)}
    }
    foreach($index in @($MakePrivate)){
        try{Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory Private -ErrorAction Stop;Write-DeployWindowsToolsLog $LogPath 'network-private' $index}
        catch{$problems+=('Chuyển mạng sang Private: '+$_.Exception.GetBaseException().Message)}
    }
    # Read back share, NTFS, firewall and network before reporting.
    $share=@(Get-SmbShare -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $ShareName})[0]
    if(-not $share -or (ConvertTo-DeploySharePath $share.Path) -ine $folder.Path){$problems+='Windows chưa ghi nhận thư mục chia sẻ.'}
    else{
        $after=Get-DeployShareAccessMap $ShareName @($grants | ForEach-Object {$_.Account})
        foreach($grant in $grants){
            if($after[$grant.Account] -ne $grant.Access){$problems+=('Quyền chia sẻ của '+$grant.Name+' đang là '+$script:DeployShareAccessLabels[$after[$grant.Account]]+'.')}
            $ntfs=Get-DeployFolderAccess $folder.Path $grant.Account
            if($ntfs -ne $grant.Access){$problems+=('Quyền NTFS của '+$grant.Name+' đang là '+$script:DeployShareAccessLabels[$ntfs]+'.')}
        }
    }
    $state=Get-DeployShareState
    if($Firewall -and -not $state.FirewallReady){$problems+='Windows chưa xác nhận luật tường lửa.'}
    $public=@($state.Profiles | Where-Object {$_.Category -eq 'Public'})
    foreach($profile in $public){$lines+=('! Mạng "'+$profile.Name+'" ('+$profile.Alias+') đang Public: máy khác chưa vào được. Nếu đây là mạng nội bộ, tích chuyển sang Private.')}
    Write-DeployWindowsToolsLog $LogPath 'share-verified' @{Share=$ShareName;Problems=$problems;Firewall=$state.Firewall;Profiles=$state.Profiles}
    $addresses=@(Get-DeployShareAddresses $state.Profiles)
    $rights=@($grants | Where-Object {$_.Access -ne 'None'} | ForEach-Object {$_.Name+': '+$script:DeployShareAccessLabels[$_.Access]})
    $head='✓ '+$(if($existing){'Đã cập nhật'}else{'Đã chia sẻ'})+' '+$folder.Path+' thành \\'+$computer+'\'+$ShareName
    if($addresses.Count){$head+=' (hoặc '+(@($addresses | ForEach-Object {'\\'+$_+'\'+$ShareName}) -join ', ')+')'}
    $lines=@($head+'.','Quyền: '+($rights -join '; ')+'. Mật khẩu vẫn bắt buộc; không mở cho Everyone / Guest.')+$lines
    if($folder.Warning){$lines+=('! '+$folder.Warning)}
    $lines+='Máy người dùng: dùng Kết nối thư mục chia sẻ để lưu mật khẩu một lần và tạo lối tắt.'
    if($problems.Count){$lines+=@($problems | ForEach-Object {'✗ '+$_})}
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($problems.Count){'Attention'}elseif($public.Count){'Attention'}else{'Success'});Log=$LogPath;Unc=('\\'+$computer+'\'+$ShareName)}
}
