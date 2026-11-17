# Public transport is mocked; parser, hashes, index validation and file staging are real.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$script:checks = 0
$script:realRead = ${function:Read-DeployPublicBytes}
function Assert($condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $caught = ''
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -match $pattern) "Expected $pattern; got $caught"
}
function Packet([string]$body) { return ('{0:x4}' -f ($body.Length + 4)) + $body }
function Bytes([string]$text) { return ,[Text.Encoding]::UTF8.GetBytes($text) }
function Reset-Remote {
    $script:requests = @(); $script:apiCalls = 0; $script:publicBlocked = $false
    $script:commit = 'b' * 40
    $script:refs = [Text.Encoding]::ASCII.GetBytes((Packet "# service=git-upload-pack`n") + '0000' + (Packet (($script:commit + ' HEAD') + [char]0 + "symref=HEAD:refs/heads/main`n")) + (Packet ($script:commit + " refs/heads/main`n")) + '0000')
    $script:text = @{
        'version.txt' = '1.1.3.0'; 'App/TechMaster-Deploy.ps1' = '# new app'
        'App/Launcher.cs' = '# launcher'; 'App/Launcher.manifest' = '<assembly/>'
        'App/TechMaster.ico' = 'icon'; 'App/Update.Core.ps1' = '# core'
        'App/Update-App.ps1' = '# updater'; 'App/Update-UI.ps1' = '# ui'
    }
    $script:index = [pscustomobject]@{
        schema = 1; product = 'TechMaster.Deploy'; repository = 'dangvien-dev/TechMaster-Deploy'; branch = 'main'; version = '1.1.3.0'
        files = @(foreach ($path in $script:text.Keys) {
            $bytes = Bytes $script:text[$path]
            [pscustomobject]@{ path = $path; mode = '100644'; sha = (Get-DeployGitBlobHash $bytes); size = $bytes.Length }
        })
    }
}
function Read-DeployPublicBytes($kind, $commit, $path, $limit) {
    $script:requests += [pscustomobject]@{ kind = $kind; commit = $commit; path = $path }
    if ($script:publicBlocked) { throw 'Public connection unavailable' }
    if ($kind -eq 'Refs') { return ,$script:refs }
    Assert ($commit -ceq $script:commit) 'Every raw URL is pinned to the resolved commit'
    if ($path -eq 'update-source.json') { return Bytes ($script:index | ConvertTo-Json -Depth 6) }
    if ($script:text.ContainsKey($path)) { return Bytes $script:text[$path] }
    throw "Unexpected public path: $path"
}
function Invoke-DeployGitHub { throw 'API is blocked with HTTP 403' }
function Get-DeployApiRelease($knownCommit) { $script:apiCalls++; return [pscustomobject]@{ fallback = $true; known = $knownCommit } }
function Build-DeployRepositoryLauncher([string]$payload) { [IO.File]::WriteAllText((Join-Path $payload 'TechMaster Deploy.exe'), 'mock launcher; never run') }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-public-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    Reset-Remote
    Assert ((ConvertFrom-DeployGitRefs $script:refs) -ceq $script:commit) 'Parse real Git pkt-line capabilities and main ref'
    Expect-Failure { ConvertFrom-DeployGitRefs (Bytes '<html>403 Forbidden</html>') } 'không hợp lệ'
    Expect-Failure { ConvertFrom-DeployGitRefs (Bytes '003dshort') } 'cắt ngắn'
    Expect-Failure { ConvertFrom-DeployGitRefs (Bytes ((Packet "# service=git-upload-pack`n") + (Packet ($script:commit + " refs/heads/other`n")) + '0000')) } 'Chưa đọc'
    Expect-Failure { ConvertFrom-DeployGitRefs (Bytes ([Text.Encoding]::ASCII.GetString($script:refs) + (Packet ($script:commit + " refs/heads/main`n")))) } 'trùng'
    Expect-Failure { & $script:realRead -kind File -commit '../main' -path 'version.txt' } 'không hợp lệ'
    Expect-Failure { & $script:realRead -kind File -commit $script:commit -path '../secret' } 'không hợp lệ'
    Expect-Failure { & $script:realRead -kind Refs -limit 100MB } 'không hợp lệ'
    $state = Get-DeployOnlineRelease $script:commit
    Assert ($state.unchanged -and $script:requests.Count -eq 1 -and $script:apiCalls -eq 0) 'Latest-version check works without API, manifest or blobs'
    $state = Get-DeployOnlineRelease ('a' * 40)
    Assert ($state.version -eq '1.1.3.0' -and $state.commit -ceq $script:commit -and $script:apiCalls -eq 0) 'Public update succeeds while all API calls would return 403'
    Assert (@($state.files).Count -eq 8 -and @($state.files | Where-Object { $_.publicCommit -cne $script:commit }).Count -eq 0) 'All validated files use one immutable revision'
    $root = Join-Path $temp 'installed'
    foreach ($f in $state.files) {
        $target = Join-Path $root $f.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        [IO.File]::WriteAllBytes($target, (Bytes $script:text[$f.path]))
    }
    [IO.File]::WriteAllText((Join-Path $root 'App/TechMaster-Deploy.ps1'), '# old app')
    $before = $script:requests.Count
    $payload = Join-Path $temp 'payload'
    $manifest = Save-DeployRepositoryPayload $state $payload $root
    Assert ($script:requests.Count - $before -eq 1 -and $script:requests[-1].path -eq 'App/TechMaster-Deploy.ps1') 'Only changed file is downloaded; unchanged files pass Git-hash verification'
    Assert ($manifest.source.commit -ceq $script:commit -and (Test-Path (Join-Path $payload 'TechMaster Deploy.exe'))) 'Public payload enters existing manifest and launcher flow'
    $script:text['App/TechMaster-Deploy.ps1'] = '# tampered'
    Expect-Failure { Get-DeployRepositoryBlob (@($state.files | Where-Object { $_.path -eq 'App/TechMaster-Deploy.ps1' })[0]) } 'không khớp'
    $script:text['version.txt'] = '9.9.9.9'
    Expect-Failure { Get-DeployOnlineRelease } 'không khớp'
    Reset-Remote
    $script:index.version = '1.1.4.0'
    Expect-Failure { Get-DeployOnlineRelease } 'Số phiên bản không khớp'
    Reset-Remote
    $script:index.files[0].mode = '120000'
    Expect-Failure { Get-DeployOnlineRelease } 'không hợp lệ'
    Assert ($script:apiCalls -eq 0) 'Invalid public metadata never falls back to bypass validation'
    Reset-Remote
    $script:index.files += $script:index.files[0]
    Expect-Failure { Get-DeployOnlineRelease } 'không hợp lệ'
    Reset-Remote
    $script:index.files[0].path = 'BienBan/BienBan-Config.json'
    Expect-Failure { Get-DeployOnlineRelease } 'ngoài phạm vi'
    Reset-Remote
    $script:index.files = @($script:index.files | Where-Object { $_.path -ne 'version.txt' })
    Expect-Failure { Get-DeployOnlineRelease } 'không đầy đủ'
    Reset-Remote
    $script:publicBlocked = $true
    $fallback = Get-DeployOnlineRelease ('a' * 40)
    Assert ($fallback.fallback -and $fallback.known -ceq ('a' * 40) -and $script:apiCalls -eq 1) 'Private/unavailable public transport retains API fallback with known revision'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "PASS: $script:checks public updater assertions; no API required, pinned raw files, hash checks and changed-file reuse."
