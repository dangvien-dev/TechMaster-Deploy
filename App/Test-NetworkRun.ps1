# Client side: real copy, hash checks, folder lock and install into temporary folders (no app is opened).
# Sharing computer: SMB share, services, firewall, network and NTFS calls are mocked.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NetworkRun.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m,$pattern=''){$failed=$false;$text='';try{& $action | Out-Null}catch{$failed=$true;$text=$_.Exception.GetBaseException().Message};Assert ($failed -and (-not $pattern -or $text -match $pattern)) "$m ($text)"}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-netrun-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
function Write-Fixture([string]$Root,[string]$Path,[string]$Text){$full=Join-Path $Root ($Path.Replace('/','\'));New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null;[IO.File]::WriteAllText($full,$Text,$utf8)}
function Write-Index([string]$Root,[string]$Version,[string[]]$Paths){
    $files=@(foreach($path in $Paths){$bytes=[IO.File]::ReadAllBytes((Join-Path $Root ($path.Replace('/','\'))));[ordered]@{path=$path;mode='100644';size=$bytes.Length;sha=(Get-DeployNetworkBlobHash $bytes)}})
    [IO.File]::WriteAllText((Join-Path $Root 'update-source.json'),(([ordered]@{schema=1;product='TechMaster.Deploy';repository='dangvien-dev/TechMaster-Deploy';branch='main';version=$Version;files=$files}) | ConvertTo-Json -Depth 5),$utf8)
}
function Get-Acl2([string]$Path){[IO.DirectoryInfo]::new($Path).GetAccessControl()}
try{
    # Blob hashes are Git's own: empty file and "hello\n".
    Assert ((Get-DeployNetworkBlobHash ([byte[]]@())) -ceq 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391' -and (Get-DeployNetworkBlobHash ([Text.Encoding]::ASCII.GetBytes("hello`n"))) -ceq 'ce013625030ba8dba906f756967f9e9ca394464a') 'Blob hashes match Git'
    foreach($path in 'App/TechMaster-Deploy.ps1','FixClone/Run.bat','version.txt','README.md'){Assert (Test-DeployNetworkPath $path) "$path is a program file"}
    foreach($path in '../x.ps1','App/../x.ps1','App\x.ps1','C:/x.ps1','/App/x.ps1','App/sub/x.ps1','App/x.exe','BienBan/Logo.svg','TechMaster Deploy.exe','App/x.ps1 ','KhoOffice/a.xml'){Assert (-not (Test-DeployNetworkPath $path)) "$path is refused"}

    $source=Join-Path $temp 'share';$target=Join-Path $temp 'TechMaster-Deploy'
    $program=@('version.txt','README.md','App/TechMaster-Deploy.ps1','App/Network.Launch.ps1','App/Network.Sync.ps1','App/Chay-Tu-Mang.bat','App/MainWindow.xml')
    foreach($path in $program){Write-Fixture $source $path ('# '+$path+" — nội dung tiếng Việt`n")}
    Write-Fixture $source 'version.txt' '2.2.24.0'
    Write-Index $source '2.2.24.0' $program
    [IO.File]::WriteAllBytes((Join-Path $source 'TechMaster Deploy.exe'),[byte[]](1..200))
    $bad=[IO.File]::ReadAllText((Join-Path $source 'update-source.json'))
    Throws {ConvertFrom-DeployNetworkIndex ([Text.Encoding]::UTF8.GetBytes($bad.Replace('TechMaster.Deploy','Other.App')))} 'Another product list is refused' 'không hợp lệ'
    Throws {ConvertFrom-DeployNetworkIndex ([Text.Encoding]::UTF8.GetBytes($bad.Replace('App/MainWindow.xml','App/../../Windows/x.xml')))} 'A path leaving the program folder is refused' 'mục không hợp lệ'
    Throws {ConvertFrom-DeployNetworkIndex ([Text.Encoding]::UTF8.GetBytes($bad.Replace('"README.md"','"readme.MD"').Replace('"version.txt"','"README.md"')))} 'A list naming a file twice is refused' 'mục không hợp lệ'
    Assert (@(Get-DeployNetworkSourceProblems $source).Count -eq 0) 'An untouched program folder has no problems'

    # First run: nothing on this computer yet.
    $staging=Join-Path $temp 'stage1'
    $seen=New-Object Collections.ArrayList
    $r=Copy-DeployNetworkStage $source $target $staging {param($i,$n,$p)[void]$seen.Add($p)}
    $indexSha=Get-DeployNetworkSha256 ([IO.File]::ReadAllBytes((Join-Path $source 'update-source.json')))
    Assert ($r.Action -ceq 'Install' -and $r.Staged -eq ($program.Count+1) -and $r.IndexSha256 -ceq $indexSha -and $r.ExeSha256 -ceq (Get-DeployNetworkSha256 ([byte[]](1..200))) -and $seen.Count -eq $program.Count -and -not (Test-Path $target)) 'Every file and the launcher are staged; nothing is written to the program folder before elevation'
    Assert ((Test-Path (Join-Path $staging 'App\MainWindow.xml')) -and (Test-Path (Join-Path $staging 'update-source.json')) -and (Test-Path (Join-Path $staging 'TechMaster Deploy.exe'))) 'Staging holds the files, the list and the launcher'
    $i=Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target
    Assert ($i.Written -eq ($program.Count+1) -and $i.Total -eq $program.Count -and $i.ExeChecked -and $i.Version -eq [version]'2.2.24.0' -and -not (Test-Path $staging)) 'The elevated step writes every checked file and removes the staging folder'
    foreach($path in $program+@('update-source.json','TechMaster Deploy.exe')){Assert ([IO.File]::ReadAllBytes((Join-Path $target $path)).Length -eq [IO.File]::ReadAllBytes((Join-Path $source $path)).Length) "$path is installed"}
    Assert (@(Get-ChildItem -LiteralPath $target -Recurse -Filter '*.tm-new').Count -eq 0) 'No temporary file is left behind'
    $acl=Get-Acl2 $target
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $users=@($rules | Where-Object {$_.IdentityReference.Value -eq 'S-1-5-32-545'})
    $writers=@($rules | Where-Object {$_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin 'S-1-5-18','S-1-5-32-544' -and ([int]$_.FileSystemRights -band ([int][Security.AccessControl.FileSystemRights]::WriteData -bor [int][Security.AccessControl.FileSystemRights]::AppendData -bor [int][Security.AccessControl.FileSystemRights]::Delete -bor [int][Security.AccessControl.FileSystemRights]::ChangePermissions -bor [int][Security.AccessControl.FileSystemRights]::TakeOwnership))})
    Assert ($acl.AreAccessRulesProtected -and $users.Count -ge 1 -and $writers.Count -eq 0 -and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') ("Program folder: inheritance off, owner Administrators, only Administrators / SYSTEM can change it (protected=$($acl.AreAccessRulesProtected) users=$($users.Count) writers=$(@($writers | ForEach-Object {$_.IdentityReference.Value+':'+[int]$_.FileSystemRights}) -join ',') sddl=$($acl.GetSecurityDescriptorSddlForm('All')))")
    $fileAcl=[IO.File]::GetAccessControl((Join-Path $target 'App\TechMaster-Deploy.ps1'))
    Assert (@($fileAcl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])).Count -eq 0 -and $fileAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') 'Program files only inherit the locked folder rules'

    # Second run: everything already matches.
    $staging=Join-Path $temp 'stage2'
    $r=Copy-DeployNetworkStage $source $target $staging
    Assert ($r.Action -ceq 'UpToDate' -and $r.Staged -eq 0 -and $r.ExeSha256 -and @(Get-ChildItem -LiteralPath $staging -File).Count -eq 1) 'An up-to-date copy stages only the list'
    $i=Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target
    Assert ($i.Written -eq 0 -and $i.ExeChecked) 'Unchanged files and the launcher are re-checked after the lock, nothing rewritten'

    # One file changed on this computer: only that file is copied again.
    $local=Join-Path $target 'App\MainWindow.xml';$saved=[IO.File]::ReadAllBytes($local)
    [IO.File]::WriteAllText($local,'changed',$utf8)
    $staging=Join-Path $temp 'stage3'
    $r=Copy-DeployNetworkStage $source $target $staging
    Assert ($r.Action -ceq 'Install' -and $r.Staged -eq 1 -and (Test-Path (Join-Path $staging 'App\MainWindow.xml'))) 'Only the changed file is staged'
    [IO.File]::WriteAllText((Join-Path $staging 'App\MainWindow.xml'),'tampered',$utf8)
    Throws {Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target} 'A staged file changed before elevation is refused' 'bị thay đổi trước khi cài'
    [IO.File]::WriteAllText((Join-Path $staging 'update-source.json'),'{}',$utf8)
    Throws {Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target} 'A staged list changed before elevation is refused' 'Danh sách tệp đã chép bị thay đổi'
    Remove-Item -LiteralPath $staging -Recurse -Force
    [IO.File]::WriteAllBytes($local,$saved)

    # Unchanged files are trusted only after the lock: a change between the two steps stops the install.
    $staging=Join-Path $temp 'stage4'
    $r=Copy-DeployNetworkStage $source $target $staging
    [IO.File]::WriteAllText((Join-Path $target 'README.md'),'swapped',$utf8)
    Throws {Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target} 'A program file changed between the steps is refused' 'không khớp bản trên máy chia sẻ'
    [IO.File]::WriteAllText((Join-Path $target 'README.md'),"# README.md — nội dung tiếng Việt`n",$utf8)
    [IO.File]::WriteAllBytes((Join-Path $target 'TechMaster Deploy.exe'),[byte[]](5..9))
    Throws {Install-DeployNetworkCopy $staging $r.IndexSha256 $r.ExeSha256 $target} 'A launcher changed between the steps is refused before it can run' 'TechMaster Deploy.exe trên máy này không khớp'
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllBytes((Join-Path $target 'TechMaster Deploy.exe'),[byte[]](1..200))

    # A changed file on the share stops the copy.
    $shared=Join-Path $source 'App\TechMaster-Deploy.ps1';$original=[IO.File]::ReadAllBytes($shared)
    [IO.File]::WriteAllText($shared,'edited on the share',$utf8)
    Throws {Copy-DeployNetworkStage $source (Join-Path $temp 'fresh') (Join-Path $temp 'stage5')} 'A share file that differs from its list is refused' 'không khớp danh sách'
    Assert ((@(Get-DeployNetworkSourceProblems $source) -join '|') -ceq 'App/TechMaster-Deploy.ps1') 'The sharing computer can name the changed file'
    [IO.File]::WriteAllBytes($shared,$original)

    # A newer copy is opened as it is only from a locked folder; one any user could write is reinstalled.
    Assert ((Test-DeployNetworkLocked $target) -and -not (Test-DeployNetworkLocked $temp) -and -not (Test-DeployNetworkLocked (Join-Path $temp 'missing'))) 'Only the locked program folder counts as locked'
    $newer=Join-Path $temp 'newer';Write-Fixture $newer 'version.txt' '9.0.0.0'
    $r=Copy-DeployNetworkStage $source $newer (Join-Path $temp 'stage6')
    Assert ($r.Action -ceq 'Install' -and $r.Staged -eq ($program.Count+1)) 'A newer copy in an unlocked folder is not trusted: the checked files are installed'
    Remove-Item -LiteralPath (Join-Path $temp 'stage6') -Recurse -Force
    Protect-DeployNetworkFolder $newer
    $r=Copy-DeployNetworkStage $source $newer (Join-Path $temp 'stage7')
    Assert ($r.Action -ceq 'KeepNewer' -and $r.LocalVersion -eq [version]'9.0.0.0' -and -not (Test-Path (Join-Path $temp 'stage7'))) 'A newer copy in a locked folder is kept and nothing is staged'

    # The elevated command: parses, carries its own functions and escapes quotes in paths.
    $command=Get-DeployNetworkElevatedCommand "C:\Temp\O'Brien\stage" $indexSha '' 'C:\TechMaster-Deploy'
    $text=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($command))
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    Assert (@($errors).Count -eq 0) ('The elevated command parses: '+(@($errors) -join '; '))
    Assert ($text.Contains("'C:\Temp\O''Brien\stage'") -and $text.Contains("'$indexSha'") -and -not $text.Contains('$script:')) 'Paths are quoted and the command does not depend on script variables'
    foreach($name in $script:DeployNetworkElevated){Assert ($text.Contains('function '+$name+' {')) "The elevated command defines $name"}
    Assert (('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$command).Length -lt 30000) "The elevated command fits on a Windows command line ($($command.Length))"

    # --- Sharing computer (mocked) ---
    $log=Join-Path $temp 'network.jsonl'
    $pc=[string]$env:COMPUTERNAME;$me=[string][Security.Principal.WindowsIdentity]::GetCurrent().Name
    $script:admin=$true;$script:calls=New-Object Collections.ArrayList;$script:shares=@{};$script:access=@{};$script:lanUsers=@('share')
    $script:service=[pscustomobject]@{Status='Stopped';StartType='Manual'};$script:profiles=@([pscustomobject]@{Index=7;Alias='Ethernet';Name='CongTy';Category='Private'});$script:ntfs=@{}
    function Assert-DeployLanAdmin {if(-not $script:admin){throw 'admin required'}}
    function Find-DeployLanUser([string]$Name){if($script:lanUsers -contains $Name){[pscustomobject]@{Name=$Name}}else{$null}}
    function Get-SmbShare {param($Name,$ErrorAction)@($script:shares.Values)}
    function Get-SmbShareAccess {param($Name,$ErrorAction)@($script:access[$Name])}
    function New-SmbShare {param($Name,$Path,$FullAccess,$ChangeAccess,$ReadAccess,$FolderEnumerationMode,$Description,$ErrorAction)
        [void]$script:calls.Add('New:'+$Name+':'+(@($ReadAccess) -join ',')+':'+[bool]$FullAccess+':'+[bool]$ChangeAccess)
        $script:shares[$Name]=[pscustomobject]@{Name=$Name;Path=$Path;Description=$Description}
        $script:access[$Name]=@($ReadAccess | ForEach-Object {[pscustomobject]@{AccountName=$_;AccessRight='Read';AccessControlType='Allow'}})}
    function Remove-SmbShare {param($Name,[switch]$Force,$ErrorAction)[void]$script:calls.Add('Remove:'+$Name);$script:shares.Remove($Name);$script:access.Remove($Name)}
    function Get-Service {param($Name,$ErrorAction)$script:service}
    function Start-Service {param($Name,$ErrorAction)[void]$script:calls.Add('Start:'+$Name);$script:service.Status='Running'}
    function Set-Service {param($Name,$StartupType,$ErrorAction)[void]$script:calls.Add('Startup:'+$StartupType)}
    function Get-DeployShareFirewallState {@([pscustomobject]@{Name='TechMaster-LAN-SMB-TCP';Exists=$script:firewallOn;Enabled=$script:firewallOn})}
    function Enable-DeployShareFirewall([string]$LogPath){[void]$script:calls.Add('Firewall');$script:firewallOn=$true}
    function Get-DeployNetworkProfiles {@($script:profiles)}
    function Get-DeployShareAddresses($Profiles){@('192.168.1.20')}
    function Set-NetConnectionProfile {param($InterfaceIndex,$NetworkCategory,$ErrorAction)[void]$script:calls.Add('Private:'+$InterfaceIndex);foreach($p in $script:profiles){if($p.Index -eq $InterfaceIndex){$p.Category='Private'}}}
    function Test-DeployNetworkNtfs([string]$Path){$true}
    function Get-DeployFolderAccess([string]$Path,[string]$Account){if($script:ntfs.ContainsKey($Account)){$script:ntfs[$Account]}else{'None'}}
    function Set-DeployFolderAccess([string]$Path,[string]$Account,[string]$Access){[void]$script:calls.Add('Ntfs:'+$Account+':'+$Access);$script:ntfs[$Account]=$Access}
    $script:firewallOn=$false

    Throws {Get-DeployNetworkRoot 'C:\'} 'A whole drive is never shared' 'không phải cả ổ'
    Throws {Get-DeployNetworkRoot '\\SERVER\Apps\TechMaster'} 'A network folder is refused' 'không phải cả ổ hay thư mục mạng'
    Throws {Get-DeployNetworkRoot (Join-Path $temp 'newer')} 'A folder that is not a TechMaster program folder is refused' 'thiếu'
    Assert ((Get-DeployNetworkRoot ($source+'\')) -ceq $source) 'The program folder is accepted without a trailing slash'
    $accounts=@(Get-DeployNetworkAccounts)
    Assert ($accounts.Count -eq 2 -and $accounts[0].Account -ceq $me -and -not $accounts[0].Lan -and $accounts[1].Account -ceq ($pc+'\share') -and $accounts[1].Lan) 'The current account and the LAN account share are offered; scan / print are not'
    Assert ((@(Get-DeployNetworkClientPaths 'KY-THUAT' @('192.168.1.20')) -join '|') -ceq '\\KY-THUAT\TechMaster$\App\Chay-Tu-Mang.bat|\\192.168.1.20\TechMaster$\App\Chay-Tu-Mang.bat') 'Client paths by name and by IP'

    $r=Set-DeployNetworkRunShare $source $me $true @() $log
    Assert ($script:calls -contains ('New:TechMaster$:'+$me+':False:False') -and $script:shares['TechMaster$'].Path -ceq $source -and $script:shares['TechMaster$'].Description -ceq $script:DeployNetworkShareMarker) 'Hidden share TechMaster$ is read-only for the chosen account, with no full / change access'
    Assert (@($script:calls | Where-Object {$_ -like 'Ntfs:*'}).Count -eq 0) 'The account using the app gets no NTFS change'
    Assert ($script:calls -contains 'Start:LanmanServer' -and $script:calls -contains 'Firewall' -and $r.Kind -ceq 'Success') "Server service and firewall are turned on ($($r.Message))"
    Assert ($r.Message.Contains('\\'+$pc+'\TechMaster$\App\Chay-Tu-Mang.bat') -and $r.Message.Contains('\\192.168.1.20\TechMaster$\App\Chay-Tu-Mang.bat') -and $r.Message.Contains($me) -and $r.Message -match 'C:\\TechMaster-Deploy') 'Result tells what to open on the other computer and with which account'
    $before=$script:calls.Count
    $r=Set-DeployNetworkRunShare $source $me $false @() $log
    Assert (@($script:calls | Select-Object -Skip $before | Where-Object {$_ -like 'New:*' -or $_ -like 'Remove:*'}).Count -eq 0 -and $r.Kind -ceq 'Success') 'Sharing again with the same account changes nothing'
    $state=Get-DeployNetworkRunState $source
    Assert ($state.Active -and $state.Account -ceq $me -and $state.ClientPaths.Count -eq 2 -and @($state.SourceProblems).Count -eq 0) 'State reads the active share and its account'

    $before=$script:calls.Count
    $r=Set-DeployNetworkRunShare $source ($pc+'\share') $true @() $log
    $after=@($script:calls | Select-Object -Skip $before)
    Assert ($after -contains 'Remove:TechMaster$' -and $after -contains ('Ntfs:'+$pc+'\share:Read') -and $after -contains ('New:TechMaster$:'+$pc+'\share:False:False')) 'Switching to the LAN account replaces the share and gives it NTFS read on the program folder'
    $script:profiles[0].Category='Public'
    $r=Set-DeployNetworkRunShare $source ($pc+'\share') $true @() $log
    Assert ($r.Kind -ceq 'Attention' -and $r.Message -match 'Public') 'A Public network is reported'
    $r=Set-DeployNetworkRunShare $source ($pc+'\share') $true @(7) $log
    Assert ($script:calls -contains 'Private:7' -and $r.Kind -ceq 'Success') 'The Public network is switched only when asked'
    Throws {Set-DeployNetworkRunShare $source ($pc+'\scan') $true @() $log} 'An account that is not offered is refused' 'Chọn tài khoản'
    $script:admin=$false
    Throws {Set-DeployNetworkRunShare $source $me $true @() $log} 'Sharing needs administrator rights' 'admin required'
    $script:admin=$true
    [IO.File]::WriteAllText($shared,'edited',$utf8)
    Throws {Set-DeployNetworkRunShare $source $me $true @() $log} 'A program folder with changed files is not shared' 'khác danh sách'
    [IO.File]::WriteAllBytes($shared,$original)

    $before=$script:calls.Count
    $r=Remove-DeployNetworkRunShare $log
    $after=@($script:calls | Select-Object -Skip $before)
    Assert ($r.Kind -ceq 'Success' -and $after -contains 'Remove:TechMaster$' -and $after -contains ('Ntfs:'+$pc+'\share:None') -and -not $script:shares.ContainsKey('TechMaster$')) 'Stopping removes the share and the NTFS read it added'
    $r=Remove-DeployNetworkRunShare $log
    Assert ($r.Kind -ceq 'Info') 'Stopping when nothing is shared is reported plainly'
    $script:shares['TechMaster$']=[pscustomobject]@{Name='TechMaster$';Path='D:\Other';Description='someone else'};$script:access['TechMaster$']=@()
    $before=$script:calls.Count
    Throws {Set-DeployNetworkRunShare $source $me $true @() $log} 'A TechMaster$ share made by someone else is not replaced' 'không do app tạo'
    Throws {Remove-DeployNetworkRunShare $log} 'A TechMaster$ share made by someone else is not removed' 'không do app tạo'
    Assert (@($script:calls | Select-Object -Skip $before | Where-Object {$_ -like 'Remove:*' -or $_ -like 'New:*'}).Count -eq 0) 'Nothing is changed on a foreign share'
    Write-Host "PASS: $checks network run assertions; Git blob hashes, program-file scope, staged copy, folder lock, re-check after lock, tamper refusal, newer copy kept, elevated command and read-only TechMaster$ share."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
