# UltraViewer 6.6.133 identity lifecycle. Importing this file is read-only.
function Get-UltraIdentity {
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
    try {
        $key=$base.OpenSubKey('SOFTWARE\UltraViewer')
        $values=[ordered]@{}
        try {
            foreach($name in 'UID','PreferID') {
                $exists=$key -and $name -in $key.GetValueNames()
                if($exists -and $key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String){throw 'Kiểu dữ liệu UltraViewer khác bản đã kiểm tra; dừng thay đổi.'}
                $values[$name]=[pscustomobject]@{Exists=[bool]$exists;Value=$(if($exists){[string]$key.GetValue($name)}else{''})}
            }
        } finally {if($key){$key.Dispose()}}
        return [pscustomobject]$values
    } finally {$base.Dispose()}
}
function Set-UltraIdentity($identity,[switch]$Clear) {
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
    try {
        $key=$base.OpenSubKey('SOFTWARE\UltraViewer',$true)
        if(-not $key -and -not $Clear){$key=$base.CreateSubKey('SOFTWARE\UltraViewer')}
        if(-not $key){return}
        try {
            foreach($name in 'UID','PreferID') {
                if($Clear -or -not $identity.$name.Exists){$key.DeleteValue($name,$false)}
                else {$key.SetValue($name,[string]$identity.$name.Value,[Microsoft.Win32.RegistryValueKind]::String)}
            }
            $key.Flush()
        } finally {$key.Dispose()}
    } finally {$base.Dispose()}
}
function Get-UltraServices {
    @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {$_.PathName -match '(?i)\bUltraViewer_Service\.exe(?:"|\s|$)'} | ForEach-Object {
        if($_.StartMode -notin 'Auto','Manual','Disabled'){throw 'Không xác định được kiểu khởi động UltraViewer.'}
        [pscustomobject]@{Name=$_.Name;Startup=$(if($_.StartMode -eq 'Auto'){'Automatic'}else{$_.StartMode});WasRunning=$_.State -eq 'Running'}
    })
}
function Get-UltraVersion {
    $apps=@(foreach($path in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match '^UltraViewer(?:\s|$)'}
    })
    if(-not $apps.Count){return ''}
    return [string]$apps[0].DisplayVersion
}
function Get-UltraDeviceHash {
    $macs=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {$_.HardwareInterface -and $_.MacAddress} | ForEach-Object {$_.MacAddress.ToUpperInvariant()} | Sort-Object -Unique)
    $uuid=[string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID
    if(-not $macs.Count -and ($uuid -notmatch '^[a-fA-F0-9-]{36}$' -or $uuid -match '^(0|-|F|f)+$')){throw 'Không đọc được nhận diện phần cứng để chống reset lặp.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($macs -join ',')+'|'+$uuid.ToUpperInvariant())))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
}
function Stop-UltraRuntime($services,[switch]$Disable) {
    $current=@(Get-UltraServices)
    foreach($service in $services) {
        if($service.Name -notin $current.Name){throw 'Dịch vụ UltraViewer đã thay đổi; chưa sửa định danh.'}
        if($Disable){Set-Service -Name $service.Name -StartupType Disabled -ErrorAction Stop}
        $controller=Get-Service -Name $service.Name -ErrorAction Stop
        if($controller.Status -ne 'Stopped') {Stop-Service -Name $service.Name -ErrorAction Stop;$controller.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(15))}
    }
    Get-Process -Name UltraViewer_Desktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 500
    if(Get-Process -Name UltraViewer_Desktop,UltraViewer_Service -ErrorAction SilentlyContinue){throw 'UltraViewer vẫn chạy; dừng trước khi thay định danh.'}
}
function Start-UltraRuntime($services) {
    $current=@(Get-UltraServices)
    foreach($service in $services) {
        if($service.Name -notin $current.Name){throw 'Dịch vụ trong bản sao lưu không còn là UltraViewer.'}
        if($service.Startup -notin 'Automatic','Manual','Disabled'){throw 'Kiểu khởi động trong sao lưu không hợp lệ.'}
        Set-Service -Name $service.Name -StartupType $service.Startup -ErrorAction Stop
        if($service.WasRunning -and $service.Startup -ne 'Disabled'){Start-Service -Name $service.Name -ErrorAction Stop}
    }
}
function Protect-UltraBackup([string]$path) {
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in 'S-1-5-18','S-1-5-32-544') {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $path -AclObject $acl -ErrorAction Stop
}
function Write-UltraJson($value,[string]$path) {
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {[IO.File]::WriteAllText($temp,($value | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop}
    finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function New-UltraReceipt([string]$root,[string]$mode,$services) {
    $dir=Join-Path $root ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Protect-UltraBackup $dir
    $receipt=[pscustomobject]@{Schema=1;Mode=$mode;Device=(Get-UltraDeviceHash);Computer=$env:COMPUTERNAME;Date=(Get-Date).ToString('o');Identity=(Get-UltraIdentity);Services=@($services);Phase='BackedUp'}
    $path=Join-Path $dir 'identity.json'
    Write-UltraJson $receipt $path
    $verify=Read-UltraReceipt $path
    foreach($name in 'UID','PreferID') {if($verify.Identity.$name.Value -cne $receipt.Identity.$name.Value -or $verify.Identity.$name.Exists -ne $receipt.Identity.$name.Exists){throw 'Sao lưu định danh chưa khớp; chưa reset.'}}
    return [pscustomobject]@{Path=$path;Data=$receipt}
}
function Read-UltraReceipt([string]$path) {
    $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if($data.Schema -ne 1 -or $data.Device -notmatch '^[a-f0-9]{64}$' -or $data.Mode -notin 'Manual','Prepare','AfterClone'){throw 'Sao lưu UltraViewer không hợp lệ.'}
    foreach($name in 'UID','PreferID') {if($data.Identity.$name.Exists -isnot [bool] -or $data.Identity.$name.Value -isnot [string]){throw 'Sao lưu thiếu dữ liệu định danh.'}}
    foreach($service in @($data.Services)){if([string]::IsNullOrWhiteSpace($service.Name) -or $service.Startup -notin 'Automatic','Manual','Disabled' -or $service.WasRunning -isnot [bool]){throw 'Sao lưu thiếu cấu hình dịch vụ UltraViewer hợp lệ.'}}
    return $data
}
function Restore-UltraReceipt([string]$path) {
    $data=Read-UltraReceipt $path
    if($data.Device -cne (Get-UltraDeviceHash)){throw 'Không khôi phục định danh của máy gốc lên máy clone khác.'}
    Stop-UltraRuntime $data.Services
    try {Set-UltraIdentity $data.Identity} finally {Start-UltraRuntime $data.Services}
    $after=Get-UltraIdentity
    foreach($name in 'UID','PreferID'){if($after.$name.Exists -ne $data.Identity.$name.Exists -or $after.$name.Value -cne $data.Identity.$name.Value){throw 'Chưa xác minh được hai giá trị đã khôi phục.'}}
}
function Assert-UltraSupported {
    $version=Get-UltraVersion
    if($version -and $version -notmatch '^6\.6\.133(?:\.0)?$'){throw "UltraViewer $version chưa được kiểm tra reset tự động. Chỉ hỗ trợ bản 6.6.133 đã thử."}
    return [bool]$version
}
function Test-UltraNewIdentity($before,$after) {
    foreach($name in 'UID','PreferID') {
        if(-not $after.$name.Exists -or [string]::IsNullOrWhiteSpace($after.$name.Value)){return $false}
        if($before.$name.Exists -and $after.$name.Value -ceq $before.$name.Value){return $false}
    }
    return $true
}
function Invoke-UltraReset([string]$backupRoot) {
    if(-not (Assert-UltraSupported)){throw 'Không tìm thấy UltraViewer đã cài.'}
    $receipt=New-UltraReceipt $backupRoot 'Manual' @(Get-UltraServices)
    try {Stop-UltraRuntime $receipt.Data.Services;Set-UltraIdentity $null -Clear}
    catch {try {Set-UltraIdentity $receipt.Data.Identity} finally {Start-UltraRuntime $receipt.Data.Services};throw}
    Start-UltraRuntime $receipt.Data.Services
    $receipt.Data.Phase='AwaitingIdentity';Write-UltraJson $receipt.Data $receipt.Path
    return [pscustomobject]@{Receipt=$receipt.Path;Message='Đã reset UID / PreferID. Mở UltraViewer, đợi kết nối rồi bấm Kiểm tra ID mới.'}
}
function Prepare-UltraForClone([string]$markerPath,[string]$backupRoot) {
    if(-not (Assert-UltraSupported)){return $null}
    if(Test-Path -LiteralPath $markerPath) {
        $existing=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if($existing.Schema -eq 1 -and $existing.Phase -in 'Prepared','AwaitingIdentity'){throw 'Đã có phiên chuẩn bị UltraViewer chưa kết thúc. Khôi phục hoặc hoàn tất phiên cũ trước khi chuẩn bị lại.'}
    }
    $receipt=New-UltraReceipt $backupRoot 'Prepare' @(Get-UltraServices)
    New-Item -ItemType Directory -Path (Split-Path -Parent $markerPath) -Force | Out-Null
    try {
        Write-UltraJson ([pscustomobject]@{Schema=1;Phase='Prepared';Receipt=$receipt.Path;Device='';LocalReceipt=''}) $markerPath
        Stop-UltraRuntime $receipt.Data.Services -Disable
        Set-UltraIdentity $null -Clear
        $receipt.Data.Phase='Prepared';Write-UltraJson $receipt.Data $receipt.Path
        $after=Get-UltraIdentity
        if($after.UID.Exists -or $after.PreferID.Exists){throw 'Định danh chưa được xoá để tạo ảnh.'}
    } catch {
        $failure=$_.Exception.Message
        try {
            Restore-UltraReceipt $receipt.Path
            Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        } catch {throw ($failure+' Không tự khôi phục được UltraViewer: '+$_.Exception.Message+' Sao lưu: '+$receipt.Path)}
        throw $failure
    }
    return $receipt.Path
}
function Complete-UltraAfterClone([string]$markerPath,[string]$backupRoot) {
    if(-not (Test-Path -LiteralPath $markerPath)){return [pscustomobject]@{State='Skipped';Message='Không có lịch chuẩn bị UltraViewer; không tự reset.'}}
    $marker=Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($marker.Schema -ne 1 -or $marker.Phase -notin 'Prepared','AwaitingIdentity','Complete'){throw 'Lịch UltraViewer không hợp lệ.'}
    $device=Get-UltraDeviceHash
    if($marker.Phase -eq 'Complete'){return [pscustomobject]@{State='Complete';Message='Lần chuẩn bị UltraViewer này đã hoàn tất; giữ nguyên ID. Nếu tạo ảnh mới, chạy lại bước chuẩn bị Sysprep.'}}
    $master=Read-UltraReceipt $marker.Receipt
    if(-not (Assert-UltraSupported)){throw 'UltraViewer trong lịch chuẩn bị không còn được cài.'}
    if($marker.Phase -eq 'AwaitingIdentity') {
        $local=Read-UltraReceipt $marker.LocalReceipt
    } else {
        $receipt=New-UltraReceipt $backupRoot 'AfterClone' $master.Services
        Stop-UltraRuntime $master.Services -Disable
        Set-UltraIdentity $null -Clear
        $marker.Device=$device;$marker.LocalReceipt=$receipt.Path;$marker.Phase='AwaitingIdentity'
        Write-UltraJson $marker $markerPath
        $local=$receipt.Data
    }
    Start-UltraRuntime $master.Services
    $after=Get-UltraIdentity
    if(Test-UltraNewIdentity $master.Identity $after) {
        $marker.Phase='Complete';Write-UltraJson $marker $markerPath
        return [pscustomobject]@{State='Complete';Message='UltraViewer đã có định danh mới cho máy này.'}
    }
    return [pscustomobject]@{State='Pending';Message='Đã bỏ định danh từ ảnh gốc. Mở UltraViewer, đợi kết nối rồi Kiểm tra ID mới; không reset lặp.'}
}
