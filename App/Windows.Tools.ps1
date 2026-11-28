# Current-user Explorer preferences and Windows' own system-cleanup UI.
function Get-DeployWindowsToolsLog([string]$Name) {
    $dir=Join-Path $env:LOCALAPPDATA 'TechMaster Deploy/Windows Tools'
    New-Item -ItemType Directory -Path $dir -Force|Out-Null
    Join-Path $dir ($Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.jsonl')
}
function Write-DeployWindowsToolsLog([string]$Path,[string]$Event,$Data) {
    [IO.File]::AppendAllText($Path,((@{Time=(Get-Date).ToString('o');Event=$Event;Data=$Data}|ConvertTo-Json -Depth 8 -Compress)+"`r`n"),[Text.UTF8Encoding]::new($false))
}
function Get-DeployWindowsToolsIdentity {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $windows=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $revision=$null;$parsed=0
    if([int]::TryParse([string]$windows.UBR,[ref]$parsed) -and $parsed -ge 0){$revision=$parsed}
    [pscustomobject]@{Build=[int]$windows.CurrentBuildNumber;Ubr=$revision;Sid=$identity.User.Value;User=$identity.Name;Session=[Diagnostics.Process]::GetCurrentProcess().SessionId}
}
# Build is a warning threshold, never proof that a staged Explorer rollout is active.
function Get-DeployExplorerMenuCompatibility($Identity) {
    $build=[int]$Identity.Build;$ubr=$null;$parsed=0
    if($null -ne $Identity.Ubr -and [int]::TryParse([string]$Identity.Ubr,[ref]$parsed) -and $parsed -ge 0){$ubr=$parsed}
    $mayIgnore=$build -gt 26200 -or ($build -eq 26200 -and ($null -eq $ubr -or $ubr -ge 9974))
    $label=[string]$build
    if($null -ne $ubr){$label+='.'+[string]$ubr}else{$label+=' (chưa đọc được UBR)'}
    $guidance=if($mayIgnore){'Windows bản 11/2026 trở đi có thể bỏ qua tuỳ chỉnh này. Giữ Shift + chuột phải để mở menu đầy đủ; nếu Customize menu có Arrange primary actions inline, có thể bật lựa chọn đó. Menu mới được triển khai dần, nên cùng build vẫn có thể khác nhau.'}else{''}
    [pscustomobject]@{Build=$build;Ubr=$ubr;BuildLabel=$label;MayIgnore=$mayIgnore;Guidance=$guidance}
}
function New-DeployExplorerMenuResult($Identity,[string]$Mode,[bool]$Changed,[string]$LogPath) {
    $compatibility=Get-DeployExplorerMenuCompatibility $Identity
    $message=if($Changed){'Đã lưu cấu hình '+$(if($Mode -eq 'Legacy'){'menu truyền thống kiểu Windows 10'}else{'menu mặc định Windows 11'})+' cho '+$Identity.User+'.'}else{'Cấu hình đã ở lựa chọn này; không ghi lại.'}
    $message+=' Windows '+$compatibility.BuildLabel+'. Chưa xác nhận giao diện menu đã đổi.'
    if($Mode -eq 'Legacy' -and $compatibility.MayIgnore){$message+=' '+$compatibility.Guidance}
    else{$message+=' Khởi động lại Explorer hoặc đăng xuất / đăng nhập lại để kiểm tra.'}
    Write-DeployWindowsToolsLog $LogPath 'menu-display-unverified' @{Mode=$Mode;Compatibility=$compatibility;DisplayVerified=$false;RegistryChanged=$Changed}
    [pscustomobject]@{Changed=$Changed;Message=$message;Log=$LogPath;Compatibility=$compatibility;DisplayVerified=$false;Mode=$Mode}
}
function Get-DeployExplorerMenuRestartMessage($Result) {
    $message='Đã yêu cầu khởi động lại Explorer. Chưa xác nhận giao diện menu đã đổi; thử lại menu chuột phải.'
    # Keep the compatibility warning visible after the restart action completes.
    if($Result.Mode -eq 'Legacy' -and $Result.Compatibility.MayIgnore){$message+=' '+$Result.Compatibility.Guidance}
    else{$message+=' Nếu chưa đổi, có thể cần đăng xuất / đăng nhập lại.'}
    $message+=' Nhật ký: '+$Result.Log
    return $message
}
function Open-DeployMenuRegistry {
    $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
    [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
}
function Get-DeployExplorerMenuSnapshot {
    $root=Open-DeployMenuRegistry;$key=$null
    try{
        $key=$root.OpenSubKey('Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')
        $present=$false;$value=$null;$kind=''
        if($key){$present='' -in @($key.GetValueNames());if($present){$value=$key.GetValue('',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);$kind=$key.GetValueKind('').ToString()}}
        [pscustomobject]@{KeyExists=($null -ne $key);DefaultPresent=$present;Value=$value;Kind=$kind}
    }finally{if($key){$key.Dispose()};$root.Dispose()}
}
function Write-DeployExplorerMenuOverride([bool]$Legacy) {
    $path='Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
    $root=Open-DeployMenuRegistry;$key=$null;$parent=$null
    try{
        if($Legacy){
            $key=$root.CreateSubKey($path+'\InprocServer32');$key.SetValue('','',[Microsoft.Win32.RegistryValueKind]::String)
        }else{
            $key=$root.OpenSubKey($path+'\InprocServer32',$true)
            if($key){
                $key.DeleteValue('',$false)
                $empty=($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0);$key.Dispose();$key=$null
                if($empty){$root.DeleteSubKey($path+'\InprocServer32',$false)}
                $parent=$root.OpenSubKey($path)
                if($parent){$parentEmpty=($parent.ValueCount -eq 0 -and $parent.SubKeyCount -eq 0);$parent.Dispose();$parent=$null;if($parentEmpty){$root.DeleteSubKey($path,$false)}}
            }
        }
    }finally{if($key){$key.Dispose()};if($parent){$parent.Dispose()};$root.Dispose()}
}
function Set-DeployExplorerMenu([ValidateSet('Legacy','Default')][string]$Mode,[string]$LogPath) {
    $who=Get-DeployWindowsToolsIdentity
    Write-DeployWindowsToolsLog $LogPath 'request' @{Mode=$Mode;Identity=$who}
    if($who.Build -lt 22000){return [pscustomobject]@{Changed=$false;Message='Máy đang dùng Windows 10 hoặc bản Windows chưa có menu Windows 11; không thay đổi registry.';Log=$LogPath}}
    $before=Get-DeployExplorerMenuSnapshot
    Write-DeployWindowsToolsLog $LogPath 'backup-before' $before
    if($before.DefaultPresent -and ($before.Kind -ne 'String' -or [string]$before.Value -ne '')){throw 'Nhánh menu đang có cấu hình khác. Đã lưu trạng thái, chưa ghi đè cấu hình này.'}
    $wantLegacy=$Mode -eq 'Legacy';$wasLegacy=$before.DefaultPresent -and $before.Kind -eq 'String' -and [string]$before.Value -eq ''
    if($wantLegacy -eq $wasLegacy){return (New-DeployExplorerMenuResult $who $Mode $false $LogPath)}
    try{
        Write-DeployExplorerMenuOverride $wantLegacy
        $after=Get-DeployExplorerMenuSnapshot
        $isLegacy=$after.DefaultPresent -and $after.Kind -eq 'String' -and [string]$after.Value -eq ''
        if($isLegacy -ne $wantLegacy){throw 'Chưa xác nhận được cấu hình sau thay đổi.'}
        Write-DeployWindowsToolsLog $LogPath 'verified-after' $after
        New-DeployExplorerMenuResult $who $Mode $true $LogPath
    }catch{Write-DeployWindowsToolsLog $LogPath 'failed' $_.Exception.Message;throw}
}
function Restart-DeployCurrentExplorer([string]$LogPath) {
    $who=Get-DeployWindowsToolsIdentity
    $items=@(Get-CimInstance Win32_Process -Filter ("Name='explorer.exe' AND SessionId="+$who.Session) -ErrorAction Stop)
    $ids=@(foreach($item in $items){$owner=Invoke-CimMethod -InputObject $item -MethodName GetOwnerSid -ErrorAction Stop;if($owner.ReturnValue -eq 0 -and $owner.Sid -eq $who.Sid){[int]$item.ProcessId}})
    if(-not $ids.Count){throw 'Không tìm thấy Explorer của cùng tài khoản và phiên đăng nhập. Hãy đăng xuất / đăng nhập lại tài khoản cần áp dụng.'}
    Write-DeployWindowsToolsLog $LogPath 'restart-explorer' @{Identity=$who;ProcessIds=$ids}
    foreach($id in $ids){Stop-Process -Id $id -ErrorAction Stop}
    Start-Sleep -Seconds 2
    $running=@(Get-CimInstance Win32_Process -Filter ("Name='explorer.exe' AND SessionId="+$who.Session) -ErrorAction Stop)
    if(-not $running.Count){Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ErrorAction Stop|Out-Null}
    Write-DeployWindowsToolsLog $LogPath 'restart-requested' 'Only the current user and session were targeted.'
}
function Get-DeployDirectoryEntryState([string]$Path) {
    # Includes hidden/system entries that Explorer hides by default.
    try{
        $items=[IO.Directory]::EnumerateFileSystemEntries($Path).GetEnumerator()
        try{if($items.MoveNext()){'HasItems'}else{'Empty'}}finally{$items.Dispose()}
    }catch{'Unknown'}
}
function Remove-DeployEmptyWindowsOld([string]$Drive,[string]$Path,[string]$LogPath) {
    # rd without /s refuses a non-empty directory, so data can never be removed here.
    $cmd=Join-Path $env:WINDIR 'System32/cmd.exe'
    $arguments='/d /c rd "'+$Drive+'\Windows.old"'
    Write-DeployWindowsToolsLog $LogPath 'remove-empty-windows-old' @{Path=$cmd;Arguments=$arguments}
    $process=Start-Process -FilePath $cmd -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    try{$exit=$process.ExitCode}finally{$process.Dispose()}
    $remaining=Test-Path -LiteralPath $Path -PathType Container
    Write-DeployWindowsToolsLog $LogPath 'remove-empty-closed' @{ExitCode=$exit;Remaining=$remaining}
    [pscustomobject]@{Remaining=$remaining;Missing=$false;Empty=$true;Message=$(if($remaining){'Windows.old rỗng nhưng chưa xoá được (có thể vừa có tệp mới hoặc bị chặn quyền). Không có dữ liệu bị xoá.'}else{'Đã xoá thư mục Windows.old rỗng (không chứa tệp nào, kể cả tệp ẩn).'});Log=$LogPath}
}
function Invoke-DeployWindowsOldCleanup([string]$LogPath) {
    $drive=$env:SystemDrive
    if($drive -notmatch '^[A-Za-z]:$'){throw 'Không xác định được ổ cài Windows.'}
    $path=Join-Path ($drive+'\') 'Windows.old'
    Write-DeployWindowsToolsLog $LogPath 'check-windows-old' @{Path=$path}
    if(-not (Test-Path -LiteralPath $path -PathType Container)){return [pscustomobject]@{Remaining=$false;Missing=$true;Message=('Không còn thư mục '+$path+'.');Log=$LogPath}}
    $folder=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($folder.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Windows.old đang là liên kết thư mục; chưa thực hiện dọn.'}
    $state=Get-DeployDirectoryEntryState $path
    Write-DeployWindowsToolsLog $LogPath 'entry-state' @{State=$state}
    # Disk Cleanup does not list an empty Windows.old, so remove the empty shell directly.
    if($state -eq 'Empty'){return (Remove-DeployEmptyWindowsOld $drive $path $LogPath)}
    $exe=Join-Path $env:WINDIR 'System32/cleanmgr.exe'
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Bản Windows này không có Disk Cleanup. Dùng Cài đặt → Lưu trữ → Tệp tạm thời.'}
    Write-DeployWindowsToolsLog $LogPath 'launch-cleanmgr' @{Path=$exe;Arguments=('/d '+$drive)}
    $process=Start-Process -FilePath $exe -ArgumentList ('/d '+$drive) -Verb RunAs -Wait -PassThru -ErrorAction Stop
    try{$exit=$process.ExitCode}finally{$process.Dispose()}
    $remaining=Test-Path -LiteralPath $path -PathType Container
    Write-DeployWindowsToolsLog $LogPath 'cleanmgr-closed' @{ExitCode=$exit;Remaining=$remaining}
    # Disk Cleanup can leave an empty Windows.old behind after removing its content.
    if($remaining -and (Get-DeployDirectoryEntryState $path) -eq 'Empty'){return (Remove-DeployEmptyWindowsOld $drive $path $LogPath)}
    [pscustomobject]@{Remaining=$remaining;Missing=$false;Empty=$false;Message=$(if($remaining){'Windows.old vẫn còn và còn chứa tệp. Trong Disk Cleanup chọn Clean up system files / Dọn tệp hệ thống → Previous Windows installation(s). Nếu Windows không liệt kê mục này, công cụ chưa nhận diện thư mục là bản cài trước.'}else{'Đã kiểm tra: Windows.old không còn trên ổ cài Windows.'});Log=$LogPath}
}
