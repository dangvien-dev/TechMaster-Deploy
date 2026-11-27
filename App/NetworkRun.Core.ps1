# Run TechMaster Deploy on another computer of the LAN without a USB stick: the program folder is shared
# read-only as the hidden share TechMaster$ for one account; the other computer opens
# \\MÁY\TechMaster$\App\Chay-Tu-Mang.bat, which copies, checks and opens a local copy (Network.Sync.ps1).
# Never Everyone / Guest, never write access; firewall and network profile reuse the LAN share rules.
. (Join-Path $PSScriptRoot 'LanShare.Core.ps1')
. (Join-Path $PSScriptRoot 'Network.Sync.ps1')
$script:DeployNetworkShareName='TechMaster$'
$script:DeployNetworkShareMarker='TechMaster Deploy - chạy qua mạng (chỉ đọc)'
$script:DeployNetworkLauncher='App\Chay-Tu-Mang.bat'
$script:DeployWebCommand='irm https://dangvien-dev.github.io/tm.txt | iex'
$script:DeployNetworkRequired=@('version.txt','update-source.json','App\TechMaster-Deploy.ps1','App\Network.Launch.ps1','App\Network.Sync.ps1','App\Chay-Tu-Mang.bat')

function Get-DeployNetworkRoot([string]$Root) {
    $path=([string]$Root).Trim()
    if(-not $path){throw 'Chưa xác định được thư mục TechMaster.'}
    $path=[IO.Path]::GetFullPath($path).TrimEnd('\')
    if($path -notmatch '^[A-Za-z]:\\.+'){throw 'Chỉ chia sẻ được thư mục TechMaster nằm trên ổ đĩa của máy này, không phải cả ổ hay thư mục mạng.'}
    if((Get-DeployShareDriveType $path) -eq 'Network'){throw 'TechMaster đang chạy từ ổ mạng; chép app vào ổ của máy này rồi chia sẻ.'}
    foreach($name in $script:DeployNetworkRequired){
        if(-not (Test-Path -LiteralPath (Join-Path $path $name) -PathType Leaf)){throw ('Thư mục TechMaster thiếu '+$name+'. Cập nhật hoặc giải nén lại app rồi chia sẻ.')}
    }
    return $path
}
# Accounts the other computer may sign in with: the Windows account using the app and the LAN account share.
function Get-DeployNetworkAccounts {
    $current=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name
    $list=@([pscustomobject]@{Account=$current;Label=($current+' (tài khoản đang dùng)');Lan=$false})
    $spec=Get-DeployLanRole 'Share'
    $exists=$false;try{$exists=[bool](Find-DeployLanUser $spec.Name)}catch{}
    if($exists){$list+=[pscustomobject]@{Account=([string]$env:COMPUTERNAME+'\'+$spec.Name);Label=([string]$env:COMPUTERNAME+'\'+$spec.Name+' (tài khoản LAN chỉ dùng qua mạng)');Lan=$true}}
    return $list
}
function Get-DeployNetworkShare {
    $share=@(Get-SmbShare -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $script:DeployNetworkShareName})[0]
    if(-not $share){return $null}
    $access=@(Get-SmbShareAccess -Name $script:DeployNetworkShareName -ErrorAction Stop | Where-Object {[string]$_.AccessControlType -eq 'Allow'} | ForEach-Object {[pscustomobject]@{Account=[string]$_.AccountName;Right=[string]$_.AccessRight}})
    [pscustomobject]@{Name=[string]$share.Name;Path=(ConvertTo-DeploySharePath $share.Path);Ours=([string]$share.Description -ceq $script:DeployNetworkShareMarker);Access=$access}
}
function Get-DeployNetworkClientPaths([string]$Computer,$Addresses) {
    $tail='\'+$script:DeployNetworkShareName+'\'+$script:DeployNetworkLauncher
    @(('\\'+$Computer+$tail))+@(@($Addresses) | Where-Object {$_} | ForEach-Object {'\\'+$_+$tail})
}
function Test-DeployNetworkNtfs([string]$Path) {try{([IO.DriveInfo]::new($Path.Substring(0,1))).DriveFormat -eq 'NTFS'}catch{$false}}
# The LAN account gets an explicit read entry on an NTFS program folder; removed again with the share.
function Clear-DeployNetworkFolderAccess($Share,[string]$LogPath) {
    if(-not $Share -or -not (Test-Path -LiteralPath $Share.Path) -or -not (Test-DeployNetworkNtfs $Share.Path)){return}
    $lan=@($script:DeployLanRoles | ForEach-Object {([string]$env:COMPUTERNAME+'\'+$_.Name)})
    foreach($entry in @($Share.Access)){
        if($lan -inotcontains $entry.Account){continue}
        try{if((Get-DeployFolderAccess $Share.Path $entry.Account) -eq 'Read'){Set-DeployFolderAccess $Share.Path $entry.Account 'None';Write-DeployWindowsToolsLog $LogPath 'network-run-ntfs-removed' $entry.Account}}catch{}
    }
}
function Get-DeployNetworkRunState([string]$Root) {
    $computer=[string]$env:COMPUTERNAME
    $path='';$rootError='';$problems=@()
    try{$path=Get-DeployNetworkRoot $Root;$problems=@(Get-DeployNetworkSourceProblems $path)}catch{$rootError=$_.Exception.GetBaseException().Message}
    $share=$null;$shareError=''
    try{$share=Get-DeployNetworkShare}catch{$shareError=$_.Exception.GetBaseException().Message}
    $accounts=@();try{$accounts=@(Get-DeployNetworkAccounts)}catch{}
    $firewall=@();try{$firewall=@(Get-DeployShareFirewallState)}catch{}
    $profiles=@();$profileError=''
    try{$profiles=@(Get-DeployNetworkProfiles)}catch{$profileError=$_.Exception.GetBaseException().Message}
    $addresses=@();try{$addresses=@(Get-DeployShareAddresses $profiles)}catch{}
    $server='';try{$server=[string](Get-Service -Name LanmanServer -ErrorAction Stop).Status}catch{}
    $active=[bool]($share -and $path -and $share.Path -ieq $path)
    $account=if($active){@($share.Access | Where-Object {$_.Right -eq 'Read'} | ForEach-Object {$_.Account})[0]}else{''}
    [pscustomobject]@{Computer=$computer;Root=$(if($path){$path}else{[string]$Root});RootError=$rootError;SourceProblems=$problems;Share=$share;ShareError=$shareError;Active=$active;Account=[string]$account;
        Accounts=$accounts;Firewall=$firewall;FirewallReady=[bool](@($firewall).Count -and -not @($firewall | Where-Object {-not $_.Enabled}).Count);Profiles=$profiles;ProfileError=$profileError;
        Server=$server;Addresses=$addresses;ClientPaths=@(Get-DeployNetworkClientPaths $computer $addresses)}
}
function Set-DeployNetworkRunShare([string]$Root,[string]$Account,[bool]$Firewall,[int[]]$MakePrivate,[string]$LogPath) {
    Assert-DeployLanAdmin
    $path=Get-DeployNetworkRoot $Root
    $choice=@(Get-DeployNetworkAccounts | Where-Object {$_.Account -ieq ([string]$Account).Trim()})[0]
    if(-not $choice){throw 'Chọn tài khoản máy kia dùng để mở thư mục TechMaster.'}
    $problems=@(Get-DeployNetworkSourceProblems $path)
    if($problems.Count){throw ('Thư mục TechMaster có tệp khác danh sách update-source.json ('+(@($problems | Select-Object -First 3) -join ', ')+'); máy kia sẽ dừng khi chép. Cập nhật lại app trước khi chia sẻ.')}
    $existing=Get-DeployNetworkShare
    if($existing -and -not $existing.Ours){throw ('Tên chia sẻ TechMaster$ đang dùng cho '+$existing.Path+' và không do app tạo. Gỡ chia sẻ đó trước.')}
    Write-DeployWindowsToolsLog $LogPath 'network-run-request' @{Path=$path;Account=$choice.Account;Firewall=$Firewall;MakePrivate=$MakePrivate;Existing=$existing}
    $same=[bool]($existing -and $existing.Path -ieq $path -and @($existing.Access).Count -eq 1 -and $existing.Access[0].Account -ieq $choice.Account -and $existing.Access[0].Right -eq 'Read')
    if($existing -and -not $same){
        Remove-SmbShare -Name $script:DeployNetworkShareName -Force -ErrorAction Stop
        Clear-DeployNetworkFolderAccess $existing $LogPath
        Write-DeployWindowsToolsLog $LogPath 'network-run-share-replaced' $existing
    }
    # Only the LAN account needs an NTFS entry; the account using the app already reads its own folder.
    if($choice.Lan -and (Test-DeployNetworkNtfs $path) -and (Get-DeployFolderAccess $path $choice.Account) -ne 'Read'){
        Set-DeployFolderAccess $path $choice.Account 'Read'
        Write-DeployWindowsToolsLog $LogPath 'network-run-ntfs-read' $choice.Account
    }
    if(-not $same){
        New-SmbShare -Name $script:DeployNetworkShareName -Path $path -ReadAccess @($choice.Account) -FolderEnumerationMode Unrestricted -Description $script:DeployNetworkShareMarker -ErrorAction Stop | Out-Null
        Write-DeployWindowsToolsLog $LogPath 'network-run-share-created' @{Path=$path;Account=$choice.Account}
    }
    $lines=@();$notes=@();$issues=@()
    $service=Get-Service -Name LanmanServer -ErrorAction Stop
    if([string]$service.Status -ne 'Running'){
        if([string]$service.StartType -eq 'Disabled'){Set-Service -Name LanmanServer -StartupType Automatic -ErrorAction Stop}
        Start-Service -Name LanmanServer -ErrorAction Stop
        $notes+='✓ Đã bật dịch vụ Server (LanmanServer) để chia sẻ file.'
    }
    if($Firewall){
        try{Enable-DeployShareFirewall $LogPath;$notes+='✓ Tường lửa: đã mở chia sẻ file trong LAN (chỉ mạng Private / Domain, chỉ máy cùng dải mạng).'}
        catch{$issues+=('Tường lửa: '+$_.Exception.GetBaseException().Message)}
    }
    foreach($index in @($MakePrivate)){
        try{Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory Private -ErrorAction Stop;Write-DeployWindowsToolsLog $LogPath 'network-private' $index}
        catch{$issues+=('Chuyển mạng sang Private: '+$_.Exception.GetBaseException().Message)}
    }
    # Read back before reporting.
    $state=Get-DeployNetworkRunState $path
    if(-not $state.Active){$issues+='Windows chưa ghi nhận chia sẻ TechMaster$.'}
    elseif(@($state.Share.Access).Count -ne 1 -or $state.Share.Access[0].Account -ine $choice.Account -or $state.Share.Access[0].Right -ne 'Read'){$issues+=('Quyền chia sẻ đang là: '+(@($state.Share.Access | ForEach-Object {$_.Account+' '+$_.Right}) -join ', ')+'.')}
    if($Firewall -and -not $state.FirewallReady){$issues+='Windows chưa xác nhận luật tường lửa.'}
    $public=@($state.Profiles | Where-Object {$_.Category -eq 'Public'})
    foreach($profile in $public){$notes+=('! Mạng "'+$profile.Name+'" ('+$profile.Alias+') đang Public: máy khác chưa vào được. Nếu là mạng nội bộ, tích chuyển sang Private.')}
    Write-DeployWindowsToolsLog $LogPath 'network-run-verified' @{Issues=$issues;Share=$state.Share;Firewall=$state.Firewall}
    $paths=@($state.ClientPaths)
    $lines+=('✓ Đã chia sẻ '+$path+' (chỉ đọc) cho '+$choice.Account+'.')
    $lines+=('Trên máy kia: mở '+$paths[0]+$(if($paths.Count -gt 1){' (hoặc '+((@($paths | Select-Object -Skip 1)) -join ', ')+')'}else{''})+', đăng nhập '+$choice.Account+' và mật khẩu của tài khoản đó.')
    $lines+='App được chép vào C:\TechMaster-Deploy của máy kia, kiểm tra từng tệp rồi mở với quyền quản trị. Bấm Ngừng chia sẻ khi xong việc.'
    $lines+=$notes
    if($issues.Count){$lines+=@($issues | ForEach-Object {'✗ '+$_})}
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($issues.Count -or $public.Count){'Attention'}else{'Success'});Log=$LogPath;ClientPaths=$paths}
}
function Remove-DeployNetworkRunShare([string]$LogPath) {
    Assert-DeployLanAdmin
    $existing=Get-DeployNetworkShare
    if(-not $existing){return [pscustomobject]@{Message='TechMaster chưa được chia sẻ qua mạng.';Kind='Info';Log=$LogPath}}
    if(-not $existing.Ours){throw ('Chia sẻ TechMaster$ ('+$existing.Path+') không do app tạo; gỡ trong Computer Management → Shared Folders.')}
    Remove-SmbShare -Name $script:DeployNetworkShareName -Force -ErrorAction Stop
    Clear-DeployNetworkFolderAccess $existing $LogPath
    Write-DeployWindowsToolsLog $LogPath 'network-run-share-removed' $existing
    if(Get-DeployNetworkShare){throw 'Windows chưa gỡ chia sẻ TechMaster$. Thử lại.'}
    [pscustomobject]@{Message='✓ Đã ngừng chia sẻ TechMaster. Máy khác không mở được \\'+[string]$env:COMPUTERNAME+'\TechMaster$ nữa; bản đã chép trên máy đó vẫn dùng được.';Kind='Success';Log=$LogPath}
}
