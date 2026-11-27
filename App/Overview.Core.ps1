# Read-only summary of this computer for the Tổng quan page. Each field is read on its own: one source
# that fails (CIM, licensing service, storage, network) shows "không đọc được" and never hides the others.
$script:DeployOverviewFields=@(
    [pscustomobject]@{Name='Computer';Label='Tên máy'},[pscustomobject]@{Name='Model';Label='Hãng / model'},
    [pscustomobject]@{Name='Windows';Label='Windows'},[pscustomobject]@{Name='Cpu';Label='CPU'},
    [pscustomobject]@{Name='Ram';Label='RAM'},[pscustomobject]@{Name='Disk';Label='Ổ hệ thống'},
    [pscustomobject]@{Name='Address';Label='Địa chỉ IP'},[pscustomobject]@{Name='WindowsLicense';Label='Bản quyền Windows'},
    [pscustomobject]@{Name='Office';Label='Office'})
$script:DeployOverviewUnknown='không đọc được'
$script:DeployLicenseIds=@{Windows='55c92734-d682-4d71-983e-d6ec3f16059f';Office='0ff1ce15-a989-479d-af46-f275c6370663'}

function Get-DeployOverviewValue([scriptblock]$Read) {
    try{$value=([string](& $Read)).Trim();if($value){return $value}}catch{}
    return $script:DeployOverviewUnknown
}
function Format-DeployGigabytes([double]$Bytes) {
    if($Bytes -le 0){return ''}
    $value=$Bytes/1GB
    if($value -ge 10){return ([string][Math]::Round($value))+' GB'}
    return ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0:0.#}',$value)).Replace('.',',')+' GB'
}
function Format-DeployWindowsVersion([string]$Caption,[string]$Display,[string]$Build,[string]$Revision,[string]$Architecture) {
    $name=([string]$Caption -replace '^\s*Microsoft\s+','').Trim()
    $parts=@($name+$(if($Display){' '+$Display}else{''}))
    if($Build){$parts+=('build '+$Build+$(if($Revision -and $Revision -ne '0'){'.'+$Revision}else{''}))}
    if($Architecture){$parts+=$Architecture}
    return ($parts -join ' · ')
}
function Format-DeployCpu([string]$Name,[int]$Cores,[int]$Threads) {
    $text=([string]$Name -replace '\s+',' ').Trim()
    if($Cores -gt 0){$text+=' · '+$Cores+' nhân'+$(if($Threads -gt $Cores){' / '+$Threads+' luồng'}else{''})}
    return $text
}
function Format-DeployDisk([string]$Drive,[double]$Free,[double]$Size,[string]$Media) {
    if($Size -le 0){return ''}
    $text=$Drive+' trống '+(Format-DeployGigabytes $Free)+' / '+(Format-DeployGigabytes $Size)
    if($Media -and $Media -notin 'Unspecified','0'){$text+=' · '+$Media}
    return $text
}
# State is 'Đã kích hoạt', 'CHƯA kích hoạt' or the given text when no key is installed; Keys are the last 5 characters.
function Get-DeployLicenseSummary([string]$ApplicationId,[string]$Missing) {
    $items=@(Get-CimInstance SoftwareLicensingProduct -Filter ("ApplicationID='"+$ApplicationId+"' AND PartialProductKey IS NOT NULL") -ErrorAction Stop)
    if(-not $items.Count){return [pscustomobject]@{State=$Missing;Keys=@()}}
    $state=if(@($items | Where-Object {$_.LicenseStatus -ne 1}).Count){'CHƯA kích hoạt'}else{'Đã kích hoạt'}
    [pscustomobject]@{State=$state;Keys=@($items | ForEach-Object {[string]$_.PartialProductKey} | Where-Object {$_} | Select-Object -Unique)}
}
function Format-DeployLicense($Summary) {
    if(-not $Summary){return $script:DeployOverviewUnknown}
    $text=[string]$Summary.State
    if(@($Summary.Keys).Count){$text+=' (key …'+(@($Summary.Keys) -join ', …')+')'}
    return $text
}
function Get-DeploySystemMedia([string]$Drive) {
    $partition=Get-Partition -DriveLetter $Drive.Substring(0,1) -ErrorAction Stop
    $disk=@(Get-PhysicalDisk -ErrorAction Stop | Where-Object {[string]$_.DeviceId -eq [string]$partition.DiskNumber})[0]
    if($disk){[string]$disk.MediaType}else{''}
}
function Get-DeployOverviewSnapshot {
    $computer=[string]$env:COMPUTERNAME
    $system=$null;$os=$null
    try{$system=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop}catch{}
    try{$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop}catch{}
    $windowsLicense=$null;$officeLicense=$null
    try{$windowsLicense=Get-DeployLicenseSummary $script:DeployLicenseIds.Windows 'không đọc được'}catch{}
    try{$officeLicense=Get-DeployLicenseSummary $script:DeployLicenseIds.Office 'không phát hiện'}catch{}
    $drive=[string]$env:SystemDrive
    $snapshot=[pscustomobject]@{
        Computer=$computer
        Model=(Get-DeployOverviewValue {
            $name=(@([string]$system.Manufacturer,[string]$system.Model) | ForEach-Object {$_.Trim()} | Where-Object {$_ -and $_ -notmatch '^(System manufacturer|System Product Name|To be filled by O\.E\.M\.)$'}) -join ' '
            $serial='';try{$serial=([string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber).Trim()}catch{}
            if($serial -and $serial -notmatch '^(Default string|To be filled by O\.E\.M\.|System Serial Number|0+)$'){$name+=' · S/N '+$serial}
            $name})
        Windows=(Get-DeployOverviewValue {
            $current=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $display=if($current.DisplayVersion){[string]$current.DisplayVersion}else{[string]$current.ReleaseId}
            Format-DeployWindowsVersion ([string]$os.Caption) $display ([string]$current.CurrentBuild) ([string]$current.UBR) ([string]$os.OSArchitecture)})
        Cpu=(Get-DeployOverviewValue {
            $cpu=@(Get-CimInstance Win32_Processor -ErrorAction Stop)
            Format-DeployCpu ([string]$cpu[0].Name) ([int](($cpu | Measure-Object NumberOfCores -Sum).Sum)) ([int](($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum))})
        Ram=(Get-DeployOverviewValue {Format-DeployGigabytes ([double]$system.TotalPhysicalMemory)})
        Disk=(Get-DeployOverviewValue {
            $disk=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='"+$drive+"'") -ErrorAction Stop
            $media='';try{$media=Get-DeploySystemMedia $drive}catch{}
            Format-DeployDisk $drive ([double]$disk.FreeSpace) ([double]$disk.Size) $media})
        Address=(Get-DeployOverviewValue {
            (@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {[string]$_.IPAddress -notmatch '^(127|169\.254)\.' -and [string]$_.AddressState -eq 'Preferred'} | Sort-Object InterfaceIndex | ForEach-Object {[string]$_.IPAddress+' ('+[string]$_.InterfaceAlias+')'})) -join ', '})
        WindowsLicense=(Format-DeployLicense $windowsLicense)
        Office=(Format-DeployLicense $officeLicense)
        Header=''
    }
    $snapshot.Header='Máy: '+$computer+'    Windows: '+$(if($windowsLicense){$windowsLicense.State}else{$script:DeployOverviewUnknown})+'    Office: '+$(if($officeLicense){$officeLicense.State}else{$script:DeployOverviewUnknown})
    return $snapshot
}
function Format-DeployOverviewText($Snapshot) {
    (@($script:DeployOverviewFields | ForEach-Object {$_.Label+': '+[string]$Snapshot.($_.Name)})) -join "`r`n"
}
