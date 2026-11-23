# Mutations run only here. No driver download, signature bypass, forced reboot or BIOS edits.
. (Join-Path $PSScriptRoot 'DriverFix.Core.ps1')
function Write-DriverFixLog($Session,[string]$Event,$Data) {
    $entry=[ordered]@{time=(Get-Date).ToString('o');event=$Event;data=$Data}
    [IO.File]::AppendAllText($Session.LogPath,(($entry|ConvertTo-Json -Depth 14 -Compress)+"`r`n"),[Text.UTF8Encoding]::new($false))
}
function Test-DriverFixAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-DriverFixAdmin($Session,[string]$Action) {
    Write-DriverFixLog $Session 'request' @{action=$Action}
    if(-not (Test-DriverFixAdmin)){Write-DriverFixLog $Session 'denied' @{action=$Action;reason='Administrator required'};throw 'Thao tác cần quyền Administrator. Đóng và mở Fix Driver bằng quyền quản trị.'}
}
function New-DriverFixSession([string]$DataRoot) {
    if(-not $DataRoot){$DataRoot=Get-DriverFixHome}
    $dir=Join-Path $DataRoot ('Sessions/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $dir -Force|Out-Null
    # Persist an initialization log before querying WMI, including failures that
    # happen before a full session can be returned to the window.
    $session=[pscustomobject]@{Home=$DataRoot;Directory=$dir;LogPath=(Join-Path $dir 'events.jsonl');CancelPath=(Join-Path $dir 'cancel');Machine=$null;Before=$null;Current=$null;Profile=$null;Profiles=$null;MatchedCount=0;Actions=(New-Object Collections.ArrayList);LastDelta=$null}
    Write-DriverFixLog $session 'session-start' @{computer=$env:COMPUTERNAME}
    try{
        $snapshot=Get-DriverFixSnapshot;$machine=Get-DriverFixMachine;$profiles=Get-DriverFixProfiles (Join-Path $DataRoot 'Profiles')
        $matched=@($profiles.Items|Where-Object {Test-DriverFixProfileMatch $_ $machine $snapshot})
        # Ambiguous profiles never enable automatic model-specific actions.
        $profile=$null;if($matched.Count -eq 1){$profile=$matched[0]}
        $session.Machine=$machine;$session.Before=$snapshot;$session.Current=$snapshot;$session.Profile=$profile;$session.Profiles=$profiles;$session.MatchedCount=$matched.Count
        Write-DriverFixLog $session 'session' @{machine=$machine;before=$snapshot;summary=(Get-DriverFixScanSummary $snapshot);profile=$profile;profileErrors=$profiles.Errors;matchedCount=$matched.Count}
    }catch{
        $failure=$_.Exception.GetBaseException().Message
        Write-DriverFixLog $session 'session-init-failed' @{error=$failure}
        throw ($failure+' Nhật ký: '+$session.LogPath)
    }
    return $session
}
function Add-DriverFixAction($Session,$Action) {
    Write-DriverFixLog $Session 'action' $Action
    [void]$Session.Actions.Add($Action)
}
function Update-DriverFixSession($Session) {
    $previous=$Session.Current;$snapshot=Get-DriverFixSnapshot
    $Session.LastDelta=Compare-DriverFixSnapshot $previous $snapshot;$Session.Current=$snapshot
    Write-DriverFixLog $Session 'scan' @{snapshot=$snapshot;summary=(Get-DriverFixScanSummary $snapshot);delta=$Session.LastDelta}
    return $Session.LastDelta
}
function ConvertTo-DriverFixNativeArgument([string]$Value) {
    if($Value.IndexOf([char]0) -ge 0 -or $Value -match '[\r\n]'){throw 'Tham số chứa ký tự điều khiển.'}
    # CommandLineToArgvW / CRT quoting, including quotes and trailing backslashes.
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Invoke-DriverFixNative($Session,[ValidateSet('pnputil','expand','powercfg')][string]$Tool,[string[]]$Arguments) {
    Assert-DriverFixAdmin $Session ('native-'+$Tool)
    $system=Join-Path $env:WINDIR 'System32'
    if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){$system=Join-Path $env:WINDIR 'Sysnative'}
    $exe=Join-Path $system ($Tool+'.exe')
    Write-DriverFixLog $Session 'native-start' @{tool=$Tool;arguments=$Arguments}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$exe;$start.Arguments=(@($Arguments|ForEach-Object {ConvertTo-DriverFixNativeArgument $_}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{
        if(-not $process.Start()){throw "Không chạy được $exe"}
        $output=$process.StandardOutput.ReadToEndAsync();$errorOutput=$process.StandardError.ReadToEndAsync()
        # Cooperative cancellation is checked between native commands, never mid-install.
        $process.WaitForExit()
        $result=[pscustomobject]@{Tool=$Tool;Arguments=$Arguments;ExitCode=$process.ExitCode;Output=$output.Result;Error=$errorOutput.Result;RebootRequired=($process.ExitCode -eq 3010);Success=($process.ExitCode -in 0,3010)}
        Write-DriverFixLog $Session 'native-result' $result
        return $result
    }catch{Write-DriverFixLog $Session 'native-failed' @{tool=$Tool;arguments=$Arguments;error=$_.Exception.Message};throw}
    finally{$process.Dispose()}
}
function Test-DriverFixCancelled($Session){Test-Path -LiteralPath $Session.CancelPath}
function Invoke-DriverFixRescan($Session) {
    Assert-DriverFixAdmin $Session 'scan-devices'
    $result=Invoke-DriverFixNative $Session pnputil @('/scan-devices')
    if(-not $result.Success){throw 'pnputil /scan-devices không thành công. Xem nhật ký; nút Quét lại vẫn đọc được CIM.'}
    Start-Sleep -Seconds 3
    Update-DriverFixSession $Session
}
function Get-DriverFixInfFiles([string]$Directory,[switch]$RejectReparse) {
    $root=Get-Item -LiteralPath $Directory -ErrorAction Stop
    if(-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Chọn thư mục thật chứa driver, không dùng junction / symlink.'}
    $queue=New-Object Collections.Queue;$queue.Enqueue($root.FullName)
    while($queue.Count){
        $dir=$queue.Dequeue()
        foreach($item in Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){if($RejectReparse){throw 'Thư mục cài chứa junction / symlink. Chọn thư mục driver thật để xác định đủ phạm vi /subdirs.'};continue}
            if($item.PSIsContainer){$queue.Enqueue($item.FullName)}elseif($item.Extension -ieq '.inf'){$item}
        }
    }
}
function Get-DriverFixInfIndex([string]$Directory,[switch]$RejectReparse) {
    foreach($file in Get-DriverFixInfFiles $Directory -RejectReparse:$RejectReparse){
        # ReadAllText honors UTF-8/UTF-16 BOM. The model IDs / DriverVer are ASCII in legacy INFs.
        $text=[IO.File]::ReadAllText($file.FullName)
        $lines=@($text -split '\r?\n'|ForEach-Object {($_ -split ';',2)[0]})
        $version='0.0.0.0';$driverVer=[regex]::Match(($lines -join "`n"),'(?im)^\s*DriverVer\s*=\s*[^,\r\n]+,\s*([\d.]+)')
        if($driverVer.Success){$parsed=$null;if([version]::TryParse($driverVer.Groups[1].Value,[ref]$parsed)){$version=$parsed.ToString()}}
        [pscustomobject]@{Path=$file.FullName;Text=($lines -join "`n");Version=$version;Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
}
function Test-DriverFixInfContainsId([string]$Text,[string]$HardwareId) {
    # Boundaries prevent a common ID matching a different, SUBSYS-only model line.
    $pattern='(?i)(?<![A-Z0-9_\\&])'+[regex]::Escape($HardwareId)+'(?![A-Z0-9_\\&])'
    return [regex]::IsMatch($Text,$pattern)
}
function Get-DriverFixInfCandidate($Device,[object[]]$Index,$Profile,$Attempted) {
    $step=Get-DriverFixStep $Device $Profile
    foreach($id in $Device.HardwareIds|Sort-Object Length -Descending){
        $found=@($Index|Where-Object {
            (Test-DriverFixInfContainsId $_.Text $id) -and
            (-not $step -or -not $step.recommendedVersion -or $_.Version -like $step.recommendedVersion) -and
            (-not $Attempted.ContainsKey(($Device.InstanceId+'|'+$_.Path+'|'+$_.Hash)))
        }|Sort-Object @{Expression={[version]$_.Version};Descending=$true},Path)
        if($found.Count){return $found[0]}
    };return $null
}
function Invoke-DriverFixAddPackage($Session,[string]$InfPath,[string]$DeviceId='',[string]$ExpectedHash='',[switch]$Subdirs) {
    Assert-DriverFixAdmin $Session 'add-driver'
    if($ExpectedHash -and (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash -cne $ExpectedHash){throw 'INF đã thay đổi sau khi đối chiếu. Quét kho lại trước khi cài.'}
    $arguments=@('/add-driver',$InfPath);if($Subdirs){$arguments+='/subdirs'};$arguments+='/install'
    $result=Invoke-DriverFixNative $Session pnputil $arguments
    Add-DriverFixAction $Session ([pscustomobject]@{Kind='Install';DeviceId=$DeviceId;Source=$InfPath;Hash=$ExpectedHash;ExitCode=$result.ExitCode;Success=$result.Success;RebootRequired=$result.RebootRequired;Message='Kết quả pnputil; trạng thái thiết bị được xác nhận bằng quét sau cài.'})
    return $result
}
function Invoke-DriverFixInstallSource($Session,[string]$Source) {
    Assert-DriverFixAdmin $Session 'install-source'
    $item=Get-Item -LiteralPath $Source -ErrorAction Stop
    $temp=$null
    try{
        if($item.PSIsContainer){$directory=$item.FullName}
        elseif($item.Extension -ieq '.cab'){
            $temp=Join-Path ([IO.Path]::GetTempPath()) ('TechMaster-DriverFix-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $temp|Out-Null
            Write-DriverFixLog $Session 'cab-source' @{path=$item.FullName;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash}
            $expanded=Invoke-DriverFixNative $Session expand @('-F:*',$item.FullName,$temp)
            if(-not $expanded.Success){throw 'Không giải nén được CAB. Xem nhật ký expand.'}
            $directory=$temp
        }else{throw 'Chỉ chọn tệp .cab hoặc thư mục chứa .inf.'}
        $index=@(Get-DriverFixInfIndex $directory -RejectReparse)
        if(-not $index.Count){throw 'Không tìm thấy .inf trong nguồn đã chọn.'}
        Write-DriverFixLog $Session 'inf-manifest' @($index|Select-Object Path,Version,Hash)
        # Respect the user-verified SST branch even in manual CAB/folder installs.
        foreach($d in $Session.Current.Problems){
            $step=Get-DriverFixStep $d $Session.Profile
            if(-not $step -or -not $step.recommendedVersion){continue}
            foreach($inf in $index){
                if(@($d.HardwareIds|Where-Object {Test-DriverFixInfContainsId $inf.Text $_}).Count -and $inf.Version -notlike $step.recommendedVersion){throw ('Profile đề xuất '+$step.recommendedVersion+' cho '+$d.Name+'; nguồn đang có '+$inf.Version+'. Chọn đúng gói hoặc kiểm tra profile trước.')}
            }
        }
        if(Test-DriverFixCancelled $Session){return [pscustomobject]@{Native=$null;Delta=$null;Rounds=0;Attempts=0;Cancelled=$true}}
        $result=Invoke-DriverFixAddPackage $Session (Join-Path $directory '*.inf') -Subdirs
        $delta=Invoke-DriverFixRescan $Session
        return [pscustomobject]@{Native=$result;Delta=$delta;Rounds=1;Attempts=1;Cancelled=(Test-DriverFixCancelled $Session)}
    }finally{
        if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
function Invoke-DriverFixRepository($Session,[string]$Directory,[ValidateRange(1,4)][int]$MaxRounds=4) {
    Assert-DriverFixAdmin $Session 'install-repository'
    $index=@(Get-DriverFixInfIndex $Directory);$attempted=@{};$count=0;$round=0
    Write-DriverFixLog $Session 'repository' @{directory=$Directory;infCount=$index.Count;maxRounds=$MaxRounds}
    # Reject an empty repository early, before hardware changes.
    if(-not $index.Count){throw 'Kho không có tệp INF. Giải nén CAB trước khi dùng kho.'}
    for($round=1;$round -le $MaxRounds;$round++){
        if(Test-DriverFixCancelled $Session){break}
        $added=0
        $devices=@($Session.Current.Problems|Where-Object {$_.ErrorCode -notin 22,45,47}|Sort-Object @{Expression={$s=Get-DriverFixStep $_ $Session.Profile;if($s){[int]$s.order}else{999}}},Name)
        foreach($device in $devices){
            if(Test-DriverFixCancelled $Session){break}
            $inf=Get-DriverFixInfCandidate $device $index $Session.Profile $attempted
            if(-not $inf){continue}
            $key=$device.InstanceId+'|'+$inf.Path+'|'+$inf.Hash;$attempted[$key]=$true
            $native=Invoke-DriverFixAddPackage $Session $inf.Path $device.InstanceId $inf.Hash
            $added++;$count++
        }
        if(-not $added){break}
        $null=Invoke-DriverFixRescan $Session
    }
    [pscustomobject]@{Rounds=[Math]::Min($round,$MaxRounds);Attempts=$count;Cancelled=(Test-DriverFixCancelled $Session);Delta=(Compare-DriverFixSnapshot $Session.Before $Session.Current)}
}
function Assert-DriverFixCurrentProfile($Session) {
    if(-not $Session.Profile){throw 'Không có profile khớp duy nhất cho thao tác này.'}
    Assert-DriverFixProfile $Session.Profile
    $machine=Get-DriverFixMachine;$snapshot=Get-DriverFixSnapshot
    if(-not (Test-DriverFixProfileMatch $Session.Profile $machine $snapshot)){throw 'Máy hiện tại không còn khớp profile. Mở lại Fix Driver.'}
    return $snapshot
}
function Get-DriverFixDisableRule($Device,$Profile) {
    # Never disable SST BUS/OED, GPIO, a storage / network controller or a parent hub.
    if($Device.PnpClass -in 'HDC','SCSIAdapter','Net','System' -or $Device.Service -match '^(USBHUB|USBXHCI|iaStor|storahci)' -or @($Device.HardwareIds|Where-Object {$_ -match '^PCI\\|^ACPI\\INTC1055|^INTELAUDIO\\DSP_'}).Count){return $null}
    foreach($rule in $Profile.disable){if(Test-DriverFixHardwarePattern $Device $rule.hardwarePatterns){return $rule}};return $null
}
function Invoke-DriverFixDisable($Session,[string]$InstanceId,[string[]]$ExpectedHardwareIds) {
    Assert-DriverFixAdmin $Session 'disable-device'
    $snapshot=Assert-DriverFixCurrentProfile $Session
    $device=@($snapshot.Problems|Where-Object InstanceId -eq $InstanceId)
    if($device.Count -ne 1 -or $device[0].ErrorCode -le 0 -or $device[0].ErrorCode -eq 22 -or -not (Get-DriverFixDisableRule $device[0] $Session.Profile)){throw 'Thiết bị chưa được xác nhận đang báo lỗi hoặc không nằm trong danh sách disable an toàn của profile.'}
    if(@(Compare-Object @($device[0].HardwareIds|Sort-Object) @($ExpectedHardwareIds|Sort-Object)).Count){throw 'Hardware ID thay đổi sau khi xác nhận; quét và chọn lại.'}
    $native=Invoke-DriverFixNative $Session pnputil @('/disable-device',$InstanceId)
    Start-Sleep -Seconds 1
    $null=Update-DriverFixSession $Session
    $readback=@($Session.Current.Problems|Where-Object { $_.InstanceId -eq $InstanceId -and $_.ErrorCode -eq 22 }).Count -eq 1
    Add-DriverFixAction $Session ([pscustomobject]@{Kind='Disable';DeviceId=$InstanceId;Source='profile';ExitCode=$native.ExitCode;Success=($native.Success -and $readback);RebootRequired=$native.RebootRequired;Message=('Xác nhận Code 22: '+$readback)})
    if(-not $native.Success -or -not $readback){throw 'Chưa xác nhận được thiết bị đã disable. Xem log và Device Manager.'}
}
function Get-DriverFixPowerSpec([string]$Id) {
    switch($Id){
        'UsbSelectiveSuspendAc' {return @('2a737441-1930-4402-8d77-b2bebba308a3','48e6b7a6-50f5-4782-a5d4-53bb8f07e226')}
        'PcieLinkStateAc' {return @('501a4d13-42af-4429-9fd1-a8218c268e20','ee12f906-d277-404b-b6da-e5fa1a576df5')}
        'SleepNeverAc' {return @('238c9fa8-0aad-41ed-83f4-97be242c8f20','29f6c1db-86da-48c5-9fdb-f2b67b1f44da')}
        default {throw 'Tinh chỉnh nguồn không hỗ trợ.'}
    }
}
function Test-DriverFixWmiDeviceMatch([string]$InstanceName,[string]$InstanceId) {
    return $InstanceName -ieq $InstanceId -or $InstanceName -imatch ('^'+[regex]::Escape($InstanceId)+'_\d+$')
}
function Invoke-DriverFixPower($Session,[string[]]$ActionIds) {
    Assert-DriverFixAdmin $Session 'power-settings'
    $snapshot=Assert-DriverFixCurrentProfile $Session
    if(-not $ActionIds.Count){throw 'Chưa chọn tinh chỉnh nguồn.'}
    foreach($id in $ActionIds){if($id -notin @($Session.Profile.powerActions|ForEach-Object id)){throw 'Tinh chỉnh không được khai báo trong profile.'}}
    foreach($id in $ActionIds|Select-Object -Unique){
        try{
            if($id -eq 'UsbHidDevicePower'){
                $devices=@($snapshot.All|Where-Object {$_.InstanceId -match '^(USB|HID)\\'})
                $entries=@(Get-CimInstance -Namespace 'root/wmi' -ClassName MSPower_DeviceEnable -ErrorAction Stop);$changed=0
                foreach($entry in $entries){
                    if(-not @($devices|Where-Object {Test-DriverFixWmiDeviceMatch $entry.InstanceName $_.InstanceId}).Count){continue}
                    Write-DriverFixLog $Session 'power-before' @{action=$id;instance=$entry.InstanceName;enable=$entry.Enable}
                    $null=Set-CimInstance -InputObject $entry -Property @{Enable=$false} -ErrorAction Stop
                    $verify=@(Get-CimInstance -Namespace 'root/wmi' -ClassName MSPower_DeviceEnable -ErrorAction Stop|Where-Object InstanceName -eq $entry.InstanceName)
                    if($verify.Count -ne 1 -or $verify[0].Enable){throw ('WMI không xác nhận thay đổi: '+$entry.InstanceName)}
                    $changed++
                }
                if(-not $changed){throw 'Không có USB/HID hỗ trợ MSPower_DeviceEnable; không thay đổi thiết bị nào.'}
                $message='Đã xác nhận bỏ tắt nguồn cho '+$changed+' thiết bị USB/HID.'
            }else{
                $spec=Get-DriverFixPowerSpec $id
                $before=Invoke-DriverFixNative $Session powercfg @('/query','SCHEME_CURRENT',$spec[0],$spec[1])
                if(-not $before.Success){throw 'Không đọc được thiết lập nguồn hiện tại; không ghi thay đổi.'}
                Write-DriverFixLog $Session 'power-before' @{action=$id;query=$before.Output}
                $result=Invoke-DriverFixNative $Session powercfg @('/setacvalueindex','SCHEME_CURRENT',$spec[0],$spec[1],'0')
                if(-not $result.Success){throw 'powercfg không áp dụng được giá trị AC.'}
                $active=Invoke-DriverFixNative $Session powercfg @('/setactive','SCHEME_CURRENT')
                if(-not $active.Success){throw 'Đã ghi giá trị nhưng chưa kích hoạt lại được power scheme.'}
                $after=Invoke-DriverFixNative $Session powercfg @('/query','SCHEME_CURRENT',$spec[0],$spec[1])
                if(-not $after.Success){throw 'Đã ghi nhưng chưa đọc lại được thiết lập; xem log.'}
                $message='powercfg chấp nhận thay đổi AC. Đã ghi truy vấn trước/sau trong log; giữ nguyên DC.'
            }
            Add-DriverFixAction $Session ([pscustomobject]@{Kind='Power';DeviceId='';Source=$id;Success=$true;Message=$message})
        }catch{
            Add-DriverFixAction $Session ([pscustomobject]@{Kind='Power';DeviceId='';Source=$id;Success=$false;Message=$_.Exception.Message})
        }
    }
}
