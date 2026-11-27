# Real NTFS changes on a temporary folder; SMB shares, firewall, network profiles, services and accounts are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LanShare.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m,$pattern=''){$failed=$false;$text='';try{& $action | Out-Null}catch{$failed=$true;$text=$_.Exception.GetBaseException().Message};Assert ($failed -and (-not $pattern -or $text -match $pattern)) "$m ($text)"}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-share-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
try{
    $log=Join-Path $temp 'share.jsonl'
    $folderPath=Join-Path $temp 'Kế Toán Đặc biệt';New-Item -ItemType Directory $folderPath | Out-Null
    $file=Join-Path $temp 'file.txt';Set-Content -LiteralPath $file 'x'
    # Real NTFS: only the explicit entries of the given account change; inherited access stays.
    $me=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $ntfsFolder=Join-Path $temp 'NtfsReal';New-Item -ItemType Directory $ntfsFolder | Out-Null
    Set-DeployFolderAccess $ntfsFolder $me 'Read'
    Assert ((Get-DeployFolderAccess $ntfsFolder $me) -ceq 'Read') 'Read grants ReadAndExecute inherited by subfolders and files'
    Set-DeployFolderAccess $ntfsFolder $me 'Change'
    Assert ((Get-DeployFolderAccess $ntfsFolder $me) -ceq 'Change') 'Change grants Modify'
    Set-DeployFolderAccess $ntfsFolder $me 'Read'
    Assert ((Get-DeployFolderAccess $ntfsFolder $me) -ceq 'Read') 'Lowering access replaces the earlier entry instead of adding to it'
    Set-DeployFolderAccess $ntfsFolder $me 'None'
    Assert ((Get-DeployFolderAccess $ntfsFolder $me) -ceq 'None' -and (Test-Path -LiteralPath $ntfsFolder) -and (Get-DeployFolderSddl $ntfsFolder) -match '^D:') 'None removes only the explicit entry; inherited access keeps the folder usable'

    $check=Get-DeployShareFolderCheck $folderPath
    Assert ($check.Path -ceq $folderPath -and $check.DefaultName -ceq 'Ke_Toan_Dac_biet' -and -not $check.Warning) 'A normal folder is accepted with a plain ASCII share name'
    Assert ((ConvertTo-DeployShareName 'D:\') -ceq 'Data_D' -and (ConvertTo-DeployShareName 'D:\Kế toán; 2026') -ceq 'Ke_toan__2026') 'Drive roots and special characters get usable share names'
    Throws {Get-DeployShareFolderCheck $env:WINDIR} 'The Windows folder is refused' 'hệ thống'
    Throws {Get-DeployShareFolderCheck (Join-Path $env:WINDIR 'System32')} 'Anything inside Windows is refused' 'hệ thống'
    Throws {Get-DeployShareFolderCheck ($env:SystemDrive+'\')} 'The system drive root is refused' 'hệ thống'
    Throws {Get-DeployShareFolderCheck $env:ProgramData} 'ProgramData is refused' 'hệ thống'
    Throws {Get-DeployShareFolderCheck $env:USERPROFILE} 'A whole user profile is refused' 'người dùng'
    Throws {Get-DeployShareFolderCheck '\\server\share'} 'Network paths are refused' 'mạng'
    Throws {Get-DeployShareFolderCheck (Join-Path $temp 'missing')} 'Missing folders are refused' 'Không tìm thấy'
    Throws {Get-DeployShareFolderCheck $file} 'Files are refused' 'Không tìm thấy'
    function Get-DeployShareDriveType([string]$Path){$script:driveType}
    $script:driveType='Removable'
    Throws {Get-DeployShareFolderCheck $folderPath} 'USB drives are refused' 'USB'
    $script:driveType='Fixed'
    if((Test-Path 'D:\') -and $env:SystemDrive -ne 'D:'){Assert ((Get-DeployShareFolderCheck 'D:\').Warning -match 'cả ổ D:') 'Sharing a whole data drive is allowed with a warning'}
    Assert ((Test-DeployShareName 'KeToan') -and (Test-DeployShareName 'Ke Toan 2026') -and -not (Test-DeployShareName 'a/b') -and -not (Test-DeployShareName 'An$') -and -not (Test-DeployShareName 'IPC') -and -not (Test-DeployShareName '') -and -not (Test-DeployShareName (' '*3))) 'Share names follow Windows rules and exclude hidden / reserved names'

    $pc=$env:COMPUTERNAME
    $script:admin=$true;$script:calls=New-Object Collections.ArrayList
    $script:localUsers=@([pscustomobject]@{Name='scan'},[pscustomobject]@{Name='share'})
    $script:shares=@{};$script:shareAccess=@{};$script:rules=@{};$script:ntfs=@{};$script:ntfsBroken=$false
    $script:netProfiles=@([pscustomobject]@{InterfaceIndex=12;InterfaceAlias='Ethernet';Name='CongTy';NetworkCategory='Private'})
    $script:service=[pscustomobject]@{Status='Stopped';StartType='Disabled'}
    function Assert-DeployLanAdmin {if(-not $script:admin){throw 'admin required'}}
    function Get-LocalUser {param($ErrorAction)$script:localUsers}
    function Get-SmbShare {param($ErrorAction)@($script:shares.Values)}
    function New-SmbShare {param($Name,$Path,$FullAccess,$ChangeAccess,$ReadAccess,$FolderEnumerationMode,$Description,$ErrorAction)
        $script:newShare=[pscustomobject]@{Name=$Name;Path=$Path;Full=@($FullAccess | Where-Object {$_});Change=@($ChangeAccess | Where-Object {$_});Read=@($ReadAccess | Where-Object {$_});Mode=[string]$FolderEnumerationMode}
        $script:shares[$Name]=[pscustomobject]@{Name=$Name;Path=$Path;Special=$false}
        $script:shareAccess[$Name]=@(@($FullAccess | Where-Object {$_} | ForEach-Object {[pscustomobject]@{AccountName=$_;AccessControlType='Allow';AccessRight='Full'}})+@($ChangeAccess | Where-Object {$_} | ForEach-Object {[pscustomobject]@{AccountName=$_;AccessControlType='Allow';AccessRight='Change'}})+@($ReadAccess | Where-Object {$_} | ForEach-Object {[pscustomobject]@{AccountName=$_;AccessControlType='Allow';AccessRight='Read'}}))
        [void]$script:calls.Add('New:'+$Name)
    }
    function Get-SmbShareAccess {param($Name,$ErrorAction)@($script:shareAccess[$Name] | Where-Object {$_})}
    function Grant-SmbShareAccess {param($Name,$AccountName,$AccessRight,[switch]$Force,$ErrorAction)[void]$script:calls.Add('Grant:'+$AccountName+':'+$AccessRight);$script:shareAccess[$Name]=@($script:shareAccess[$Name] | Where-Object {$_})+[pscustomobject]@{AccountName=$AccountName;AccessControlType='Allow';AccessRight=$AccessRight}}
    function Revoke-SmbShareAccess {param($Name,$AccountName,[switch]$Force,$ErrorAction)[void]$script:calls.Add('Revoke:'+$AccountName);$script:shareAccess[$Name]=@($script:shareAccess[$Name] | Where-Object {$_ -and $_.AccountName -ine $AccountName})}
    function Get-Service {param($Name,$ErrorAction)$script:service}
    function Set-Service {param($Name,$StartupType,$ErrorAction)$script:service.StartType=$StartupType}
    function Start-Service {param($Name,$ErrorAction)[void]$script:calls.Add('Start:'+$Name);$script:service.Status='Running'}
    function Get-NetFirewallRule {param($Name,$ErrorAction)if($script:rules.ContainsKey($Name)){$script:rules[$Name]}}
    function New-NetFirewallRule {param($Name,$DisplayName,$Group,$Direction,$Action,$Protocol,$LocalPort,$Profile,$RemoteAddress,$ErrorAction)
        Assert (@($Profile) -contains 'Private' -and @($Profile) -notcontains 'Public' -and $RemoteAddress -ceq 'LocalSubnet' -and $Direction -ceq 'Inbound' -and $Action -ceq 'Allow' -and $Group -ceq 'TechMaster LAN') 'Firewall rules only allow inbound sharing from the local subnet on Private / Domain networks'
        $script:rules[$Name]=[pscustomobject]@{Name=$Name;Enabled='True';Ports=@($LocalPort)}
        [void]$script:calls.Add('Rule:'+$Name)
    }
    function Enable-NetFirewallRule {param($Name,$ErrorAction)$script:rules[$Name].Enabled='True';[void]$script:calls.Add('Enable:'+$Name)}
    function Get-NetConnectionProfile {param($ErrorAction)$script:netProfiles}
    function Set-NetConnectionProfile {param($InterfaceIndex,$NetworkCategory,$ErrorAction)[void]$script:calls.Add('Private:'+$InterfaceIndex);@($script:netProfiles | Where-Object {$_.InterfaceIndex -eq $InterfaceIndex})[0].NetworkCategory=$NetworkCategory}
    function Get-NetIPAddress {param($InterfaceIndex,$AddressFamily,$ErrorAction)if($InterfaceIndex -eq 12){[pscustomobject]@{IPAddress='192.168.1.10'}}elseif($InterfaceIndex -eq 7){[pscustomobject]@{IPAddress='10.0.0.5'}}}
    function Set-DeployFolderAccess([string]$Path,[string]$Account,[string]$Access){[void]$script:calls.Add('Ntfs:'+$Account+':'+$Access);$script:ntfs[$Account]=$Access}
    function Get-DeployFolderAccess([string]$Path,[string]$Account){if($script:ntfsBroken){'None'}elseif($script:ntfs.ContainsKey($Account)){$script:ntfs[$Account]}else{'None'}}
    function Get-DeployFolderSddl([string]$Path){'D:(A;OICI;FA;;;BA)'}
    $grants=@([pscustomobject]@{Role='Scan';Access='Read'},[pscustomobject]@{Role='Share';Access='Change'},[pscustomobject]@{Role='Print';Access='None'})

    $state=Get-DeployShareState $folderPath
    Assert ($state.Folder.Path -ceq $folderPath -and -not $state.Existing -and @($state.Accounts | Where-Object {$_.Exists}).Count -eq 2 -and -not $state.FirewallReady -and $state.Server -ceq 'Stopped') 'State lists the folder, existing accounts, firewall and server service'

    $r=Set-DeployFolderShare $folderPath 'KeToan' $grants $true @() $log
    Assert ($r.Kind -eq 'Success' -and $script:newShare.Path -ceq $folderPath -and $script:newShare.Mode -ceq 'AccessBased' -and ($script:newShare.Change -join ',') -ceq "$pc\share" -and ($script:newShare.Read -join ',') -ceq "$pc\scan" -and $script:newShare.Full.Count -eq 1) 'Share is created with Change for share, Read for scan, Full only for Administrators and access-based listing'
    Assert (-not @($script:newShare.Full+$script:newShare.Change+$script:newShare.Read | Where-Object {$_ -match 'Everyone|Guest|Mọi người'}).Count -and $r.Message -match 'Mật khẩu vẫn bắt buộc') 'Everyone / Guest are never given access'
    Assert ($script:ntfs["$pc\share"] -ceq 'Change' -and $script:ntfs["$pc\scan"] -ceq 'Read' -and -not $script:ntfs.ContainsKey("$pc\print")) 'NTFS matches the share permissions; a missing account with no access is skipped'
    Assert ($script:rules.Count -eq 2 -and $script:calls -contains 'Start:LanmanServer' -and $script:service.StartType -ceq 'Automatic') 'Firewall rules are added and the Server service is started'
    Assert ($r.Message.Contains("\\$pc\KeToan") -and $r.Message.Contains('\\192.168.1.10\KeToan') -and $r.Message -match 'share: Đọc & ghi' -and $r.Message -match 'scan: Chỉ đọc' -and $r.Unc -ceq "\\$pc\KeToan") 'Result shows the paths by computer name and IP, and the permissions'

    $before=$script:calls.Count
    Throws {Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Print';Access='Read'}) $false @() $log} 'Access for an account that does not exist yet is refused' 'Chưa có tài khoản print'
    Throws {Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Share';Access='None'}) $false @() $log} 'At least one account must get access' 'ít nhất một'
    Throws {Set-DeployFolderShare $folderPath 'An$' $grants $false @() $log} 'Hidden or invalid share names are refused' 'Tên chia sẻ'
    $other=Join-Path $temp 'Other';New-Item -ItemType Directory $other | Out-Null
    Throws {Set-DeployFolderShare $other 'KeToan' $grants $false @() $log} 'A share name already used for another folder is refused' 'thư mục khác'
    $script:admin=$false
    Throws {Set-DeployFolderShare $folderPath 'KeToan' $grants $false @() $log} 'Administrator rights are required'
    $script:admin=$true
    Assert ($script:calls.Count -eq $before) 'Refused requests change nothing'

    $state=Get-DeployShareState $folderPath
    Assert ($state.Existing.Name -ceq 'KeToan' -and $state.CurrentAccess["$pc\share"] -ceq 'Change' -and $state.CurrentAccess["$pc\scan"] -ceq 'Read' -and $state.FirewallReady) 'An existing share is recognised with its current permissions'
    $r=Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Scan';Access='None'},[pscustomobject]@{Role='Share';Access='Read'}) $true @() $log
    Assert ($r.Kind -eq 'Success' -and $r.Message -match 'Đã cập nhật' -and $script:calls -contains "Revoke:$pc\scan" -and $script:calls -contains "Grant:$pc\share:Read" -and -not ($script:calls -contains 'New:KeToan2') -and $script:ntfs["$pc\scan"] -ceq 'None' -and $script:ntfs["$pc\share"] -ceq 'Read') 'Updating replaces the permissions of the selected accounts only'
    Assert (@($script:calls | Where-Object {$_ -like 'Rule:*'}).Count -eq 2) 'Existing firewall rules are reused'

    $script:shareAccess['KeToan']=@(@($script:shareAccess['KeToan'] | Where-Object {$_ -and $_.AccountName -ine "$pc\share"})+[pscustomobject]@{AccountName="$pc\share";AccessControlType='Allow';AccessRight='Full'})
    $before=$script:calls.Count
    $r=Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Share';Access='Change'}) $true @() $log
    $made=@($script:calls | Select-Object -Skip $before)
    Assert ($r.Kind -eq 'Success' -and $made -contains "Revoke:$pc\share" -and $made -contains "Grant:$pc\share:Change" -and -not @($script:shareAccess['KeToan'] | Where-Object {$_.AccountName -ieq "$pc\share" -and $_.AccessRight -eq 'Full'}).Count) 'Full share access set by someone else is lowered to the chosen read & write'
    $script:netProfiles+=[pscustomobject]@{InterfaceIndex=7;InterfaceAlias='Wi-Fi';Name='VanPhong';NetworkCategory='Public'}
    $r=Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Share';Access='Change'}) $true @() $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match 'VanPhong' -and $r.Message -match 'Public' -and -not ($script:calls -contains 'Private:7')) 'A Public network is reported and never changed without being asked'
    $r=Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Share';Access='Change'}) $true @(7) $log
    Assert ($r.Kind -eq 'Success' -and $script:calls -contains 'Private:7' -and $r.Message.Contains('\\10.0.0.5\KeToan')) 'A Public network is made Private only when asked'

    $script:ntfsBroken=$true
    $r=Set-DeployFolderShare $folderPath 'KeToan' @([pscustomobject]@{Role='Share';Access='Change'}) $false @() $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match 'Quyền NTFS của share') 'Permissions Windows does not confirm are reported'
    $script:ntfsBroken=$false
    $entries=@(Get-Content $log | ForEach-Object {$_ | ConvertFrom-Json})
    Assert (@($entries | Where-Object Event -eq 'share-request').Count -ge 4 -and @($entries | Where-Object Event -eq 'share-verified').Count -ge 4 -and @($entries | Where-Object {$_.Event -eq 'share-request' -and $_.Data.NtfsBefore}).Count -ge 4) 'Each change logs the NTFS permissions before and the verification after'
    Write-Host "PASS: $checks LAN share assertions; real NTFS entries, protected folders, share names, share / NTFS permissions, LAN-only firewall, network profile and verification."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
