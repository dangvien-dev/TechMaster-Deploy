$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'CustomApps.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Fails([scriptblock]$action){$caught=$false;try{&$action|Out-Null}catch{$caught=$true};return $caught}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-custom-'+[guid]::NewGuid().ToString('N'))
$oldProfile=$env:LOCALAPPDATA;$oldSystem=$env:SystemRoot
try{
    New-Item -ItemType Directory -Path $temp|Out-Null;$env:LOCALAPPDATA=Join-Path $temp 'profile';$env:SystemRoot=Join-Path $temp 'Windows'
    $path=Get-DeployCustomAppsPath
    Assert ($path.StartsWith($env:LOCALAPPDATA)) 'Catalog is local to the current Windows user'
    $exe=Join-Path $temp "Bộ cài's app.exe";$msi=Join-Path $temp 'Package name.msi'
    [IO.File]::WriteAllText($exe,'fixture only');[IO.File]::WriteAllText($msi,'fixture only')
    $one=New-DeployCustomApp 'PowerToys' WinGet -PackageId 'Microsoft.PowerToys'
    $two=New-DeployCustomApp 'Phần mềm nội bộ' Local -Path $exe -Arguments '/S'
    Save-DeployCustomApps $path @($one,$two)
    $read=@(Get-DeployCustomApps $path)
    Assert ($read.Count -eq 2 -and $read[1].Path -ceq $exe -and $read[1].Arguments -ceq '/S') 'WinGet and Unicode installer entries round-trip'
    $changed=New-DeployCustomApp 'Tên mới' WinGet -PackageId 'Microsoft.PowerToys' -Key $one.Key
    Save-DeployCustomApps $path @($changed,$two)
    Assert (@(Get-DeployCustomApps $path)[0].Name -ceq 'Tên mới') 'Editing retains the entry key'
    $plan=New-DeployBasicStartInfo $two 'unused'
    Assert ($plan.FileName -ceq $exe -and $plan.Arguments -eq '/S' -and -not $plan.UseShellExecute) 'EXE runs directly with selected arguments and no command shell'
    $localMsi=New-DeployCustomApp 'MSI' Local -Path $msi -Arguments '/quiet'
    $plan=New-DeployBasicStartInfo $localMsi 'unused'
    Assert ($plan.FileName -like '*msiexec.exe' -and $plan.Arguments.Contains('"'+$msi+'"') -and $plan.Arguments -match '/norestart') 'MSI path is quoted and avoids automatic reboot'
    $plan=New-DeployBasicStartInfo $one 'winget.exe'
    Assert ($plan.Arguments -match '--id Microsoft.PowerToys --exact' -and -not $plan.UseShellExecute) 'WinGet selection reaches an exact package'
    Assert (Fails {New-DeployCustomApp 'Bad' WinGet -PackageId 'A.B --override evil'}) 'Package arguments cannot be injected through the ID'
    Assert (Fails {New-DeployCustomApp 'Script' Local -Path (Join-Path $temp 'run.ps1')}) 'Only EXE/MSI installers are accepted'
    Assert (Fails {Save-DeployCustomApps $path @($one,$one)}) 'Duplicate catalog keys are rejected'
    Assert (@(Get-DeployCustomApps $path).Count -eq 2) 'Invalid replacement preserves the last valid catalog'
    Remove-Item -LiteralPath $exe
    Assert (@(Get-DeployCustomApps $path).Count -eq 2) 'Unplugged installer storage does not erase catalog entries'
    Assert (Fails {New-DeployBasicStartInfo $two 'unused'}) 'A missing installer is rejected before execution'
    Save-DeployCustomApps $path @()
    Assert (@(Get-DeployCustomApps $path).Count -eq 0) 'Removing all custom entries persists an empty list'
}finally{$env:LOCALAPPDATA=$oldProfile;$env:SystemRoot=$oldSystem;if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks custom-app assertions; local storage, add/edit/delete, launch plans, Unicode paths and validation."
