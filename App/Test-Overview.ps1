# Formatting uses fixed values; the snapshot is then read for real (read-only CIM, registry and network).
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Overview.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
Assert ((Format-DeployGigabytes (16GB-300MB)) -ceq '16 GB' -and (Format-DeployGigabytes 8.2GB) -ceq '8,2 GB' -and (Format-DeployGigabytes 0) -ceq '') 'Sizes are in GB with a Vietnamese decimal comma'
Assert ((Format-DeployWindowsVersion 'Microsoft Windows 11 Pro' '24H2' '26100' '2314' '64-bit') -ceq 'Windows 11 Pro 24H2 · build 26100.2314 · 64-bit') 'Windows edition, version, build and architecture are combined'
Assert ((Format-DeployWindowsVersion 'Microsoft Windows 10 Pro' '' '19045' '0' '') -ceq 'Windows 10 Pro · build 19045') 'Missing parts are left out'
Assert ((Format-DeployCpu '  Intel(R) Core(TM)   i5-12450H ' 8 12) -ceq 'Intel(R) Core(TM) i5-12450H · 8 nhân / 12 luồng' -and (Format-DeployCpu 'AMD Ryzen 3' 4 4) -ceq 'AMD Ryzen 3 · 4 nhân') 'CPU name is tidied and shows cores / threads'
Assert ((Format-DeployDisk 'C:' 120GB 476GB 'SSD') -ceq 'C: trống 120 GB / 476 GB · SSD' -and (Format-DeployDisk 'C:' 1GB 2GB 'Unspecified') -ceq 'C: trống 1 GB / 2 GB' -and (Format-DeployDisk 'C:' 0 0 '') -ceq '') 'System disk shows free / total and SSD / HDD when Windows knows it'
Assert ((Format-DeployLicense ([pscustomobject]@{State='Đã kích hoạt';Keys=@('3V66T','XGVPP')})) -ceq 'Đã kích hoạt (key …3V66T, …XGVPP)' -and (Format-DeployLicense ([pscustomobject]@{State='không phát hiện';Keys=@()})) -ceq 'không phát hiện' -and (Format-DeployLicense $null) -ceq 'không đọc được') 'Licences show their state and only the last 5 key characters'
Assert ((Get-DeployOverviewValue {throw 'boom'}) -ceq 'không đọc được' -and (Get-DeployOverviewValue {'   '}) -ceq 'không đọc được' -and (Get-DeployOverviewValue {' giá trị '}) -ceq 'giá trị') 'A failing or empty source reads as không đọc được'
$original=${function:Get-DeployLicenseSummary}
try{
    function Get-DeployLicenseSummary {throw 'Software Protection service is stopped'}
    $broken=Get-DeployOverviewSnapshot
    Assert ($broken.WindowsLicense -ceq 'không đọc được' -and $broken.Office -ceq 'không đọc được' -and $broken.Header -ceq ('Máy: '+$env:COMPUTERNAME+'    Windows: không đọc được    Office: không đọc được') -and $broken.Windows -ne 'không đọc được') 'A licensing failure only affects the licence fields'
}finally{Set-Item Function:Get-DeployLicenseSummary $original}
$s=Get-DeployOverviewSnapshot
Assert ($s.Computer -ceq $env:COMPUTERNAME -and $s.Windows -match 'Windows' -and $s.Windows -match 'build \d+') "Windows edition and build are read ($($s.Windows))"
Assert ($s.Cpu -cne 'không đọc được' -and $s.Ram -match '^\d+(,\d)? GB$' -and $s.Disk -match '^[A-Z]: trống \d') "CPU, RAM and system disk are read ($($s.Cpu) | $($s.Ram) | $($s.Disk))"
Assert ($s.WindowsLicense -match '^(Đã kích hoạt|CHƯA kích hoạt|không đọc được)' -and $s.Header -match '^Máy: ') "Licence state and header are formed ($($s.Header))"
$text=Format-DeployOverviewText $s
Assert ($text.Split("`n").Count -eq 9 -and $text.StartsWith('Tên máy: '+$env:COMPUTERNAME) -and $text -match 'Địa chỉ IP: ') 'Copied text lists every field with its label'
Write-Host "PASS: $checks overview assertions; formatting, independent fields and a real read-only snapshot."
