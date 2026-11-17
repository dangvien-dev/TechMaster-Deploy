param(
    [Parameter(Mandatory = $true)][version]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$LauncherPath = '',
    [string]$Notes = 'Cập nhật trực tiếp từ repo GitHub; giữ cấu hình, sao lưu và quay lại. Xem CHANGELOG.md trong gói.'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $LauncherPath) {
    & (Join-Path $PSScriptRoot 'Build-Launcher.ps1') | Out-Host
    $LauncherPath = Join-Path $root 'TechMaster Deploy.exe'
}
if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) { throw 'Chưa có launcher Windows để đóng gói.' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$name = 'TechMaster-Deploy-v' + $Version.ToString() + '.zip'
$zipPath = Join-Path $OutputDirectory $name
if (Test-Path -LiteralPath $zipPath) { throw 'Gói phiên bản này đã tồn tại. Chọn thư mục đầu ra khác hoặc tăng phiên bản.' }
$stage = Join-Path $OutputDirectory ('stage_' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $stage 'TechMaster-Deploy'
New-Item -ItemType Directory -Path $app -Force | Out-Null
try {
    $sourceFiles = @(& git -C $root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Không đọc được danh sách tệp Git.' }
    foreach ($relative in $sourceFiles) {
        $default = $relative -cin @('BienBan/Logo.svg', 'FixClone/Reinstall/_DOC-TRUOC.txt')
        if (-not $default) {
            try { Assert-DeployPath $relative } catch { continue }
        }
        $target = Join-Path $app $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        [IO.File]::Copy((Join-Path $root $relative), $target)
    }
    [IO.File]::Copy($LauncherPath, (Join-Path $app 'TechMaster Deploy.exe'))
    [IO.File]::WriteAllText((Join-Path $app 'version.txt'), ($Version.ToString() + "`r`n"), [Text.UTF8Encoding]::new($false))
    $files = @(Get-ChildItem -LiteralPath $app -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($app.Length + 1).Replace('\', '/')
        [pscustomobject]@{ path = $rel; sha256 = (Get-DeployHash $_.FullName); preserve = ($rel -cin @('BienBan/Logo.svg', 'FixClone/Reinstall/_DOC-TRUOC.txt')) }
    } | Sort-Object path)
    $commit = ([string](& git -C $root rev-parse HEAD)).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Không đọc được commit của checkout.' }
    $dirty = @(& git -C $root status --porcelain).Count -gt 0
    $manifest = [pscustomobject]@{
        schema = 1; product = $script:DeployProduct; version = $Version.ToString(); notes = $Notes; files = $files
        source = [pscustomobject]@{ repository = $script:DeployRepository; branch = $script:DeployBranch; commit = $commit; dirty = $dirty }
    }
    Write-DeployJson $manifest (Join-Path $app 'update-package.json')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
    $hash = Get-DeployHash $zipPath
    $verifyDir = Join-Path $stage 'verify'
    $null = Expand-DeployPackage $zipPath $verifyDir $hash
    [IO.File]::WriteAllText(($zipPath + '.sha256'), ($hash + '  ' + $name + "`n"), [Text.UTF8Encoding]::new($false))
    Write-Host "Đã tạo và xác minh: $zipPath"
    Write-Output $zipPath
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
