$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Pdf.Printer.ps1')
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++}
$script:printers=@();$script:fail=$false;$script:queries=0
function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction)
    $script:queries++
    if($script:fail){throw 'Mock Spooler unavailable'}
    return $script:printers
}
$result=Complete-DeployFoxitReader @{Status='Đã có';Group='Skipped'} 'winget already installed'
Assert ($result.Group -eq 'Skipped' -and $result.Status -match 'chưa có máy in PDF') 'Reader already-installed does not imply an installed PDF printer'
Assert ($result.Details -match 'không kèm' -and $result.Details -match 'Microsoft Print to PDF') 'Missing Foxit printer is explained without claiming Reader installs a printer'
$script:printers=@([pscustomobject]@{Name='Foxit PDF Printer';DriverName='Foxit PDF Printer Driver';PortName='FOXIT:';WorkOffline=$false},[pscustomobject]@{Name='HP Printer';DriverName='HP';PortName='USB001';WorkOffline=$false})
$inventory=Get-DeployPdfPrinterInventory
Assert ($inventory.Printers.Count -eq 1 -and $inventory.Printers[0].Name -eq 'Foxit PDF Printer') 'PDF queue inventory excludes unrelated physical printers'
$result=Complete-DeployFoxitReader @{Status='Đã cài';Group='Installed'} 'native'
Assert ($result.Group -eq 'Installed' -and $result.Details -match 'FOXIT:' -and $result.Details -match 'chưa xác nhận') 'Queue name/driver/port are recorded without claiming a successful print test'
$script:printers=@([pscustomobject]@{Name='Microsoft Print to PDF';DriverName='Microsoft Print To PDF';PortName='PORTPROMPT:';WorkOffline=$false})
$result=Complete-DeployFoxitReader @{Status='Reboot';Group='Restart'} ''
Assert ($result.Group -eq 'Restart' -and $result.Details -match 'Microsoft Print to PDF' -and $result.Status -match 'khởi động lại') 'Microsoft queue is recognized independently and reboot outcome is preserved'
$script:fail=$true;$result=Complete-DeployFoxitReader @{Status='Đã có';Group='Skipped'} ''
Assert ($result.Status -match 'chưa đọc' -and $result.Status -notmatch 'chưa có' -and $result.Details -match 'Spooler unavailable') 'Printer query failure is not misreported as missing PDF capability'
$before=$script:queries;$result=Complete-DeployFoxitReader @{Status='Install failed';Group='Failed'} 'error'
Assert ($result.Status -eq 'Install failed' -and $script:queries -eq $before) 'Failed Reader installation is retained without post-install work'
Write-Host "PASS: $checks PDF printer assertions; Reader/printer distinction, vendor-neutral queue discovery, restart and unreadable Spooler."
