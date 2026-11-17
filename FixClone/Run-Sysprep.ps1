# Graphical confirmations; no typed YES. Do not run this entrypoint in a test suite.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'UltraViewer.Core.ps1')
. (Join-Path $PSScriptRoot 'Master.Deployment.Core.ps1')
try {
    $system=Join-Path $env:SystemRoot 'System32'
    if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){$system=Join-Path $env:SystemRoot 'Sysnative'}
    $principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $command="& '{0}'" -f $PSCommandPath.Replace("'","''")
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process=Start-Process -FilePath (Join-Path $system 'WindowsPowerShell/v1.0/powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -PassThru -Wait
        exit $process.ExitCode
    }
    if(Get-Process sysprep -ErrorAction SilentlyContinue){throw 'Sysprep đang chạy. Chờ kết thúc trước khi tạo ảnh mới.'}
    $null=New-Item -ItemType Directory -Path (Join-Path $env:SystemDrive 'FixClone') -Force
    $work=Join-Path $env:SystemDrive 'FixClone'
    $optionsPath=Join-Path $work 'MasterOptions.json'
    if(Test-Path -LiteralPath $optionsPath){Remove-Item -LiteralPath $optionsPath -Force}
    & (Join-Path $PSScriptRoot 'Master-Preflight.ps1') -OptionsPath $optionsPath
    if(-not (Test-Path -LiteralPath $optionsPath)){return}
    $options=Get-Content -LiteralPath $optionsPath -Raw -Encoding UTF8|ConvertFrom-Json
    $volume=Get-CimInstance -Namespace root/cimv2/Security/MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume -Filter "DriveLetter='C:'" -ErrorAction Stop
    if($volume -and $volume.ConversionStatus -ne 0){throw 'Ổ C: còn mã hoá BitLocker. Giải mã xong trước khi Sysprep.'}
    $office=Get-MasterOfficeDirectory
    function Copy-DeploymentFile([string]$source,[string]$target) {
        if([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop}
    }
    foreach($name in 'Fix-CloneDuplicate.ps1','Fix-DinhDang.ps1','UltraViewer.Core.ps1','Master.Deployment.Core.ps1','Load-Ui.ps1','UltraViewer-Reset.ps1','UltraViewer-Reset.xml','UltraViewer.Diagnostics.ps1') {Copy-DeploymentFile (Join-Path $PSScriptRoot $name) (Join-Path $work $name)}
    foreach($name in 'Office-Cleanup.Core.ps1','Office-Cleanup.Engine.ps1'){Copy-DeploymentFile (Join-Path $office $name) (Join-Path $work $name)}
    $uiSource=Split-Path -Parent $runtime
    New-Item -ItemType Directory -Path (Join-Path $work 'App') -Force|Out-Null
    foreach($name in 'Wpf.Runtime.ps1','ConfirmWindow.xml','DesktopIdentity.cs','TechMaster.ico'){Copy-DeploymentFile (Join-Path $uiSource $name) (Join-Path (Join-Path $work 'App') $name)}
    $reinstall=Join-Path $PSScriptRoot 'Reinstall'
    if((Test-Path -LiteralPath $reinstall) -and [IO.Path]::GetFullPath($reinstall) -ne [IO.Path]::GetFullPath((Join-Path $work 'Reinstall'))){Copy-Item -LiteralPath $reinstall -Destination $work -Recurse -Force}
    $unattend=Join-Path $system 'Sysprep/unattend.xml'
    & (Join-Path $PSScriptRoot 'New-Unattend.ps1') -OutputPath $unattend
    $null=Invoke-MasterDeployment $options $work $system $unattend
} catch {Show-DeployMessage $_.Exception.GetBaseException().Message 'Chưa chạy được Sysprep' 'Error';exit 1}
