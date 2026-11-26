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
    [pscustomobject]@{Name=$name;ErrorCode=$code;ErrorCodeText=(Get-DriverFixCodeText $code);Description=(Get-DriverFixErrorDescription $code);HardwareIds=@($Device.HardwareID|Where-Object {$_}|Select-Object -Unique);CompatibleIds=@($Device.CompatibleID|Where-Object {$_}|Select-Object -Unique);InstanceId=$instance;Service=[string]$Device.Service;PnpClass=[string]$Device.PNPClass}
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
        [pscustomobject]@{Kind='Catalog';Vendor='';Query=$query;Label=$query;Url=('https://www.catalog.update.microsoft.com/Search.aspx?q='+[uri]::EscapeDataString($query))}
    }
}
# Máy in / MFP: Catalog hiếm khi lập chỉ mục driver theo USB VID/PID (INF khai báo USBPRINT\... hoặc tên model), nên link VID/PID
# thường trống. Với thiết bị nhận ra là máy in / MFP, mở trang hỗ trợ của hãng theo VID. Thêm một dòng để hỗ trợ hãng khác.
# Support: trang hỗ trợ chính thức (chỉ host này được mở thêm ngoài Catalog / Google). Site: tên miền dùng cho tìm kiếm site:.
# PrinterOnly=$false: VID còn dùng cho webcam, bàn phím, điện thoại... nên cần dấu hiệu máy in (class / ID / tên) mới gợi ý hãng.
function Get-DriverFixPrinterVendors {
    @(
        [pscustomobject]@{Vid='04A9';Name='Canon';Support='https://vn.canon/vi/support';Site='vn.canon';PrinterOnly=$false}
        [pscustomobject]@{Vid='03F0';Name='HP';Support='https://support.hp.com/us-en/drivers';Site='support.hp.com';PrinterOnly=$false}
        [pscustomobject]@{Vid='04B8';Name='Epson';Support='https://www.epson.com.vn/';Site='epson.com.vn';PrinterOnly=$false}
        [pscustomobject]@{Vid='04F9';Name='Brother';Support='https://support.brother.com/g/b/productsearch.aspx?c=vn&lang=en';Site='support.brother.com';PrinterOnly=$true}
        [pscustomobject]@{Vid='0482';Name='Kyocera';Support='https://www.kyoceradocumentsolutions.com/';Site='kyoceradocumentsolutions.com';PrinterOnly=$false}
        [pscustomobject]@{Vid='05CA';Name='Ricoh';Support='https://www.ricoh.com.vn/';Site='ricoh.com.vn';PrinterOnly=$false}
        [pscustomobject]@{Vid='0924';Name='Xerox';Support='https://www.support.xerox.com/';Site='support.xerox.com';PrinterOnly=$true}
        [pscustomobject]@{Vid='043D';Name='Lexmark';Support='https://support.lexmark.com/';Site='support.lexmark.com';PrinterOnly=$true}
        [pscustomobject]@{Vid='06BC';Name='OKI';Support='https://www.oki.com/';Site='oki.com';PrinterOnly=$true}
    )
}
function Get-DriverFixUsbVid($Device) {
    foreach($id in (@($Device.HardwareIds)+@([string]$Device.InstanceId))){
        $m=[regex]::Match(([string]$id).ToUpperInvariant(),'^(?:USB|HID)\\VID_([0-9A-F]{4})')
        if($m.Success){return $m.Groups[1].Value}
    }
    return ''
}
function Test-DriverFixPrinterDevice($Device) {
    if(-not $Device){return $false}
    if([string]$Device.PnpClass -in 'Printer','PrintQueue'){return $true}
    foreach($id in (@($Device.HardwareIds)+@($Device.CompatibleIds))){
        if($id -and ([string]$id).ToUpperInvariant() -match '^(?:USBPRINT|WSDPRINT|PRINTENUM|LPTENUM|DOT4PRT)\\|^USB\\CLASS_07(?:&|$)'){return $true}
    }
    # Canon MF240 Code 28 không có class và ID USB chỉ là VID/PID, nên cần thêm nhận diện theo tên.
    return ([string]$Device.Name) -match '(?i)\b(?:printers?|mfp|mfc|scanner|laserjet|deskjet|officejet|inkjet|pixma|imageclass|i-sensys|ufr\s?ii|ecotank|workforce|ecosys|taskalfa|bizhub|phaser|versalink|altalink|workcentre)\b|\b(?:lbp|mf)\d{3,4}'
}
function Get-DriverFixPrinterVendor($Device) {
    $vid=Get-DriverFixUsbVid $Device
    if(-not $vid){return $null}
    $vendor=@(Get-DriverFixPrinterVendors|Where-Object Vid -eq $vid)|Select-Object -First 1
    if(-not $vendor){return $null}
    if($vendor.PrinterOnly -or (Test-DriverFixPrinterDevice $Device)){return $vendor}
    return $null
}
function Get-DriverFixPrinterModel($Device) {
    $name=([string]$Device.Name -replace '[\x00-\x1F\x7F"]',' ' -replace '\s+',' ').Trim()
    # Tên rỗng, bằng InstanceId hoặc chung chung (USB Printing Support...) không giúp tìm đúng model.
    if(-not $name -or $name -ceq [string]$Device.InstanceId -or $name.Contains('\') -or $name -match '(?i)^(?:USB |Unknown |Generic |Microsoft |WSD )'){return ''}
    if($name.Length -gt 80){$name=$name.Substring(0,80).Trim()}
    return $name
}
function Get-DriverFixVendorLinks($Device,$Vendor) {
    $model=Get-DriverFixPrinterModel $Device
    if($model){
        $subject=if($model -match ('(?i)^'+[regex]::Escape($Vendor.Name))){$model}else{$Vendor.Name+' '+$model}
        $search=$subject+' driver site:'+$Vendor.Site
        [pscustomobject]@{Kind='Vendor';Vendor=$Vendor.Name;Query=$search;Label=('Tìm driver "'+$model+'" trên '+$Vendor.Site);Url=('https://www.google.com/search?hl=vi&q='+[uri]::EscapeDataString($search))}
    }
    [pscustomobject]@{Kind='Vendor';Vendor=$Vendor.Name;Query=$Vendor.Support;Label=('Trang hỗ trợ '+$Vendor.Name+' ('+([uri]$Vendor.Support).Host+')');Url=$Vendor.Support}
}
# Link mở cho một thiết bị: máy in / MFP của hãng trong bảng → trang hãng; còn lại → Microsoft Update Catalog theo Hardware ID.
function Get-DriverFixDriverLinks($Device) {
    $vendor=Get-DriverFixPrinterVendor $Device
    if($vendor){return @(Get-DriverFixVendorLinks $Device $vendor)}
    return @(Get-DriverFixCatalogLinks @($Device.HardwareIds))
}
# Chỉ mở link do chương trình tạo: Catalog, tìm kiếm Google theo site:, hoặc host hỗ trợ trong bảng hãng; luôn HTTPS, không tài khoản / cổng lạ.
function Test-DriverFixAllowedLink([string]$Url) {
    $uri=$null
    if(-not [uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.IsDefaultPort){return $false}
    $linkHost=$uri.Host.ToLowerInvariant()
    if($linkHost -eq 'www.catalog.update.microsoft.com'){return $uri.AbsolutePath -eq '/Search.aspx'}
    if($linkHost -eq 'www.google.com'){return $uri.AbsolutePath -eq '/search'}
    foreach($vendor in Get-DriverFixPrinterVendors){if($linkHost -eq ([uri]$vendor.Support).Host.ToLowerInvariant()){return $true}}
    return $false
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
