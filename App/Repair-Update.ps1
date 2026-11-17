<# One-time bootstrap for versions whose updater cannot reach the API.
   Download this script from the project's public repository, close TechMaster,
   then run with -Root pointing to the existing application directory. #>
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Công cụ này dành cho Windows.' }
    Add-Type -AssemblyName PresentationFramework
    if ($Root) {
        $Root = [IO.Path]::GetFullPath($Root)
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'App/TechMaster-Deploy.ps1') -PathType Leaf)) { throw 'Không tìm thấy TechMaster trong thư mục đã chọn.' }
    }
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $command = "& '{0}' -Root '{1}'" -f $PSCommandPath.Replace("'", "''"), $Root.Replace("'", "''")
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        Start-Process -FilePath $shell -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -ErrorAction Stop | Out-Null
        return
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $runner = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Update Runner/' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $runner -Force | Out-Null
    $core = Join-Path $runner 'Update.Core.ps1'
    # This bootstrap, like the script itself, comes only from the fixed HTTPS
    # repository. Resolve an immutable revision before downloading the runner.
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dangvien-dev/TechMaster-Deploy/main/App/Update.Core.ps1' -UseBasicParsing -OutFile $core -TimeoutSec 60 -ErrorAction Stop
    . $core
    $release = Get-DeployOnlineRelease
    foreach ($name in 'Update.Core.ps1', 'Update-App.ps1', 'Update.Engine.ps1', 'Wpf.Runtime.ps1', 'UpdaterWindow.xml') {
        $entry = @($release.files | Where-Object { $_.path -ceq ('App/' + $name) })
        if ($entry.Count -ne 1) { throw 'Bản cập nhật thiếu công cụ cần thiết.' }
        [byte[]]$bytes = Get-DeployRepositoryBlob $entry[0]
        [IO.File]::WriteAllBytes((Join-Path $runner $name), $bytes)
    }
    $command = "& '{0}' -Root '{1}' -Mode Online" -f (Join-Path $runner 'Update-App.ps1').Replace("'", "''"), $Root.Replace("'", "''")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    # Exit this bootstrap before the updater's open-tool check. Waiting here
    # would leave another PowerShell command line containing the app's root.
    $child = Start-Process -FilePath $shell -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded) -WorkingDirectory $runner -WindowStyle Hidden -PassThru -ErrorAction Stop
    if ($child) { $child.Dispose() }
    return
} catch {
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'Không chuẩn bị được cập nhật', 'OK', 'Error')
    exit 1
}
