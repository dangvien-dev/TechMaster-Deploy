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
    $valid = Test-Path -LiteralPath $target
    if ($valid) {
        $saved = [IO.File]::ReadAllText($target) | ConvertFrom-Json
        foreach ($key in 'schema','product','repository','branch','version') { if ([string]$saved.$key -cne [string]$index[$key]) { $valid = $false } }
        $map = @{}
        foreach ($entry in $saved.files) {
            if ($map.ContainsKey($entry.path)) { $valid = $false }
            $map[$entry.path] = $entry
        }
        if ($map.Count -ne $files.Count) { $valid = $false }
        foreach ($entry in $files) {
            $old = $map[$entry.path]
            if (-not $old -or $old.sha -cne $entry.sha -or [long]$old.size -ne [long]$entry.size -or $old.mode -cne $entry.mode) { $valid = $false }
        }
    }
    # Windows PowerShell 5.1 and PowerShell 7 serialize indentation differently.
    # Compare the actual metadata and hashes rather than JSON whitespace.
    if (-not $valid) { throw 'Danh sách cập nhật chưa khớp mã nguồn. Chạy App/Build-UpdateIndex.ps1 trước khi commit.' }
    Write-Host 'Danh sách cập nhật khớp toàn bộ mã nguồn.'
} else {
    [IO.File]::WriteAllText($target, $json, [Text.UTF8Encoding]::new($false))
    Write-Host ('Đã tạo danh sách cập nhật: ' + $files.Count + ' tệp.')
}
