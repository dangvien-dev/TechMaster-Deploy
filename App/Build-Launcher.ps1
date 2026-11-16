$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dotNet = Join-Path $env:WINDIR 'Microsoft.NET'
$framework = if ([Environment]::Is64BitOperatingSystem) { 'Framework64' } else { 'Framework' }
$compiler = Join-Path $dotNet "$framework\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The Windows .NET Framework C# compiler was not found.'
}

$exe = Join-Path $root 'TechMaster Deploy.exe'
$icon = Join-Path $PSScriptRoot 'TechMaster.ico'
$manifest = Join-Path $PSScriptRoot 'Launcher.manifest'
$source = Join-Path $PSScriptRoot 'Launcher.cs'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/out:$exe" "/win32icon:$icon" "/win32manifest:$manifest" /reference:System.Windows.Forms.dll $source
if ($LASTEXITCODE -ne 0) { throw "Launcher build failed with code $LASTEXITCODE." }
Write-Output $exe
