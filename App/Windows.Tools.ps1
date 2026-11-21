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
    [pscustomobject]@{Build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber;Sid=$identity.User.Value;User=$identity.Name;Session=[Diagnostics.Process]::GetCurrentProcess().SessionId}
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
    if($wantLegacy -eq $wasLegacy){return [pscustomobject]@{Changed=$false;Message='Cấu hình registry đã ở lựa chọn này. Nếu menu chưa đổi, khởi động lại Explorer hoặc đăng xuất / đăng nhập lại.';Log=$LogPath}}
    try{
        Write-DeployExplorerMenuOverride $wantLegacy
        $after=Get-DeployExplorerMenuSnapshot
        $isLegacy=$after.DefaultPresent -and $after.Kind -eq 'String' -and [string]$after.Value -eq ''
        if($isLegacy -ne $wantLegacy){throw 'Chưa xác nhận được cấu hình sau thay đổi.'}
        Write-DeployWindowsToolsLog $LogPath 'verified-after' $after
        [pscustomobject]@{Changed=$true;Message=('Đã lưu lựa chọn '+$(if($wantLegacy){'menu truyền thống kiểu Windows 10'}else{'menu mặc định Windows 11'})+' cho '+$who.User+'. Áp dụng sau khi khởi động lại Explorer hoặc đăng nhập lại. Một số bản Windows mới có thể không áp dụng tuỳ chỉnh menu truyền thống.');Log=$LogPath}
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
function Invoke-DeployWindowsOldCleanup([string]$LogPath) {
    $drive=$env:SystemDrive
    if($drive -notmatch '^[A-Za-z]:$'){throw 'Không xác định được ổ cài Windows.'}
    $path=Join-Path ($drive+'\') 'Windows.old'
    Write-DeployWindowsToolsLog $LogPath 'check-windows-old' @{Path=$path}
    if(-not (Test-Path -LiteralPath $path -PathType Container)){return [pscustomobject]@{Remaining=$false;Missing=$true;Message=('Không còn thư mục '+$path+'.');Log=$LogPath}}
    $folder=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($folder.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Windows.old đang là liên kết thư mục; chưa thực hiện dọn.'}
    $exe=Join-Path $env:WINDIR 'System32/cleanmgr.exe'
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Bản Windows này không có Disk Cleanup. Dùng Cài đặt → Lưu trữ → Tệp tạm thời.'}
    Write-DeployWindowsToolsLog $LogPath 'launch-cleanmgr' @{Path=$exe;Arguments=('/d '+$drive)}
    $process=Start-Process -FilePath $exe -ArgumentList ('/d '+$drive) -Verb RunAs -Wait -PassThru -ErrorAction Stop
    try{$exit=$process.ExitCode}finally{$process.Dispose()}
    $remaining=Test-Path -LiteralPath $path -PathType Container
    Write-DeployWindowsToolsLog $LogPath 'cleanmgr-closed' @{ExitCode=$exit;Remaining=$remaining}
    [pscustomobject]@{Remaining=$remaining;Missing=$false;Message=$(if($remaining){'Windows.old vẫn còn. Trong Disk Cleanup chọn Clean up system files / Dọn tệp hệ thống → Previous Windows installation(s). Nếu Windows không liệt kê mục này, công cụ chưa nhận diện thư mục là bản cài trước.'}else{'Đã kiểm tra: Windows.old không còn trên ổ cài Windows.'});Log=$LogPath}
}
