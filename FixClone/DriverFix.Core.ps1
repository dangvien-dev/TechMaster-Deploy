# Read-only inventory, Catalog queries and declarative profiles. Windows PowerShell 5.1.
. (Join-Path $PSScriptRoot 'DriverFix.Profiles.ps1')
function Get-DriverFixHome {
    if(-not $env:LOCALAPPDATA){throw 'Không có LOCALAPPDATA để lưu dữ liệu Fix Driver.'}
    Join-Path $env:LOCALAPPDATA 'TechMaster Deploy/DriverFix'
}
function Get-DriverFixErrorDescription([int]$Code) {
    $descriptions=@{-1='Chưa đọc được mã trạng thái; kiểm tra Device Manager';0='Hoạt động';1='Cấu hình chưa đúng';3='Driver hỏng / thiếu tài nguyên';10='Thiết bị không khởi động được';12='Không đủ tài nguyên';14='Cần khởi động lại';18='Cần cài lại driver';19='Cấu hình registry lỗi';21='Đang gỡ thiết bị';22='Đã disable';24='Thiết bị không có / lỗi driver';28='Chưa có driver';29='Bị tắt bởi firmware';31='Windows không tải được driver';32='Dịch vụ driver bị tắt';37='Không khởi tạo được driver';39='Không tải được driver';40='Thông tin driver thiếu / sai';41='Không tìm thấy phần cứng';42='Thiết bị trùng lặp';43='Thiết bị báo lỗi (USB có thể lỗi descriptor)';44='Thiết bị đã dừng';45='Không kết nối';47='Đã chuẩn bị tháo an toàn';48='Driver bị Windows chặn';49='Registry vượt giới hạn';50='Không áp dụng được thuộc tính';51='Đang chờ thiết bị khác';52='Không xác minh được chữ ký driver';53='Dành riêng cho kernel debugger';54='Đang reset'}
    if($descriptions.ContainsKey($Code)){return $descriptions[$Code]}
    return 'Lỗi cấu hình thiết bị; xem Device Manager'
}
function ConvertTo-DriverFixDevice($Device) {
    $instance=[string]$Device.PNPDeviceID
    if(-not $instance){$instance=[string]$Device.DeviceID}
    if(-not $instance){throw 'Thiết bị không có InstanceId.'}
    $name=[string]$Device.Name;if(-not $name){$name=$instance}
    $code=-1;$parsed=0
    if($null -ne $Device.ConfigManagerErrorCode -and [int]::TryParse([string]$Device.ConfigManagerErrorCode,[ref]$parsed) -and $parsed -ge 0){$code=$parsed}
    [pscustomobject]@{Name=$name;ErrorCode=$code;ErrorCodeText=(Get-DriverFixCodeText $code);Description=(Get-DriverFixErrorDescription $code);HardwareIds=@($Device.HardwareID|Where-Object {$_}|Select-Object -Unique);InstanceId=$instance;Service=[string]$Device.Service;PnpClass=[string]$Device.PNPClass}
}
function Get-DriverFixSnapshot {
    # Keep healthy devices too, so disappearing hardware is not called repaired.
    $all=@(Get-CimInstance Win32_PnPEntity -OperationTimeoutSec 30 -ErrorAction Stop|ForEach-Object {ConvertTo-DriverFixDevice $_})
    if(-not $all.Count){throw 'Windows không trả về thiết bị PnP nào. Chưa thể kết luận máy không thiếu driver. Bấm Mở Device Manager để đối chiếu, rồi Quét lại.'}
    [pscustomobject]@{Time=(Get-Date).ToString('o');Source='CIM Win32_PnPEntity';All=$all;Problems=@($all|Where-Object ErrorCode -ne 0)}
}
function Get-DriverFixCodeText($Code){
    $parsed=0
    if($null -eq $Code -or -not [int]::TryParse([string]$Code,[ref]$parsed) -or $parsed -lt 0){return '?'}
    return [string]$parsed
}
function Get-DriverFixVisibleDevices($Snapshot,[bool]$ShowAll) {
    if($ShowAll){return @($Snapshot.All)}
    return @($Snapshot.Problems)
}
function Get-DriverFixScanSummary($Snapshot) {
    $all=@($Snapshot.All | Where-Object {$_})
    $healthy=@($all | Where-Object {$null -ne $_.ErrorCode -and $_.ErrorCode -eq 0}).Count
    $problems=@($all | Where-Object {$null -ne $_.ErrorCode -and $_.ErrorCode -gt 0}).Count
    $unknown=$all.Count-$healthy-$problems
    $message=if(-not $all.Count){'Chưa đọc được danh sách thiết bị. Không thể kết luận máy không thiếu driver.'}
        else{'Đã đọc '+$all.Count+' thiết bị · '+$healthy+' báo Code 0 · '+$problems+' có mã lỗi'+$(if($unknown){' · '+$unknown+' chưa đọc được trạng thái'}else{''})+'.'}
    $countsText=$message
    if($all.Count -and -not $problems -and -not $unknown){$message+=' Windows chưa báo thiết bị lỗi / thiếu driver trong lần quét này. Có thể bật Hiện tất cả thiết bị để xem danh sách đã đọc.'}
    if($unknown){$message+=' Các thiết bị có mã ? cần đối chiếu trong Device Manager; không được tính là hoạt động.'}
    [pscustomobject]@{Total=$all.Count;Healthy=$healthy;Problems=$problems;Unknown=$unknown;CountsText=$countsText;Message=$message;Kind=$(if(-not $all.Count){'Error'}elseif($unknown){'Attention'}else{'Info'})}
}
function Get-DriverFixMachine {
    $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $bios=Get-CimInstance Win32_BIOS -ErrorAction Stop
    $board=Get-CimInstance Win32_BaseBoard -ErrorAction Stop|Select-Object -First 1
    [pscustomobject]@{ComputerName=$env:COMPUTERNAME;Manufacturer=[string]$cs.Manufacturer;Model=[string]$cs.Model;Bios=[string]$bios.SMBIOSBIOSVersion;BiosVendor=[string]$bios.Manufacturer;Board=([string]$board.Manufacturer+' '+[string]$board.Product);CPU=(@(Get-CimInstance Win32_Processor -ErrorAction Stop|ForEach-Object Name)-join '; ');RamGB=[Math]::Round(([double]$cs.TotalPhysicalMemory/1GB),2);OS=([string](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption)}
}
function Compare-DriverFixSnapshot($Before,$After) {
    $old=@{};$now=@{};foreach($d in $Before.All){$old[$d.InstanceId]=$d};foreach($d in $After.All){$now[$d.InstanceId]=$d}
    [pscustomobject]@{
        Resolved=@($Before.Problems|Where-Object {$_.ErrorCode -gt 0 -and $now.ContainsKey($_.InstanceId) -and $now[$_.InstanceId].ErrorCode -eq 0})
        Disappeared=@($Before.Problems|Where-Object {-not $now.ContainsKey($_.InstanceId)})
        Disabled=@($After.Problems|Where-Object ErrorCode -eq 22)
        NewProblems=@($After.Problems|Where-Object {-not $old.ContainsKey($_.InstanceId)})
        Remaining=@($After.Problems)
    }
}
function Get-DriverFixCatalogLinks([string[]]$HardwareIds) {
    $queries=New-Object Collections.Generic.List[string]
    foreach($id in $HardwareIds){
        $s=$id.ToUpperInvariant();$q=@()
        if($s -match '^INTELAUDIO\\'){
            if($s -match '(CTLR_DEV_[0-9A-F]{4})&LINKTYPE_([0-9A-F]{2})'){$q+=($matches[1]+'&LINKTYPE_'+$matches[2])}
            # DSP_CTLR_DEV is a controller, not the endpoint DEV.
            $endpoint=[regex]::Match($s,'(?:^|&)DEV_([0-9A-F]{4})(?:&|$)')
            $vendor=[regex]::Match($s,'(?:^|&)VEN_([0-9A-F]{4})(?:&|$)')
            if($endpoint.Success){if($vendor.Success){$q+=('VEN_'+$vendor.Groups[1].Value+'&DEV_'+$endpoint.Groups[1].Value)};$q+=('DEV_'+$endpoint.Groups[1].Value)}
        }elseif($s -match '^(?:PCI|HDAUDIO)\\(?:FUNC_[0-9A-F]{2}&)?VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})'){$q+=('VEN_'+$matches[1]+'&DEV_'+$matches[2]);$q+=('DEV_'+$matches[2])}
        elseif($s -match '^(?:USB|HID)\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})'){$q+=('VID_'+$matches[1]+'&PID_'+$matches[2]);$q+=('VID_'+$matches[1])}
        elseif($s -match '^ACPI\\VEN_([^\\&]+)&DEV_([^\\&]+)'){$token=$matches[1]+$matches[2];$q+=$token;$q+=('ACPI\'+$token)}
        elseif($s -match '^ACPI\\([^\\&]+)'){$q+=$matches[1];$q+=('ACPI\'+$matches[1])}
        else{
            $parts=$s.Split([char]'\');$fallback=$s
            if($parts.Count -ge 2){$fallback=$parts[0]+'\'+$parts[1]}
            $q+=($fallback -replace '&SUBSYS_[^\\&]+.*$','' -replace '&REV_[^\\&]+.*$','')
        }
        foreach($query in $q){if($query -and -not $queries.Contains($query)){$queries.Add($query)}}
    }
    # IDs arrive specific first. Keep a small, useful list, never raw SUBSYS-only queries.
    foreach($query in @($queries|Select-Object -First 3)){
        [pscustomobject]@{Query=$query;Url=('https://www.catalog.update.microsoft.com/Search.aspx?q='+[uri]::EscapeDataString($query))}
    }
}
function Test-DriverFixHardwarePattern($Device,[string[]]$Patterns) {
    foreach($id in $Device.HardwareIds){foreach($pattern in $Patterns){if($id -like $pattern){return $true}}};return $false
}
function Assert-DriverFixProperties($Object,[string[]]$Allowed,[string]$Context) {
    foreach($property in $Object.PSObject.Properties){if($property.Name -notin $Allowed){throw "Profile: trường không hỗ trợ $Context.$($property.Name)"}}
}
function Assert-DriverFixPatterns([object[]]$Patterns,[switch]$Disable) {
    if(-not $Patterns.Count){throw 'Profile: thiếu hardwarePatterns.'}
    foreach($pattern in $Patterns){
        if($pattern -isnot [string] -or $pattern.Length -lt 8 -or $pattern -match '[\r\n?\[\]]' -or $pattern -notmatch '^[A-Za-z0-9_\\&.{}*+-]+$' -or $pattern.TrimEnd('*').Length -lt 8 -or $pattern.TrimEnd('*').Contains('*')){throw "Profile: Hardware ID pattern không hợp lệ: $pattern"}
        if($Disable -and $pattern -notmatch '^INTELAUDIO\\CTLR_DEV_[0-9A-Fa-f]{4}&LINKTYPE_[0-9A-Fa-f]{2}&DEVTYPE_[0-9A-Fa-f]{2}&VEN_[0-9A-Fa-f]{4}&DEV_[0-9A-Fa-f]{4}\*?$|^(USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}|ACPI\\[A-Za-z0-9_]{7,})(?:&[A-Za-z0-9_]+)*\*?$'){
            throw 'Profile: disable chỉ nhận Hardware ID USB/ACPI cụ thể hoặc endpoint INTELAUDIO; không nhận bus PCI / driver cha.'
        }
    }
}
function Assert-DriverFixProfile($Profile) {
    Assert-DriverFixProperties $Profile @('schema','id','name','verification','match','notes','installOrder','disable','powerActions','knownFailures') 'root'
    if($Profile.schema -ne 1 -or $Profile.id -notmatch '^[a-z0-9-]{3,80}$' -or -not $Profile.name){throw 'Profile không đúng schema 1 / thiếu id, name.'}
    Assert-DriverFixProperties $Profile.match @('anyOf') 'match'
    if(-not @($Profile.match.anyOf).Count){throw 'Profile thiếu điều kiện nhận diện.'}
    foreach($condition in $Profile.match.anyOf){
        Assert-DriverFixProperties $condition @('manufacturer','model','bios','hardwarePattern') 'match.anyOf'
        if(-not ($condition.manufacturer -or $condition.model -or $condition.bios -or $condition.hardwarePattern)){throw 'Điều kiện profile rỗng.'}
        foreach($field in 'manufacturer','model','bios'){if($condition.$field -and ([string]$condition.$field -match '[*?\[\]\r\n]' -or [string]::IsNullOrWhiteSpace($condition.$field))){throw 'Nhận diện máy phải dùng chuỗi chính xác, không wildcard.'}}
        if($condition.hardwarePattern){Assert-DriverFixPatterns @($condition.hardwarePattern)}
    }
    foreach($step in $Profile.installOrder){
        Assert-DriverFixProperties $step @('order','name','hardwarePatterns','recommendedVersion','queries','links') 'installOrder'
        Assert-DriverFixPatterns @($step.hardwarePatterns)
        if(-not $step.name -or [int]$step.order -lt 1 -or ($step.recommendedVersion -and $step.recommendedVersion -notmatch '^\d+(\.\d+){1,3}(\.\*)?$')){throw 'Bước cài profile không hợp lệ.'}
        foreach($link in $step.links){$uri=$null;if(-not [uri]::TryCreate([string]$link,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin 'https','http' -or $uri.UserInfo){throw 'Profile chỉ chấp nhận link HTTP(S), không chứa tài khoản.'}}
    }
    foreach($item in $Profile.disable){
        Assert-DriverFixProperties $item @('name','hardwarePatterns','reason') 'disable'
        Assert-DriverFixPatterns @($item.hardwarePatterns) -Disable
    }
    foreach($action in $Profile.powerActions){
        Assert-DriverFixProperties $action @('id','name') 'powerActions'
        if($action.id -notin 'UsbSelectiveSuspendAc','PcieLinkStateAc','UsbHidDevicePower','SleepNeverAc'){throw 'Profile: tinh chỉnh nguồn không hỗ trợ.'}
    }
}
function Get-DriverFixProfiles([string]$Directory) {
    if(-not $Directory){$Directory=Join-Path (Get-DriverFixHome) 'Profiles'}
    $builtin=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json
    Assert-DriverFixProfile $builtin
    New-Item -ItemType Directory -Path $Directory -Force|Out-Null
    $sample=Join-Path $Directory 'SingPC-i5-12450H.json'
    if(-not (Test-Path -LiteralPath $sample)){[IO.File]::WriteAllText($sample,(Get-DriverFixBuiltinProfileJson),[Text.UTF8Encoding]::new($false))}
    $valid=New-Object Collections.ArrayList;$errors=New-Object Collections.ArrayList;$ids=@{}
    foreach($file in Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File|Sort-Object Name){
        try{
            if($file.Length -gt 256KB){throw 'Profile quá lớn (tối đa 256 KB).'}
            $p=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json;Assert-DriverFixProfile $p
            if($ids.ContainsKey($p.id)){throw ('Trùng id profile: '+$p.id)}
            $ids[$p.id]=$true;[void]$valid.Add($p)
        }catch{[void]$errors.Add(($file.Name+': '+$_.Exception.Message))}
    }
    [pscustomobject]@{Items=@($valid);Errors=@($errors);Directory=$Directory}
}
function Test-DriverFixProfileMatch($Profile,$Machine,$Snapshot) {
    foreach($condition in $Profile.match.anyOf){
        $ok=$true
        foreach($pair in @(@('manufacturer','Manufacturer'),@('model','Model'),@('bios','Bios'))){
            if($condition.($pair[0]) -and ([string]$Machine.($pair[1])).Trim() -ine ([string]$condition.($pair[0])).Trim()){$ok=$false}
        }
        if($condition.hardwarePattern -and -not @($Snapshot.All|Where-Object {Test-DriverFixHardwarePattern $_ @($condition.hardwarePattern)}).Count){$ok=$false}
        if($ok){return $true}
    };return $false
}
function Get-DriverFixStep($Device,$Profile) {
    if($Profile){foreach($step in $Profile.installOrder|Sort-Object order){if(Test-DriverFixHardwarePattern $Device $step.hardwarePatterns){return $step}}}
    return $null
}
function Get-DriverFixProfileText($Profile) {
    if(-not $Profile){return 'Không khớp profile. Vẫn có thể quét, mở Catalog và cài CAB/INF theo Hardware ID.'}
    $lines=@($Profile.name,[string]$Profile.verification)
    foreach($step in $Profile.installOrder|Sort-Object order){$lines+=('Bước '+$step.order+': '+$step.name+' · '+$step.recommendedVersion);$links=@($step.queries|ForEach-Object {'https://www.catalog.update.microsoft.com/Search.aspx?q='+[uri]::EscapeDataString($_)});$links+=@($step.links);$lines+=@($links|Where-Object {$_}|Select-Object -Unique)}
    $lines+=@($Profile.notes);$lines+=@($Profile.knownFailures)
    return $lines -join "`r`n`r`n"
}
