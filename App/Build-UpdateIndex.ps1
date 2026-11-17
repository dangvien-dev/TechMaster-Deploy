param([switch]$Check)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$root = Split-Path -Parent $PSScriptRoot
$paths = @(& git -C $root ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được danh sách tệp chương trình.' }
$files = @(foreach ($path in ($paths | Sort-Object -Unique)) {
    try { Assert-DeployPath $path } catch { continue }
    if ($path -ceq 'TechMaster Deploy.exe') { continue }
    Assert-DeployRegularPath $root $path
    [byte[]]$bytes = [IO.File]::ReadAllBytes((Join-Path $root $path))
    [ordered]@{ path = $path; mode = '100644'; size = $bytes.Length; sha = (Get-DeployGitBlobHash $bytes) }
})
$index = [ordered]@{
    schema = 1; product = $script:DeployProduct; repository = $script:DeployRepository
    branch = $script:DeployBranch; version = (Get-DeployVersion $root).ToString(); files = $files
}
$json = ($index | ConvertTo-Json -Depth 6) + "`n"
$target = Join-Path $root 'update-source.json'
if ($Check) {
    if (-not (Test-Path -LiteralPath $target) -or [IO.File]::ReadAllText($target) -cne $json) { throw 'Danh sách cập nhật chưa khớp mã nguồn. Chạy App/Build-UpdateIndex.ps1 trước khi commit.' }
    Write-Host 'Danh sách cập nhật khớp toàn bộ mã nguồn.'
} else {
    [IO.File]::WriteAllText($target, $json, [Text.UTF8Encoding]::new($false))
    Write-Host ('Đã tạo danh sách cập nhật: ' + $files.Count + ' tệp.')
}
