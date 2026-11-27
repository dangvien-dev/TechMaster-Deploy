# Client side of "Chạy TechMaster qua mạng" (Network.Launch.ps1, opened from \\MÁY\TechMaster$\App).
# The share carries its own list of program files: update-package.json in an installed copy (SHA256 of
# every file, launcher included) or update-source.json in a repository checkout (size + Git blob hash).
# 1. Without elevation (the share connection belongs to this sign-in): copy only the files that differ
#    into a private staging folder, checking each one against the list.
# 2. Elevated, as an inline command built here (no script from a folder users can write is run as
#    administrator): lock C:\TechMaster-Deploy to Administrators / SYSTEM, check the staged list by SHA256,
#    check every file again while writing it, then open the app.
# Functions used by the elevated step read no $script: variables: their text is sent as the command.
$script:DeployNetworkElevated=@('Test-DeployNetworkPath','Get-DeployNetworkBlobHash','Get-DeployNetworkSha256','ConvertFrom-DeployNetworkIndex','Test-DeployNetworkBytes','Test-DeployNetworkFile','Protect-DeployNetworkFolder','Install-DeployNetworkCopy','Start-DeployNetworkApp')
$script:DeployNetworkIndexNames=@('update-package.json','update-source.json')

function Test-DeployNetworkPath([string]$Path) {
    # Same program-file scope as the updater (Assert-DeployPath); the launcher is copied separately.
    if(-not $Path -or $Path.Contains('\') -or $Path.Contains(':') -or $Path.StartsWith('/')){return $false}
    foreach($part in ($Path -split '/')){if(-not $part -or $part -in '.','..' -or $part -match '[.\s]$|[\x00-\x1f<>"|?*]'){return $false}}
    if($Path -match '^BienBan/Logo\.'){return $false}
    return ($Path -match '^(App|Office|KichHoat|FixClone|BienBan)/[^/]+\.(ps1|cs|ico|svg|html|bat|xml|manifest|md)$' -or $Path -in 'README.md','PROGRESS.md','CHANGELOG.md','RELEASING.md','version.txt')
}
function Get-DeployNetworkBlobHash([byte[]]$Bytes) {
    $header=[Text.Encoding]::ASCII.GetBytes('blob '+$Bytes.Length+[char]0)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{[void]$sha.TransformBlock($header,0,$header.Length,$null,0);[void]$sha.TransformFinalBlock($Bytes,0,$Bytes.Length);([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Get-DeployNetworkSha256([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function ConvertFrom-DeployNetworkIndex([byte[]]$Bytes) {
    $index=[Text.Encoding]::UTF8.GetString($Bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $version=$null
    if([string]$index.product -cne 'TechMaster.Deploy' -or -not [version]::TryParse([string]$index.version,[ref]$version) -or -not @($index.files).Count){throw 'Danh sách tệp TechMaster (update-package.json / update-source.json) không hợp lệ.'}
    $package=[bool](@($index.files)[0].PSObject.Properties['sha256'])
    $seen=@{}
    $files=@(foreach($entry in @($index.files)){
        $path=[string]$entry.path
        # Files an installed copy keeps for the user (preserve) may differ: they are neither checked nor copied.
        if($package -and $entry.preserve -eq $true){continue}
        $valid=if($package){((Test-DeployNetworkPath $path) -or $path -ceq 'TechMaster Deploy.exe') -and [string]$entry.sha256 -match '^[0-9a-fA-F]{64}$'}else{(Test-DeployNetworkPath $path) -and [string]$entry.sha -cmatch '^[0-9a-f]{40}$' -and [long]$entry.size -ge 0}
        if(-not $valid -or $seen.ContainsKey($path.ToLowerInvariant())){throw ('Danh sách tệp TechMaster có mục không hợp lệ: '+$path)}
        $seen[$path.ToLowerInvariant()]=$true
        if($package){[pscustomobject]@{Path=$path;Size=[long]-1;Sha=([string]$entry.sha256).ToLowerInvariant();Kind='Sha256'}}
        else{[pscustomobject]@{Path=$path;Size=[long]$entry.size;Sha=[string]$entry.sha;Kind='Blob'}}
    })
    [pscustomobject]@{Version=$version;Files=$files;Format=$(if($package){'Package'}else{'Source'})}
}
function Test-DeployNetworkBytes([byte[]]$Bytes,$Entry) {
    if($Entry.Kind -ceq 'Sha256'){return ((Get-DeployNetworkSha256 $Bytes) -ceq $Entry.Sha)}
    return ($Bytes.Length -eq $Entry.Size -and (Get-DeployNetworkBlobHash $Bytes) -ceq $Entry.Sha)
}
# True only when the file on disk is exactly the listed version.
function Test-DeployNetworkFile([string]$Path,$Entry) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
    if($Entry.Kind -cne 'Sha256' -and ([IO.FileInfo]::new($Path)).Length -ne $Entry.Size){return $false}
    return (Test-DeployNetworkBytes ([IO.File]::ReadAllBytes($Path)) $Entry)
}
function Get-DeployNetworkTarget {Join-Path $env:SystemDrive 'TechMaster-Deploy'}
# A copy is trusted as it is only when the folder is locked (Protect-DeployNetworkFolder): owned by
# Administrators, no inherited entries and nobody but Administrators / SYSTEM may write. A folder any
# user could have filled is reinstalled from checked files instead of being opened as administrator.
function Test-DeployNetworkLocked([string]$Path) {
    try{
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
        $acl=[IO.DirectoryInfo]::new($Path).GetAccessControl()
        if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544'){return $false}
        # Write data / append / attributes / delete / child delete / DACL / owner, plus GENERIC_ALL and GENERIC_WRITE.
        $write=0x2 -bor 0x4 -bor 0x10 -bor 0x100 -bor 0x10000 -bor 0x40 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
        foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
            if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $rule.IdentityReference.Value -notin 'S-1-5-18','S-1-5-32-544' -and ([int]$rule.FileSystemRights -band $write)){return $false}
        }
        return $true
    }catch{return $false}
}
function Get-DeployNetworkLocalVersion([string]$Target) {
    $path=Join-Path $Target 'version.txt';$version=$null
    try{if((Test-Path -LiteralPath $path -PathType Leaf) -and [version]::TryParse(([IO.File]::ReadAllText($path)).Trim(),[ref]$version)){return $version}}catch{}
    return $null
}
# The list a program folder carries: update-package.json in an installed copy, update-source.json in a checkout.
function Get-DeployNetworkIndexFile([string]$Root) {
    foreach($name in $script:DeployNetworkIndexNames){$path=Join-Path $Root $name;if(Test-Path -LiteralPath $path -PathType Leaf){return [pscustomobject]@{Name=$name;Path=$path}}}
    return $null
}
# Files of $Root that differ from its own list; the sharing computer warns before clients fail.
function Get-DeployNetworkSourceProblems([string]$Root) {
    $file=Get-DeployNetworkIndexFile $Root
    if(-not $file){return @('Thiếu danh sách tệp update-package.json.')}
    try{$index=ConvertFrom-DeployNetworkIndex ([IO.File]::ReadAllBytes($file.Path))}catch{return @($_.Exception.GetBaseException().Message)}
    @(foreach($entry in $index.Files){if(-not (Test-DeployNetworkFile (Join-Path $Root ($entry.Path.Replace('/','\'))) $entry)){$entry.Path}})
}
function Copy-DeployNetworkStage([string]$Source,[string]$Target,[string]$Staging,[scriptblock]$Progress=$null) {
    $file=Get-DeployNetworkIndexFile $Source
    if(-not $file){throw 'Thư mục chia sẻ không có danh sách tệp TechMaster (update-package.json). Trên máy chia sẻ, cập nhật hoặc giải nén lại TechMaster rồi chia sẻ lại.'}
    $indexBytes=[IO.File]::ReadAllBytes($file.Path)
    $index=ConvertFrom-DeployNetworkIndex $indexBytes
    $entries=@($index.Files)
    $local=Get-DeployNetworkLocalVersion $Target
    $result=[pscustomobject]@{Version=$index.Version;LocalVersion=$local;Action='';Staged=0;Total=$entries.Count;IndexName=$file.Name;IndexSha256=(Get-DeployNetworkSha256 $indexBytes);ExeSha256='';Staging=$Staging}
    if($local -and $local -gt $index.Version -and (Test-DeployNetworkLocked $Target)){$result.Action='KeepNewer';return $result}
    # A checkout's list has no launcher: it is checked by SHA256 like the listed files.
    $exe=Join-Path $Source 'TechMaster Deploy.exe'
    if(-not @($entries | Where-Object {$_.Path -ceq 'TechMaster Deploy.exe'}).Count -and (Test-Path -LiteralPath $exe -PathType Leaf)){
        $result.ExeSha256=Get-DeployNetworkSha256 ([IO.File]::ReadAllBytes($exe))
        $entries+=[pscustomobject]@{Path='TechMaster Deploy.exe';Size=[long]-1;Sha=$result.ExeSha256;Kind='Sha256'}
    }
    New-Item -ItemType Directory -Path $Staging -Force | Out-Null
    $count=0
    foreach($entry in $entries){
        $count++
        if($Progress){& $Progress $count $entries.Count $entry.Path}
        $relative=$entry.Path.Replace('/','\')
        $same=$false;try{$same=Test-DeployNetworkFile (Join-Path $Target $relative) $entry}catch{}
        if($same){continue}
        $from=Join-Path $Source $relative
        if(-not (Test-Path -LiteralPath $from -PathType Leaf)){throw ('Thư mục chia sẻ thiếu tệp '+$entry.Path+'. Trên máy chia sẻ, cập nhật lại TechMaster.')}
        $bytes=[IO.File]::ReadAllBytes($from)
        if(-not (Test-DeployNetworkBytes $bytes $entry)){throw ('Tệp '+$entry.Path+' trên máy chia sẻ không khớp danh sách (đã bị sửa hoặc chép dở). Trên máy chia sẻ, cập nhật lại TechMaster.')}
        $to=Join-Path $Staging $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
        [IO.File]::WriteAllBytes($to,$bytes)
        $result.Staged++
    }
    [IO.File]::WriteAllBytes((Join-Path $Staging $file.Name),$indexBytes)
    $result.Action=if($result.Staged){'Install'}else{'UpToDate'}
    return $result
}
function Protect-DeployNetworkFolder([string]$Path) {
    # Administrators / SYSTEM change the program, Users only read and run it. The folder's whole DACL is
    # replaced in one step (explicit entries of any other account go too), then owner and child entries
    # are reset, so an account that created or opened up this folder earlier cannot change it afterwards.
    $run={param([string[]]$Arguments)$output=& icacls.exe @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw ('Không khoá được quyền thư mục '+$Path+': '+(($output | Out-String).Trim()))}}
    & $run @($Path,'/setowner','*S-1-5-32-544','/C','/Q')
    $security=New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true,$false)
    $inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach($rule in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))){
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($rule[0])),([Security.AccessControl.FileSystemRights]$rule[1]),$inherit,([Security.AccessControl.PropagationFlags]::None),([Security.AccessControl.AccessControlType]::Allow))))
    }
    [IO.Directory]::SetAccessControl($Path,$security)
    & $run @($Path,'/setowner','*S-1-5-32-544','/T','/C','/Q')
    if(@(Get-ChildItem -LiteralPath $Path -Force).Count){& $run @((Join-Path $Path '*'),'/reset','/T','/C','/Q')}
}
function Install-DeployNetworkCopy([string]$Staging,[string]$IndexName,[string]$IndexSha256,[string]$ExeSha256,[string]$Target) {
    if($IndexName -cnotin 'update-package.json','update-source.json'){throw 'Tên danh sách tệp không hợp lệ.'}
    $indexBytes=[IO.File]::ReadAllBytes((Join-Path $Staging $IndexName))
    if((Get-DeployNetworkSha256 $indexBytes) -cne $IndexSha256){throw 'Danh sách tệp đã chép bị thay đổi trước khi cài. Chạy lại Chay-Tu-Mang.bat.'}
    $index=ConvertFrom-DeployNetworkIndex $indexBytes
    if(Test-Path -LiteralPath $Target){
        $item=Get-Item -LiteralPath $Target -Force
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ('Không dùng được '+$Target+': không phải thư mục thường.')}
    }else{New-Item -ItemType Directory -Path $Target -Force | Out-Null}
    # Lock first: from here on only administrators can change what is checked and run.
    Protect-DeployNetworkFolder $Target
    $written=0
    $items=@($index.Files)
    if($ExeSha256 -and -not @($items | Where-Object {$_.Path -ceq 'TechMaster Deploy.exe'}).Count){$items+=[pscustomobject]@{Path='TechMaster Deploy.exe';Size=[long]-1;Sha=$ExeSha256;Kind='Sha256'}}
    foreach($entry in $items){
        $relative=$entry.Path.Replace('/','\')
        $to=Join-Path $Target $relative;$staged=Join-Path $Staging $relative
        if(Test-Path -LiteralPath $staged -PathType Leaf){
            $bytes=[IO.File]::ReadAllBytes($staged)
            if(-not (Test-DeployNetworkBytes $bytes $entry)){throw ('Tệp đã chép bị thay đổi trước khi cài: '+$entry.Path+'. Chạy lại Chay-Tu-Mang.bat.')}
            New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
            $temp=$to+'.tm-new'
            [IO.File]::WriteAllBytes($temp,$bytes)
            try{[IO.File]::Copy($temp,$to,$true)}
            catch{throw ('Không ghi được '+$entry.Path+'. Đóng TechMaster Deploy đang mở trên máy này rồi chạy lại. ('+$_.Exception.GetBaseException().Message+')')}
            finally{[IO.File]::Delete($temp)}
            $written++
        }elseif(-not (Test-DeployNetworkFile $to $entry)){
            # Unchanged files and the launcher are checked here, after the lock, before anything runs as administrator.
            throw ($entry.Path+' trên máy này không khớp bản trên máy chia sẻ. Chạy lại Chay-Tu-Mang.bat.')
        }
    }
    # The list goes with the program, so the app's updater knows the installed version; a stale list of the other kind is removed.
    [IO.File]::WriteAllBytes((Join-Path $Target $IndexName),$indexBytes)
    foreach($other in @('update-package.json','update-source.json' | Where-Object {$_ -cne $IndexName})){Remove-Item -LiteralPath (Join-Path $Target $other) -Force -ErrorAction SilentlyContinue}
    # Lock again so files written now are owned by Administrators like the rest.
    Protect-DeployNetworkFolder $Target
    Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{Target=$Target;Written=$written;Total=$index.Files.Count;Version=$index.Version;ExeChecked=[bool]@($items | Where-Object {$_.Path -ceq 'TechMaster Deploy.exe'}).Count}
}
# -Script opens App\TechMaster-Deploy.ps1 directly: used when the launcher was not checked against the share.
function Start-DeployNetworkApp([string]$Target,[switch]$Elevate,[switch]$Script) {
    $exe=Join-Path $Target 'TechMaster Deploy.exe'
    if(-not $Script -and (Test-Path -LiteralPath $exe -PathType Leaf)){Start-Process -FilePath $exe -WorkingDirectory $Target | Out-Null;return}
    $arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "'+(Join-Path $Target 'App\TechMaster-Deploy.ps1')+'"'
    if($Elevate){Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -WorkingDirectory $Target | Out-Null}
    else{Start-Process powershell.exe -ArgumentList $arguments -WorkingDirectory $Target | Out-Null}
}
function Get-DeployNetworkElevatedCommand([string]$Staging,[string]$IndexName,[string]$IndexSha256,[string]$ExeSha256,[string]$Target) {
    $quote={param($value)"'"+([string]$value).Replace("'","''")+"'"}
    $lines=@('$ErrorActionPreference=''Stop''')
    foreach($name in $script:DeployNetworkElevated){$lines+=('function '+$name+' {'+(Get-Command $name -CommandType Function).ScriptBlock.ToString()+'}')}
    $lines+=@(
        'try{',
        ('    Write-Host ''Đang kiểm tra và cài TechMaster Deploy vào '+([string]$Target).Replace("'","''")+'…'''),
        ('    $r=Install-DeployNetworkCopy '+(& $quote $Staging)+' '+(& $quote $IndexName)+' '+(& $quote $IndexSha256)+' '+(& $quote $ExeSha256)+' '+(& $quote $Target)),
        '    Write-Host (''✓ Phiên bản ''+$r.Version+'': đã kiểm tra ''+$r.Total+'' tệp, cập nhật ''+$r.Written+'' tệp. Đang mở TechMaster Deploy…'') -ForegroundColor Green',
        '    Start-DeployNetworkApp $r.Target -Script:(-not $r.ExeChecked)',
        '    Start-Sleep -Seconds 2',
        '}catch{',
        '    Write-Host (''✗ ''+$_.Exception.GetBaseException().Message) -ForegroundColor Red',
        '    [void](Read-Host ''Nhấn Enter để đóng'')',
        '    exit 1',
        '}')
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($lines -join "`n")))
}
# Entry used by Network.Launch.ps1. Returns what happened; throws with a message for the user.
function Start-DeployNetworkRun([string]$Source,[string]$Target='') {
    if(-not $Target){$Target=Get-DeployNetworkTarget}
    $staging=Join-Path ([IO.Path]::GetTempPath()) ('TechMaster-Net-'+[guid]::NewGuid().ToString('N'))
    try{
        $copy=Copy-DeployNetworkStage $Source $Target $staging {param($index,$total,$path)Write-Progress -Activity 'Đang chép TechMaster Deploy từ máy chia sẻ' -Status ($index.ToString()+'/'+$total+'  '+$path) -PercentComplete ([int](100*$index/$total))}
        Write-Progress -Activity 'Đang chép TechMaster Deploy từ máy chia sẻ' -Completed
        if($copy.Action -eq 'KeepNewer'){
            Write-Host ('Máy này đã có bản mới hơn ('+$copy.LocalVersion+') tại '+$Target+'; mở bản đó.')
            Start-DeployNetworkApp $Target -Elevate
            return [pscustomobject]@{Action='KeepNewer';Target=$Target;Version=$copy.LocalVersion}
        }
        Write-Host ('Phiên bản '+$copy.Version+': chép '+$copy.Staged+' tệp mới / thay đổi. Chọn Yes ở hộp quyền quản trị để cài vào '+$Target+'.')
        $command=Get-DeployNetworkElevatedCommand $staging $copy.IndexName $copy.IndexSha256 $copy.ExeSha256 $Target
        try{$process=Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$command) -PassThru}
        catch{throw 'Cần quyền quản trị để cài và mở TechMaster Deploy. Chạy lại Chay-Tu-Mang.bat và chọn Yes.'}
        # Wait for the installer only, not for the app it opens.
        $process.WaitForExit()
        $code=0;try{$code=$process.ExitCode}catch{}
        if($code -ne 0){throw 'Chưa cài được TechMaster Deploy; xem thông báo trong cửa sổ quản trị.'}
        return [pscustomobject]@{Action=$copy.Action;Target=$Target;Version=$copy.Version}
    }finally{if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue}}
}
