# Actual noninteractive engine and file transactions, with network/Windows process effects mocked.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
. (Join-Path $PSScriptRoot 'Update.Engine.ps1')
$script:checks = 0
function Assert($condition, $message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Put($path, $text) { New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null; [IO.File]::WriteAllText($path,$text) }
function Payload($path,$version) {
    Put (Join-Path $path 'version.txt') $version
    Put (Join-Path $path 'App/TechMaster-Deploy.ps1') ('# app '+$version)
    Put (Join-Path $path 'TechMaster Deploy.exe') 'fake launcher; never executed'
    $files = @(Get-ChildItem -LiteralPath $path -File -Recurse | ForEach-Object {
        [pscustomobject]@{ path=$_.FullName.Substring($path.Length+1).Replace('\','/'); sha256=(Get-DeployHash $_.FullName); preserve=$false }
    })
    Write-DeployJson ([pscustomobject]@{ schema=1;product='TechMaster.Deploy';version=$version;files=$files }) (Join-Path $path 'update-package.json')
}
function Get-DeployOnlineRelease { return $script:remote }
$script:toolsCheck = ${function:Assert-DeployToolsClosed}
function Assert-DeployToolsClosed {}
function Start-Process { $script:restarts++ }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-engine-'+[guid]::NewGuid().ToString('N'))
try {
    $root=Join-Path $temp 'installed'; $work=Join-Path $temp 'work'; $script:restarts=0
    Payload $root '1.1.3.0'
    Put (Join-Path $root 'BienBan/BienBan-Config.json') 'my customer data'
    $script:remote=[pscustomobject]@{ unchanged=$true }
    $result=Invoke-DeployUpdateTask -Operation Check -Root $root -Work $work
    Assert ($result.state -eq 'Latest' -and $script:restarts -eq 0) 'Latest check never closes or restarts the app'
    $script:remote=[pscustomobject]@{ unchanged=$false;version='1.2.0.0';commit=('a'*40) }
    $result=Invoke-DeployUpdateTask -Operation Check -Root $root -Work $work
    Assert ($result.state -eq 'Available' -and $result.release.version -eq '1.2.0.0') 'Check returns an offer without applying it'
    Assert ((Get-DeployVersion $root) -eq [version]'1.1.3.0') 'Offer leaves installed version untouched'
    $stage=Join-Path $temp 'package/TechMaster-Deploy'
    Payload $stage '1.2.0.0'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=Join-Path $temp 'update.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $stage),$zip)
    $result=Invoke-DeployUpdateTask -Operation PrepareLocal -Root $root -Work $work -PackagePath $zip
    Assert ($result.state -eq 'Ready' -and (Get-DeployVersion $root) -eq [version]'1.1.3.0') 'Preparation verifies the ZIP without installing'
    Assert ((Get-DeployUpdateView $result.state).action -eq 'Apply') 'Ready state exposes explicit graphical installation action'
    Assert ((Get-DeployUpdateView 'Available').action -eq 'PrepareOnline') 'Available state exposes download, not installation'
    $view=Get-DeployUpdateView 'Applying'
    Assert ($view.busy -and -not $view.action) 'Applying cannot trigger another UI operation'
    $result=Invoke-DeployUpdateTask -Operation Apply -Root $root -Work $work
    Assert ($result.state -eq 'Complete' -and (Get-DeployVersion $root) -eq [version]'1.2.0.0') 'Explicit Apply commits real update transaction'
    Assert ($script:restarts -eq 1) 'Successful Apply restarts once'
    Assert ([IO.File]::ReadAllText((Join-Path $root 'BienBan/BienBan-Config.json')) -ceq 'my customer data') 'WPF engine preserves customer configuration'
    $history=Invoke-DeployUpdateTask -Operation History -Root $root -Work $work
    Assert ($history.state -eq 'History' -and @($history.rows).Count -eq 1 -and $history.rows[0].Status -eq 'Đã cập nhật') 'History is a graphical data result with friendly status'
    $rollback=Invoke-DeployUpdateTask -Operation RollbackInfo -Root $root -Work $work
    Assert ($rollback.state -eq 'RollbackReady' -and $rollback.backup) 'Rollback is offered separately before any mutation'
    Assert ((Get-DeployVersion $root) -eq [version]'1.2.0.0') 'Rollback offer leaves current version intact'
    $result=Invoke-DeployUpdateTask -Operation Rollback -Root $root -Work $work -Backup $rollback.backup
    Assert ($result.state -eq 'Complete' -and (Get-DeployVersion $root) -eq [version]'1.1.3.0') 'Explicit rollback restores actual files'
    Assert ($script:restarts -eq 2) 'Rollback restarts once'
    Assert ([IO.File]::ReadAllText((Join-Path $root 'BienBan/BienBan-Config.json')) -ceq 'my customer data') 'Rollback preserves customer configuration'
    function Get-CimInstance {
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& '$root/FixClone/Master-Preflight.ps1' -AfterClone"))
        [pscustomobject]@{ProcessId=($PID+100);CommandLine=('powershell.exe -EncodedCommand '+$encoded)}
    }
    $caught=''
    try { & $script:toolsCheck $root } catch { $caught=$_.Exception.Message }
    Assert ($caught -match 'Còn cửa sổ công cụ') 'Updater detects tools launched by encoded PowerShell commands before changing files'
    $progress=Get-Content -LiteralPath (Join-Path $work 'progress.json') -Raw | ConvertFrom-Json
    Assert ($progress.percent -eq 100 -and $progress.message) 'Engine publishes completion progress without any console interaction'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
Write-Host "PASS: $script:checks graphical update engine assertions; real staging, explicit apply, history, restore and data preservation."
