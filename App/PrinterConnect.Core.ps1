# Network printers without switching off Windows printing protections.
# - A printer with its own LAN port is added on a Standard TCP/IP port: no spooler RPC between computers.
# - A printer shared from another computer is connected with an account that has a password (saved once in
#   Credential Manager) and a driver installed by an administrator beforehand, so Point and Print never has
#   to download one for a standard user.
# - The only registry change offered is the client RPC transport for printing (named pipes instead of TCP),
#   for Windows 11 22H2+ connecting to older print servers; it keeps authentication and is undone with a backup.
# Settings that remove protections (RpcAuthnLevelPrivacyEnabled=0, RestrictDriverInstallationToAdministrators=0,
# insecure guest logons, blank passwords) are never written.
. (Join-Path $PSScriptRoot 'Windows.Tools.ps1')
. (Join-Path $PSScriptRoot 'LanConnect.Core.ps1')
. (Join-Path $PSScriptRoot 'Defaults.Core.ps1')
$script:DeployPrinterRpcKey='SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'
$script:DeployPrinterRpcValue='RpcUseNamedPipeProtocol'
$script:DeployPrinterClassGuid='{4d36e979-e325-11ce-bfc1-08002be10318}'

# ---------- Input ----------
function ConvertFrom-DeployPrinterAddress([string]$Value) {
    $address=([string]$Value).Trim()
    if($address -match '^(?i)(https?|ipp)://'){throw 'Chỉ nhập IP hoặc tên máy in, không kèm http:// (ví dụ 192.168.1.50).'}
    if(-not $address){throw 'Nhập địa chỉ IP của máy in (xem trên màn hình máy in hoặc trang cấu hình mạng in ra từ máy).'}
    if($address -match '^\d{1,3}(\.\d{1,3}){3}$'){
        foreach($part in $address.Split('.')){if([int]$part -gt 255){throw ('Địa chỉ IP không hợp lệ: '+$address)}}
        if($address -match '^(0|127|255)\.' -or $address -eq '0.0.0.0'){throw ('Địa chỉ IP không dùng được cho máy in: '+$address)}
        return $address
    }
    if($address -match '^[\d.]+$'){throw ('Địa chỉ IP không hợp lệ: '+$address+'. IP có dạng 192.168.1.50.')}
    if($address.Length -gt 253 -or $address -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$'){throw ('Địa chỉ không hợp lệ: '+$address+'. Nhập IP (192.168.1.50) hoặc tên máy in trong mạng.')}
    return $address
}
function ConvertFrom-DeployPrinterPortNumber($Value) {
    $text=([string]$Value).Trim()
    if(-not $text){return 9100}
    $number=0
    if(-not [int]::TryParse($text,[ref]$number) -or $number -lt 1 -or $number -gt 65535){throw ('Cổng không hợp lệ: '+$text+'. Máy in mạng thường dùng 9100 (RAW).')}
    return $number
}
function Assert-DeployPrinterName([string]$Name) {
    $value=([string]$Name).Trim()
    if(-not $value){throw 'Nhập tên máy in hiển thị trên máy này.'}
    if($value.Length -gt 200 -or $value -match '[\\,!]' -or $value -match '[\x00-\x1f]'){throw 'Tên máy in không được chứa \ , ! và tối đa 200 ký tự.'}
    return $value
}
function ConvertFrom-DeployPrinterShare([string]$Path) {
    $target=ConvertFrom-DeployShareUnc $Path
    if($target.Unc -cne ('\\'+$target.Server+'\'+$target.Share)){throw 'Nhập đường dẫn máy in dạng \\TÊN-MÁY\TênMáyIn, không có thư mục con.'}
    [pscustomobject]@{Server=$target.Server;Share=$target.Share;Path=$target.Unc}
}
function Get-DeployPrinterPortName([string]$Address,[int]$Port) {
    if($Port -eq 9100){return ('IP_'+$Address)}
    return ('IP_'+$Address+'_'+$Port)
}

# ---------- Thin wrappers (mocked in tests) ----------
function Test-DeployPrinterAdmin {([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function Test-DeployTcpPort([string]$HostName,[int]$Port,[int]$TimeoutMs=1500) {
    $client=New-Object Net.Sockets.TcpClient
    try{
        $async=$client.BeginConnect($HostName,$Port,$null,$null)
        if(-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)){return $false}
        $client.EndConnect($async);return $true
    }catch{return $false}finally{$client.Close()}
}
function Test-DeployPing([string]$HostName) {
    $ping=New-Object Net.NetworkInformation.Ping
    try{return ($ping.Send($HostName,1000).Status -eq 'Success')}catch{return $false}finally{$ping.Dispose()}
}
function Test-DeployServerLogon([string]$Server,[string]$User,[Security.SecureString]$Password) {
    Initialize-DeployConnectNative
    [int][TechMaster.LanConnectNative]::TestConnection(('\\'+$Server+'\IPC$'),$User,$Password,0)
}
function Get-DeploySpoolerState {try{[string](Get-Service -Name Spooler -ErrorAction Stop).Status}catch{''}}
function Restart-DeployPrintSpooler {Restart-Service -Name Spooler -Force -ErrorAction Stop}
function Get-DeployPrinterArchitecture {
    $arch=[string]$env:PROCESSOR_ARCHITEW6432
    if(-not $arch){$arch=[string]$env:PROCESSOR_ARCHITECTURE}
    switch -Regex ($arch){'ARM64'{return 'arm64'}'AMD64|IA64'{return 'amd64'}default{return 'x86'}}
}
function Get-DeployPrinterEnvironment([string]$Architecture) {
    switch($Architecture){'arm64'{'Windows ARM64'}'amd64'{'Windows x64'}default{'Windows NT x86'}}
}
function Get-DeployInstalledPrinterDrivers {
    $environment=Get-DeployPrinterEnvironment (Get-DeployPrinterArchitecture)
    @(Get-PrinterDriver -ErrorAction Stop | Where-Object {-not [string]$_.PrinterEnvironment -or [string]$_.PrinterEnvironment -eq $environment} | ForEach-Object {[string]$_.Name} | Sort-Object -Unique)
}
function Get-DeployRemotePrinterDriver([string]$Server,[string]$Share) {
    $found=@(Get-Printer -ComputerName $Server -ErrorAction Stop | Where-Object {[string]$_.ShareName -ieq $Share -or [string]$_.Name -ieq $Share})
    if($found.Count){return [string]$found[0].DriverName}
    return ''
}
function Invoke-DeployPnputil([string[]]$Arguments) {
    $system=Join-Path $env:WINDIR 'System32'
    if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){$system=Join-Path $env:WINDIR 'Sysnative'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $system 'pnputil.exe'
    $start.Arguments=(@($Arguments | ForEach-Object {'"'+([string]$_).Replace('"','')+'"'}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{
        if(-not $process.Start()){throw 'Không chạy được pnputil.'}
        $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ExitCode=$process.ExitCode;Output=([string]$output.Result+[string]$errors.Result).Trim()}
    }finally{$process.Dispose()}
}
function Invoke-DeployPrinterTestPage([string]$Name) {
    $escaped=$Name.Replace('\','\\').Replace("'","\'")
    $printer=@(Get-CimInstance Win32_Printer -Filter ("Name='"+$escaped+"'") -ErrorAction Stop)
    if($printer.Count -ne 1){throw 'Không tìm thấy hàng đợi để in trang thử.'}
    $result=Invoke-CimMethod -InputObject $printer[0] -MethodName PrintTestPage -ErrorAction Stop
    if($null -ne $result.ReturnValue -and [int]$result.ReturnValue -ne 0){throw ('Windows báo lỗi khi gửi trang thử (mã '+$result.ReturnValue+').')}
}
function Get-DeployPrinterRpcBackupPath {
    $dir=Join-Path $env:LOCALAPPDATA 'TechMaster Deploy\Windows Tools'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Join-Path $dir 'PrinterRpc-backup.json'
}
# 64-bit view, so a 32-bit host process still reads and writes the key the 64-bit spooler uses.
function Open-DeployPrinterPolicyRoot {
    $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
    [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
}
function Get-DeployPrinterRpcSetting {
    $root=Open-DeployPrinterPolicyRoot
    $key=$null
    try{$key=$root.OpenSubKey($script:DeployPrinterRpcKey)}finally{if(-not $key){$root.Dispose()}}
    if(-not $key){return [pscustomobject]@{Present=$false;Value=$null;Kind=''}}
    try{
        $present=$script:DeployPrinterRpcValue -in @($key.GetValueNames())
        [pscustomobject]@{Present=[bool]$present;Value=$(if($present){$key.GetValue($script:DeployPrinterRpcValue)}else{$null});Kind=$(if($present){[string]$key.GetValueKind($script:DeployPrinterRpcValue)}else{''})}
    }finally{$key.Dispose();$root.Dispose()}
}
function Set-DeployPrinterRpcSetting($State) {
    $root=Open-DeployPrinterPolicyRoot;$key=$null
    try{
        if($State.Present){
            $key=$root.CreateSubKey($script:DeployPrinterRpcKey)
            $key.SetValue($script:DeployPrinterRpcValue,[int]$State.Value,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()
        }else{
            $key=$root.OpenSubKey($script:DeployPrinterRpcKey,$true)
            if($key){$key.DeleteValue($script:DeployPrinterRpcValue,$false)}
        }
    }finally{if($key){$key.Dispose()};$root.Dispose()}
}

# ---------- Error codes ----------
# Windows reports printer connection failures as Win32 codes inside CIM / COM exceptions or in the message text.
function Get-DeployPrinterErrorCode($Failure) {
    $item=$Failure
    if($item -is [Management.Automation.ErrorRecord]){$item=$item.Exception}
    $depth=0
    while($item -and $depth -lt 6){
        $depth++
        $data=$null;try{$data=$item.ErrorData}catch{}
        if($data){
            foreach($name in @('error_Code')){
                $value=$null
                try{if($data.CimInstanceProperties){$property=$data.CimInstanceProperties[$name];if($property){$value=$property.Value}}}catch{}
                if($null -eq $value){try{$value=$data.$name}catch{}}
                $parsed=0L
                if($null -ne $value -and [long]::TryParse([string]$value,[ref]$parsed) -and $parsed -gt 0){return [int]($parsed -band 0xFFFF)}
            }
        }
        $message='';try{$message=[string]$item.Message}catch{}
        $match=[regex]::Match($message,'0x([0-9A-Fa-f]{8})')
        if($match.Success){
            $value=[Convert]::ToInt64($match.Groups[1].Value,16)
            $high=($value -shr 16) -band 0xFFFF
            if($high -eq 0x8007 -or $high -eq 0){return [int]($value -band 0xFFFF)}
        }
        if($item -is [ComponentModel.Win32Exception] -and $item.NativeErrorCode -gt 0){return [int]$item.NativeErrorCode}
        $hresult=0;try{$hresult=[int]$item.HResult}catch{}
        if((($hresult -shr 16) -band 0xFFFF) -eq 0x8007){return [int]($hresult -band 0xFFFF)}
        $next=$null;try{$next=$item.InnerException}catch{}
        $item=$next
    }
    return 0
}
function Format-DeployPrinterCode([int]$Code) {'0x'+$Code.ToString('x8')}
function Get-DeployPrinterErrorText([int]$Code,$Context=$null) {
    $label=Format-DeployPrinterCode $Code
    $modern=$Context -and [int]$Context.Build -ge 22621
    $rpcOff=$Context -and -not $Context.RpcNamedPipes
    switch($Code){
        283 {
            $text='Máy chủ in yêu cầu mã hoá kết nối in (bản vá bảo mật PrintNightmare) nhưng kết nối từ máy này không đạt ('+$label+'). Cập nhật Windows trên cả hai máy rồi thử lại.'
            if($modern -and $rpcOff){$text+=' Máy này là Windows 11 22H2 trở lên: nếu máy chủ là Windows 10 / bản cũ, thử Chế độ tương thích RPC ở dưới.'}
            $text+=' Không tắt RpcAuthnLevelPrivacyEnabled trên máy chủ; nếu máy in có cổng LAN, thêm theo IP để không phụ thuộc máy chủ.'
            return $text
        }
        1801 {
            $text='Máy chủ không mở được máy in này ('+$label+'). Kiểm tra tên chia sẻ của máy in trên máy chủ (Printer properties → Sharing).'
            if($modern -and $rpcOff){$text+=' Máy này là Windows 11 22H2 trở lên, lỗi này hay gặp khi máy chủ không nhận RPC qua TCP: thử Chế độ tương thích RPC ở dưới.'}
            return $text
        }
        3019 {return ('Máy này cần driver của máy in trước khi kết nối ('+$label+'). Chọn thư mục driver đúng model (cùng tên driver trên máy chủ) để app cài bằng quyền Administrator, rồi kết nối lại.')}
        3020 {return ('Driver trên máy chủ chưa có bản cho Windows 64-bit / kiến trúc của máy này ('+$label+'). Chọn thư mục driver đúng model để cài trên máy này.')}
        1797 {return ('Driver máy in không xác định được ('+$label+'). Chọn thư mục driver đúng model rồi thử lại.')}
        126 {return ('Driver trên máy này không nạp được ('+$label+'): thường do driver 32/64-bit không khớp hoặc cài dở. Cài lại driver từ thư mục của hãng.')}
        1722 {return ('Máy chủ in không trả lời ('+$label+'). Kiểm tra máy chủ đang bật, dịch vụ Print Spooler đang chạy và tường lửa cho phép File and Printer Sharing trong mạng Private.')}
        1726 {return ('Kết nối RPC tới máy chủ in bị ngắt ('+$label+'). Khởi động lại Print Spooler trên máy chủ rồi thử lại.')}
        5 {return ('Tài khoản không có quyền dùng máy in này ('+$label+'). Trên máy chủ, mở Printer properties → Security, cho tài khoản (ví dụ print) hoặc nhóm Users quyền Print.')}
        2 {return ('Không tìm thấy máy in trên máy chủ ('+$label+'). Kiểm tra tên chia sẻ và máy in vẫn đang được chia sẻ.')}
        64 {return ('Mất kết nối mạng tới máy chủ trong lúc kết nối ('+$label+'). Kiểm tra dây mạng / Wi-Fi rồi thử lại.')}
        1219 {return (Get-DeployShareLogonError 1219)}
        1272 {return (Get-DeployShareLogonError 1272)}
        1326 {return (Get-DeployShareLogonError 1326)}
        53 {return (Get-DeployShareLogonError 53)}
    }
    if($Code -le 0){return 'Windows chưa kết nối được máy in và không trả mã lỗi. Xem nhật ký.'}
    return ('Windows chưa kết nối được máy in ('+$label+'): '+([ComponentModel.Win32Exception]::new($Code)).Message)
}

# ---------- Driver packages ----------
function Remove-DeployInfComment([string]$Line) {
    $quoted=$false
    for($i=0;$i -lt $Line.Length;$i++){
        $char=$Line[$i]
        if($char -eq '"'){$quoted=-not $quoted}elseif($char -eq ';' -and -not $quoted){return $Line.Substring(0,$i)}
    }
    return $Line
}
function Resolve-DeployInfString([string]$Value,$Strings) {
    $text=$Value.Trim()
    $token=[regex]::Match($text,'^%([^%]+)%$')
    if($token.Success){
        $key=$token.Groups[1].Value.ToLowerInvariant()
        if($Strings.ContainsKey($key)){$text=[string]$Strings[$key]}
    }
    if($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')){$text=$text.Substring(1,$text.Length-2)}
    return $text.Replace('""','"').Trim()
}
# INF files are ANSI or UTF-16 (often with, sometimes without a byte-order mark); UTF-8 needs a BOM.
function Read-DeployInfText([string]$Path) {
    [byte[]]$bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){return [Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)}
    if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE){return [Text.Encoding]::Unicode.GetString($bytes,2,$bytes.Length-2)}
    if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF){return [Text.Encoding]::BigEndianUnicode.GetString($bytes,2,$bytes.Length-2)}
    if($bytes.Length -ge 4 -and $bytes[1] -eq 0 -and $bytes[3] -eq 0){return [Text.Encoding]::Unicode.GetString($bytes)}
    return [Text.Encoding]::Default.GetString($bytes)
}
# Printer models an INF installs for this processor: the names Add-PrinterDriver / a print server use.
function Get-DeployPrinterInfModels([string]$Text,[string]$Architecture='') {
    if(-not $Architecture){$Architecture=Get-DeployPrinterArchitecture}
    $sections=@{};$current=''
    foreach($raw in ($Text -split '\r?\n')){
        $line=(Remove-DeployInfComment $raw).Trim()
        if(-not $line){continue}
        $header=[regex]::Match($line,'^\[([^\]]+)\]$')
        if($header.Success){$current=$header.Groups[1].Value.Trim().ToLowerInvariant();if(-not $sections.ContainsKey($current)){$sections[$current]=New-Object Collections.ArrayList};continue}
        if($current){[void]$sections[$current].Add($line)}
    }
    if(-not $sections.ContainsKey('version') -or -not $sections.ContainsKey('manufacturer')){return @()}
    $isPrinter=$false
    foreach($line in $sections['version']){
        if($line -match '^(?i)Class\s*=\s*"?Printer"?\s*$'){$isPrinter=$true}
        if($line -match '^(?i)ClassGuid\s*=\s*(\{[^}]+\})' -and $Matches[1].ToLowerInvariant() -eq $script:DeployPrinterClassGuid){$isPrinter=$true}
    }
    if(-not $isPrinter){return @()}
    $strings=@{}
    if($sections.ContainsKey('strings')){
        foreach($line in $sections['strings']){
            $pair=$line.Split('=',2)
            if($pair.Count -eq 2){$strings[$pair[0].Trim().ToLowerInvariant()]=(Resolve-DeployInfString $pair[1] @{})}
        }
    }
    $decorations=@('','nt','nt'+$Architecture)
    $models=New-Object Collections.ArrayList;$seen=@{}
    foreach($line in $sections['manufacturer']){
        $pair=$line.Split('=',2)
        if($pair.Count -ne 2){continue}
        $vendor=Resolve-DeployInfString $pair[0] $strings
        $parts=@($pair[1].Split(',') | ForEach-Object {$_.Trim()})
        $base=$parts[0].ToLowerInvariant()
        if(-not $base){continue}
        $names=@()
        if($parts.Count -eq 1){$names=@($base)}
        foreach($decoration in @($parts | Select-Object -Skip 1)){
            $kind=($decoration.Split('.')[0]).ToLowerInvariant()
            if($decorations -contains $kind){$names+=($base+'.'+$decoration.ToLowerInvariant())}
        }
        foreach($name in $names){
            if(-not $sections.ContainsKey($name)){continue}
            foreach($entry in $sections[$name]){
                $model=$entry.Split('=',2)
                if($model.Count -ne 2){continue}
                $display=Resolve-DeployInfString $model[0] $strings
                if(-not $display -or $seen.ContainsKey($display.ToLowerInvariant())){continue}
                $seen[$display.ToLowerInvariant()]=$true
                [void]$models.Add([pscustomobject]@{Model=$display;Manufacturer=$vendor})
            }
        }
    }
    @($models | Sort-Object Model)
}
function Get-DeployPrinterDriverPackages([string]$Folder,[string]$Architecture='',[int]$MaxFiles=2000) {
    $root=Get-Item -LiteralPath $Folder -ErrorAction Stop
    if(-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Chọn thư mục thật chứa driver đã giải nén (có file .inf), không dùng junction / symlink.'}
    $queue=New-Object Collections.Queue;$queue.Enqueue($root.FullName)
    $packages=New-Object Collections.ArrayList;$count=0
    while($queue.Count){
        $dir=$queue.Dequeue()
        foreach($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($item.PSIsContainer){$queue.Enqueue($item.FullName);continue}
            if($item.Extension -ine '.inf'){continue}
            $count++
            if($count -gt $MaxFiles){throw ('Thư mục có hơn '+$MaxFiles+' file .inf. Chọn thư mục driver của đúng model máy in.')}
            $models=@()
            try{$models=@(Get-DeployPrinterInfModels ((Read-DeployInfText $item.FullName)) $Architecture)}catch{continue}
            foreach($model in $models){[void]$packages.Add([pscustomobject]@{Model=$model.Model;Manufacturer=$model.Manufacturer;Inf=$item.FullName})}
        }
    }
    @($packages | Sort-Object Model,Inf)
}
function Install-DeployPrinterDriver([string]$Model,[string]$InfPath,[string]$LogPath) {
    if(@(Get-DeployInstalledPrinterDrivers) -ccontains $Model){
        Write-DeployWindowsToolsLog $LogPath 'driver-present' @{Model=$Model}
        return [pscustomobject]@{Installed=$false;Message=('Driver '+$Model+' đã có trên máy.')}
    }
    if(-not $InfPath){throw ('Máy này chưa có driver '+$Model+'. Bấm Chọn thư mục driver… và chọn bộ driver đã giải nén của hãng.')}
    if(-not (Test-Path -LiteralPath $InfPath -PathType Leaf)){throw ('Không còn file driver: '+$InfPath+'. Chọn lại thư mục driver.')}
    $models=@(Get-DeployPrinterInfModels ((Read-DeployInfText $InfPath)))
    if(@($models | ForEach-Object {$_.Model}) -cnotcontains $Model){throw ('File '+[IO.Path]::GetFileName($InfPath)+' không có model '+$Model+' cho Windows của máy này. Chọn đúng bộ driver.')}
    Write-DeployWindowsToolsLog $LogPath 'driver-add-request' @{Model=$Model;Inf=$InfPath;Hash=(Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash}
    $result=Invoke-DeployPnputil @('/add-driver',$InfPath)
    Write-DeployWindowsToolsLog $LogPath 'driver-pnputil' $result
    if($result.ExitCode -notin 0,259,3010){throw ('Windows chưa nhận gói driver (pnputil mã '+$result.ExitCode+'). Driver cần có chữ ký số hợp lệ; tải lại bộ driver của hãng. Xem nhật ký.')}
    Add-PrinterDriver -Name $Model -ErrorAction Stop
    if(@(Get-DeployInstalledPrinterDrivers) -cnotcontains $Model){throw ('Windows chưa xác nhận driver '+$Model+' đã cài.')}
    Write-DeployWindowsToolsLog $LogPath 'driver-installed' @{Model=$Model}
    [pscustomobject]@{Installed=$true;Message=('Đã cài driver '+$Model+' (quyền Administrator, driver có chữ ký).')}
}

# ---------- RPC compatibility ----------
function Get-DeployPrinterRpcView {
    $build=0;try{$build=[int](Get-DeployWindowsToolsIdentity).Build}catch{}
    $setting=Get-DeployPrinterRpcSetting
    $enabled=$setting.Present -and [string]$setting.Kind -eq 'DWord' -and [int]$setting.Value -eq 1
    $backup=Test-Path -LiteralPath (Get-DeployPrinterRpcBackupPath)
    if($build -lt 22621){$text='Máy này là Windows 10 / Windows 11 trước 22H2 (build '+$build+'): đã kết nối qua named pipes, không cần chế độ này.'}
    elseif($enabled){$text='Đang bật: máy này kết nối máy chủ in qua RPC named pipes'+$(if($backup){' (app đã bật, có bản sao lưu để hoàn tác).'}else{' (do chính sách / người khác đặt).'})}
    elseif($setting.Present){$text='Đang đặt RPC qua TCP theo chính sách ('+[string]$setting.Value+').'}
    else{$text='Mặc định Windows 11 22H2+: kết nối máy chủ in qua RPC over TCP (build '+$build+').'}
    [pscustomobject]@{Build=$build;Enabled=[bool]$enabled;Setting=$setting;HasBackup=[bool]$backup;CanEnable=($build -ge 22621 -and -not $enabled);CanUndo=[bool]$backup;Text=$text}
}
function Set-DeployPrinterRpcCompatibility([bool]$Enable,[string]$LogPath) {
    if(-not (Test-DeployPrinterAdmin)){throw 'Mở TechMaster Deploy bằng quyền Administrator để đổi cách kết nối máy chủ in.'}
    $view=Get-DeployPrinterRpcView
    $backupPath=Get-DeployPrinterRpcBackupPath
    Write-DeployWindowsToolsLog $LogPath 'rpc-request' @{Enable=$Enable;Before=$view.Setting;Build=$view.Build;HasBackup=$view.HasBackup}
    if($Enable){
        if($view.Build -lt 22621){return [pscustomobject]@{Message=$view.Text;Kind='Info';Log=$LogPath}}
        if($view.Enabled){return [pscustomobject]@{Message='Chế độ tương thích RPC đã bật; không ghi lại.';Kind='Info';Log=$LogPath}}
        if($view.Setting.Present -and [string]$view.Setting.Kind -ne 'DWord'){throw 'Giá trị RpcUseNamedPipeProtocol đang có kiểu khác DWORD; chưa ghi đè. Kiểm tra Group Policy của máy.'}
        if(-not $view.HasBackup){
            [IO.File]::WriteAllText($backupPath,(([pscustomobject]@{Present=$view.Setting.Present;Value=$view.Setting.Value;Time=(Get-Date).ToString('o')}) | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
            Write-DeployWindowsToolsLog $LogPath 'rpc-backup' @{Path=$backupPath;State=$view.Setting}
        }
        Set-DeployPrinterRpcSetting ([pscustomobject]@{Present=$true;Value=1})
        $after=Get-DeployPrinterRpcSetting
        if(-not $after.Present -or [int]$after.Value -ne 1){throw 'Windows chưa xác nhận thiết lập RPC.'}
        $message='✓ Đã bật: máy này kết nối máy chủ in qua RPC named pipes (vẫn xác thực tài khoản và mã hoá như trước). Không thay đổi bảo mật của máy chủ in.'
    }else{
        if(-not $view.HasBackup){return [pscustomobject]@{Message='Chưa có bản sao lưu do app tạo; không hoàn tác thiết lập do chính sách / người khác đặt.';Kind='Info';Log=$LogPath}}
        $saved=[IO.File]::ReadAllText($backupPath) | ConvertFrom-Json
        $state=[pscustomobject]@{Present=[bool]$saved.Present;Value=$(if($saved.Present){[int]$saved.Value}else{$null})}
        Set-DeployPrinterRpcSetting $state
        $after=Get-DeployPrinterRpcSetting
        if([bool]$after.Present -ne $state.Present -or ($state.Present -and [int]$after.Value -ne $state.Value)){throw 'Windows chưa xác nhận đã khôi phục thiết lập RPC.'}
        Remove-Item -LiteralPath $backupPath -Force
        $message='✓ Đã hoàn tác: khôi phục cách kết nối máy chủ in như trước khi app bật.'
    }
    Write-DeployWindowsToolsLog $LogPath 'rpc-after' (Get-DeployPrinterRpcSetting)
    try{Restart-DeployPrintSpooler;$message+=' Đã khởi động lại Print Spooler; thử kết nối máy in lại.';$kind='Success'}
    catch{$message+=' Chưa khởi động lại được Print Spooler ('+$_.Exception.GetBaseException().Message+'); khởi động lại máy để áp dụng.';$kind='Attention'}
    Write-DeployWindowsToolsLog $LogPath 'rpc-done' @{Enable=$Enable;Kind=$kind}
    [pscustomobject]@{Message=$message;Kind=$kind;Log=$LogPath}
}

# ---------- Diagnosis (read-only) ----------
function New-DeployPrinterCheck([ValidateSet('Ok','Fail','Warn','Info')][string]$State,[string]$Text) {[pscustomobject]@{State=$State;Text=$Text}}
function Format-DeployPrinterDiagnosis($Checks) {
    $marks=@{Ok='✓';Fail='✗';Warn='!';Info='–'}
    $states=@($Checks | ForEach-Object {$_.State})
    $kind=if($states -contains 'Fail'){'Error'}elseif($states -contains 'Warn'){'Attention'}else{'Success'}
    [pscustomobject]@{Message=(@($Checks | ForEach-Object {$marks[$_.State]+' '+$_.Text}) -join "`n");Kind=$kind}
}
function Get-DeployIpPrinterDiagnosis([string]$Address,$Port) {
    $checks=@()
    $host_=ConvertFrom-DeployPrinterAddress $Address
    $number=ConvertFrom-DeployPrinterPortNumber $Port
    $ping=Test-DeployPing $host_
    $checks+=if($ping){New-DeployPrinterCheck Ok ('Máy in '+$host_+' trả lời ping.')}else{New-DeployPrinterCheck Info ('Máy in '+$host_+' không trả lời ping (nhiều máy in tắt ping; xem kết quả cổng in).')}
    $raw=Test-DeployTcpPort $host_ $number
    $checks+=if($raw){New-DeployPrinterCheck Ok ('Cổng in '+$number+' mở: in trực tiếp qua TCP/IP được, không cần máy chủ in.')}else{New-DeployPrinterCheck Fail ('Chưa kết nối được cổng '+$number+'. Kiểm tra máy in bật, cùng lớp mạng với máy này (IP 192.168.x.y cùng x), IP trên máy in đúng.')}
    $web=Test-DeployTcpPort $host_ 80 800
    if($web){$checks+=New-DeployPrinterCheck Info ('Trang cấu hình máy in: http://'+$host_+' (đổi IP tĩnh, bật Scan to folder ở đây).')}
    $portName=Get-DeployPrinterPortName $host_ $number
    try{
        $existing=@(Get-PrinterPort -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $portName -or [string]$_.PrinterHostAddress -ieq $host_})
        $queues=@(Get-Printer -ErrorAction Stop | Where-Object {$existing.Name -contains [string]$_.PortName})
        if($queues.Count){$checks+=New-DeployPrinterCheck Info ('Máy này đã có máy in dùng địa chỉ này: '+(@($queues | ForEach-Object {$_.Name}) -join ', ')+'.')}
    }catch{$checks+=New-DeployPrinterCheck Warn ('Không đọc được danh sách máy in: '+$_.Exception.GetBaseException().Message)}
    $spooler=Get-DeploySpoolerState
    if($spooler -ne 'Running'){$checks+=New-DeployPrinterCheck Fail ('Dịch vụ Print Spooler trên máy này đang '+$(if($spooler){$spooler}else{'không đọc được'})+'.')}
    $checks
}
function Get-DeploySharePrinterDiagnosis([string]$Path) {
    $checks=@()
    $target=ConvertFrom-DeployPrinterShare $Path
    $server=$target.Server
    $ping=Test-DeployPing $server
    $checks+=if($ping){New-DeployPrinterCheck Ok ('Máy chủ '+$server+' trả lời ping.')}else{New-DeployPrinterCheck Info ('Máy chủ '+$server+' không trả lời ping (tường lửa có thể chặn ping).')}
    $smb=Test-DeployTcpPort $server 445
    $checks+=if($smb){New-DeployPrinterCheck Ok 'Cổng 445 (chia sẻ file và máy in) mở.'}else{New-DeployPrinterCheck Fail ('Không vào được cổng 445 của '+$server+'. Kiểm tra máy chủ bật, cùng mạng, tường lửa cho phép File and Printer Sharing trong mạng Private.')}
    $rpc=Test-DeployTcpPort $server 135
    $checks+=if($rpc){New-DeployPrinterCheck Ok 'Cổng 135 (RPC) mở.'}else{New-DeployPrinterCheck Warn 'Cổng 135 (RPC) đóng: Windows 11 22H2+ kết nối máy chủ in qua RPC over TCP sẽ lỗi (thường 0x00000709 / 0x000006ba). Mở tường lửa trên máy chủ, hoặc dùng Chế độ tương thích RPC.'}
    $saved='';try{$saved=[string](Get-DeployShareCredentialUser $server)}catch{}
    $checks+=if($saved){New-DeployPrinterCheck Ok ('Đã lưu mật khẩu cho '+$server+' (tài khoản '+$saved+').')}else{New-DeployPrinterCheck Warn ('Chưa lưu mật khẩu cho '+$server+': nhập tài khoản có mật khẩu (ví dụ print) để app kiểm tra và lưu. App không dùng Guest / tài khoản không mật khẩu.')}
    $remote=''
    if($smb){try{$remote=[string](Get-DeployRemotePrinterDriver $server $target.Share)}catch{}}
    if($remote){
        $local=@();try{$local=@(Get-DeployInstalledPrinterDrivers)}catch{}
        $checks+=New-DeployPrinterCheck Ok ('Máy chủ dùng driver: '+$remote+'.')
        $checks+=if($local -ccontains $remote){New-DeployPrinterCheck Ok 'Máy này đã có driver cùng tên: kết nối không cần tải driver.'}else{New-DeployPrinterCheck Warn ('Máy này chưa có driver '+$remote+'. App chạy quyền Administrator có thể lấy driver từ máy chủ; nếu lỗi 0x00000bcb, chọn thư mục driver cùng tên.')}
    }else{$checks+=New-DeployPrinterCheck Info 'Chưa đọc được tên driver trên máy chủ (cần tài khoản đã lưu hoặc máy chủ chặn RPC).'}
    $view=Get-DeployPrinterRpcView
    $checks+=New-DeployPrinterCheck $(if($view.Build -ge 22621 -and -not $view.Enabled -and -not $rpc){'Warn'}else{'Info'}) ('Cách kết nối máy chủ in: '+$view.Text)
    try{if(@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $target.Path}).Count){$checks+=New-DeployPrinterCheck Info ('Tài khoản này đã kết nối '+$target.Path+'.')}}catch{}
    $spooler=Get-DeploySpoolerState
    if($spooler -ne 'Running'){$checks+=New-DeployPrinterCheck Fail ('Dịch vụ Print Spooler trên máy này đang '+$(if($spooler){$spooler}else{'không đọc được'})+'.')}
    $checks
}

# ---------- Changes ----------
function Complete-DeployPrinterSetup([string]$Name,[bool]$A4,[bool]$Default,[bool]$TestPage,[string]$LogPath) {
    $lines=@();$problems=@()
    if($A4 -or $Default){
        try{
            $r=Set-DeployPrinterDefaults $Name $A4 $Default $LogPath
            foreach($line in @(([string]$r.Message) -split "`n" | Where-Object {$_})){if($r.Kind -eq 'Success'){$lines+=('✓ '+$line)}else{$problems+=$line}}
        }catch{$problems+=$_.Exception.GetBaseException().Message}
    }
    if($TestPage){
        try{Invoke-DeployPrinterTestPage $Name;$lines+='✓ Đã gửi trang in thử; kiểm tra giấy ra ở máy in.';Write-DeployWindowsToolsLog $LogPath 'test-page' $Name}
        catch{$problems+=('Trang in thử: '+$_.Exception.GetBaseException().Message)}
    }
    [pscustomobject]@{Lines=$lines;Problems=$problems}
}
function Add-DeployIpPrinter([string]$Address,$Port,[string]$Name,[string]$Driver,[string]$InfPath,[bool]$A4,[bool]$Default,[bool]$TestPage,[string]$LogPath) {
    if(-not (Test-DeployPrinterAdmin)){throw 'Mở TechMaster Deploy bằng quyền Administrator để thêm máy in.'}
    $host_=ConvertFrom-DeployPrinterAddress $Address
    $number=ConvertFrom-DeployPrinterPortNumber $Port
    $queue=Assert-DeployPrinterName $Name
    $model=([string]$Driver).Trim()
    if(-not $model){throw 'Chọn driver máy in (đã cài trên máy hoặc từ thư mục driver của hãng).'}
    Write-DeployWindowsToolsLog $LogPath 'ip-request' @{Address=$host_;Port=$number;Name=$queue;Driver=$model;Inf=$InfPath;A4=$A4;Default=$Default;TestPage=$TestPage}
    $lines=@();$problems=@()
    $reachable=Test-DeployTcpPort $host_ $number
    Write-DeployWindowsToolsLog $LogPath 'ip-reachable' @{Address=$host_;Port=$number;Reachable=$reachable}
    if(-not $reachable){$problems+=('Chưa kết nối được '+$host_+':'+$number+' — máy in có thể đang tắt hoặc sai IP; hàng đợi vẫn được tạo, in được khi máy in lên mạng.')}
    $driverResult=Install-DeployPrinterDriver $model $InfPath $LogPath
    $lines+=('✓ '+$driverResult.Message)
    $portName=Get-DeployPrinterPortName $host_ $number
    $port=@(Get-PrinterPort -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $portName})
    if($port.Count){
        if([string]$port[0].PrinterHostAddress -and [string]$port[0].PrinterHostAddress -ine $host_){throw ('Cổng '+$portName+' đã có nhưng trỏ tới '+$port[0].PrinterHostAddress+'; không ghi đè. Kiểm tra lại trong Print Management.')}
        $lines+=('✓ Dùng lại cổng TCP/IP '+$portName+'.')
    }else{
        Add-PrinterPort -Name $portName -PrinterHostAddress $host_ -PortNumber $number -ErrorAction Stop
        Write-DeployWindowsToolsLog $LogPath 'port-added' @{Port=$portName;Address=$host_;Number=$number}
        $lines+=('✓ Đã tạo cổng Standard TCP/IP '+$portName+' (RAW '+$number+', không bật SNMP để tránh báo Offline sai).')
    }
    $existing=@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $queue})
    if($existing.Count){
        if([string]$existing[0].PortName -ieq $portName -and [string]$existing[0].DriverName -ceq $model){$lines+=('✓ Máy in '+$queue+' đã có với cùng cổng và driver; không tạo lại.')}
        else{throw ('Tên '+$queue+' đã được máy in khác dùng (cổng '+$existing[0].PortName+', driver '+$existing[0].DriverName+'). Đặt tên khác.')}
    }else{
        Add-Printer -Name $queue -DriverName $model -PortName $portName -ErrorAction Stop
        if(@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $queue}).Count -ne 1){throw 'Windows chưa xác nhận máy in đã thêm.'}
        Write-DeployWindowsToolsLog $LogPath 'printer-added' @{Name=$queue;Driver=$model;Port=$portName}
        $lines+=('✓ Đã thêm máy in '+$queue+' → '+$host_+'.')
    }
    $done=Complete-DeployPrinterSetup $queue $A4 $Default $TestPage $LogPath
    $lines+=$done.Lines;$problems+=$done.Problems
    $lines+=@($problems | ForEach-Object {'✗ '+$_})
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($problems.Count){'Attention'}else{'Success'});Log=$LogPath}
}
function Get-DeployPrinterContext {
    $view=$null;try{$view=Get-DeployPrinterRpcView}catch{}
    if(-not $view){return [pscustomobject]@{Build=0;RpcNamedPipes=$false}}
    [pscustomobject]@{Build=$view.Build;RpcNamedPipes=$view.Enabled}
}
function Connect-DeploySharedPrinter([string]$Path,[string]$Account,[Security.SecureString]$Password,[string]$Driver,[string]$InfPath,[bool]$Default,[bool]$TestPage,[string]$LogPath) {
    if(-not (Test-DeployPrinterAdmin)){throw 'Mở TechMaster Deploy bằng quyền Administrator để cài driver và kết nối máy in.'}
    $target=ConvertFrom-DeployPrinterShare $Path
    Assert-DeployConnectUser
    $user=([string]$Account).Trim()
    $hasPassword=$Password -and $Password.Length -gt 0
    Write-DeployWindowsToolsLog $LogPath 'share-request' @{Path=$target.Path;User=$user;NewPassword=[bool]$hasPassword;Driver=$Driver;Inf=$InfPath;Default=$Default;TestPage=$TestPage}
    $lines=@();$problems=@()
    if($hasPassword){
        if(-not $user){throw 'Nhập tài khoản trên máy chủ in (ví dụ print).'}
        $code=[int](Test-DeployServerLogon $target.Server $user $Password)
        Write-DeployWindowsToolsLog $LogPath 'logon-test' @{Server=$target.Server;User=$user;Code=$code}
        if($code -ne 0){throw (Get-DeployShareLogonError $code)}
        Save-DeployShareCredential $target.Server $user $Password
        if([string](Get-DeployShareCredentialUser $target.Server) -cne $user){throw 'Windows chưa xác nhận mật khẩu đã lưu.'}
        $lines+=('✓ Đăng nhập '+$target.Server+' bằng '+$user+' thành công; đã lưu mật khẩu vào Credential Manager của '+[Security.Principal.WindowsIdentity]::GetCurrent().Name+'.')
    }else{
        $saved=[string](Get-DeployShareCredentialUser $target.Server)
        if(-not $saved){throw ('Chưa có mật khẩu đã lưu cho '+$target.Server+'. Nhập tài khoản có mật khẩu trên máy chủ (ví dụ print, tạo ở Mạng LAN & chia sẻ → Tài khoản chia sẻ LAN). App không kết nối kiểu Guest / không mật khẩu.')}
        $lines+=('✓ Dùng mật khẩu đã lưu cho '+$target.Server+' (tài khoản '+$saved+').')
    }
    $remote='';try{$remote=[string](Get-DeployRemotePrinterDriver $target.Server $target.Share)}catch{Write-DeployWindowsToolsLog $LogPath 'remote-driver-failed' $_.Exception.GetBaseException().Message}
    $model=([string]$Driver).Trim()
    if($remote -and $model -and $model -cne $remote){throw ('Máy chủ dùng driver '+$remote+', khác driver đã chọn ('+$model+'). Kết nối máy in share cần đúng tên driver như máy chủ: chọn Tự động hoặc model '+$remote+'.')}
    if(-not $model){$model=$remote}
    if($model){
        if($InfPath -or @(Get-DeployInstalledPrinterDrivers) -ccontains $model){
            $driverResult=Install-DeployPrinterDriver $model $InfPath $LogPath
            $lines+=('✓ '+$driverResult.Message)
        }else{$lines+=('– Máy này chưa có driver '+$model+'; Windows lấy driver từ máy chủ bằng quyền Administrator của app.')}
    }
    $already=@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $target.Path}).Count -gt 0
    if($already){$lines+=('✓ Tài khoản này đã kết nối '+$target.Path+'.')}
    else{
        try{Add-Printer -ConnectionName $target.Path -ErrorAction Stop}
        catch{
            $code=Get-DeployPrinterErrorCode $_
            Write-DeployWindowsToolsLog $LogPath 'connect-failed' @{Path=$target.Path;Code=$code;Error=$_.Exception.GetBaseException().Message}
            throw (Get-DeployPrinterErrorText $code (Get-DeployPrinterContext))
        }
        if(@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $target.Path}).Count -ne 1){throw 'Windows chưa xác nhận đã kết nối máy in.'}
        Write-DeployWindowsToolsLog $LogPath 'connected' @{Path=$target.Path}
        $lines+=('✓ Đã kết nối '+$target.Path+' cho tài khoản Windows đang dùng máy.')
    }
    # Windows keeps its own spelling of the connection name; later steps match the queue exactly.
    $queue=[string]@(Get-Printer -ErrorAction Stop | Where-Object {[string]$_.Name -ieq $target.Path})[0].Name
    $done=Complete-DeployPrinterSetup $queue $false $Default $TestPage $LogPath
    $lines+=$done.Lines;$problems+=$done.Problems
    $lines+=@($problems | ForEach-Object {'✗ '+$_})
    [pscustomobject]@{Message=($lines -join "`n");Kind=$(if($problems.Count){'Attention'}else{'Success'});Log=$LogPath}
}

# ---------- Worker entry ----------
function Invoke-DeployPrinterConnectAction([ValidateSet('Inspect','Scan','Diagnose','Apply','RpcEnable','RpcUndo')][string]$Action,$Payload,[string]$LogPath) {
    switch($Action){
        'Inspect' {
            $drivers=@();$problem=''
            try{$drivers=@(Get-DeployInstalledPrinterDrivers)}catch{$problem=$_.Exception.GetBaseException().Message}
            return [pscustomobject]@{Message=$(if($problem){'Không đọc được danh sách driver: '+$problem}else{''});Kind=$(if($problem){'Attention'}else{'Info'});Drivers=$drivers;Rpc=(Get-DeployPrinterRpcView);Log=''}
        }
        'Scan' {
            $packages=@(Get-DeployPrinterDriverPackages ([string]$Payload.Folder))
            Write-DeployWindowsToolsLog $LogPath 'scan' @{Folder=[string]$Payload.Folder;Models=$packages.Count}
            $message=if($packages.Count){'Tìm thấy '+$packages.Count+' model máy in trong thư mục driver. Chọn đúng model trong danh sách Driver.'}else{'Không có driver máy in cho Windows của máy này trong thư mục đã chọn. Giải nén bộ driver của hãng (file .exe / .zip) rồi chọn thư mục có file .inf.'}
            return [pscustomobject]@{Message=$message;Kind=$(if($packages.Count){'Success'}else{'Attention'});Packages=$packages;Log=$LogPath}
        }
        'Diagnose' {
            $checks=if($Payload.Mode -eq 'Ip'){Get-DeployIpPrinterDiagnosis $Payload.Address $Payload.Port}else{Get-DeploySharePrinterDiagnosis $Payload.Path}
            Write-DeployWindowsToolsLog $LogPath 'diagnosis' @{Mode=$Payload.Mode;Checks=@($checks)}
            $view=Format-DeployPrinterDiagnosis $checks
            return [pscustomobject]@{Message=$view.Message;Kind=$view.Kind;Log=$LogPath}
        }
        'Apply' {
            $result=if($Payload.Mode -eq 'Ip'){Add-DeployIpPrinter $Payload.Address $Payload.Port $Payload.Name $Payload.Driver $Payload.Inf ([bool]$Payload.A4) ([bool]$Payload.Default) ([bool]$Payload.TestPage) $LogPath}
                else{Connect-DeploySharedPrinter $Payload.Path $Payload.Account $Payload.Password $Payload.Driver $Payload.Inf ([bool]$Payload.Default) ([bool]$Payload.TestPage) $LogPath}
            $drivers=@();try{$drivers=@(Get-DeployInstalledPrinterDrivers)}catch{}
            return [pscustomobject]@{Message=$result.Message;Kind=$result.Kind;Drivers=$drivers;Log=$LogPath}
        }
        'RpcEnable' {$r=Set-DeployPrinterRpcCompatibility $true $LogPath;return [pscustomobject]@{Message=$r.Message;Kind=$r.Kind;Rpc=(Get-DeployPrinterRpcView);Log=$LogPath}}
        'RpcUndo' {$r=Set-DeployPrinterRpcCompatibility $false $LogPath;return [pscustomobject]@{Message=$r.Message;Kind=$r.Kind;Rpc=(Get-DeployPrinterRpcView);Log=$LogPath}}
    }
}
