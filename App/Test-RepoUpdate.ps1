# GitHub responses are mocked; staging, hashes, install and rollback use real files.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$script:checks = 0
$script:realGitHub = ${function:Invoke-DeployGitHub}
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $errorText = ''
    try { & $action | Out-Null } catch { $errorText = $_.Exception.Message }
    Assert ($errorText -match $pattern) "Expected $pattern; got $errorText"
}
function Make-Remote([string]$version, [string]$commit) {
    $script:requests = @()
    $script:blobs = @{}
    $script:text = @{
        'version.txt' = $version; 'App/TechMaster-Deploy.ps1' = '# new app'
        'App/Launcher.cs' = '# same launcher source'; 'App/Launcher.manifest' = '<assembly />'
        'App/TechMaster.ico' = 'same icon'; 'App/Update.Core.ps1' = '# same core'
        'App/Update-App.ps1' = '# same entrypoint'; 'App/Update-UI.ps1' = '# same UI'
        'App/Build-Launcher.ps1' = 'throw "Never execute this downloaded build script"'
        'BienBan/Logo.svg' = 'remote default logo'; 'BienBan/BienBan-Config.json' = 'must not fetch this'
        'Office/ODT/setup.exe' = 'must not fetch this either'
    }
    $entries = @(foreach ($path in $script:text.Keys) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($script:text[$path])
        $sha = Get-DeployGitBlobHash $bytes
        $script:blobs[$sha] = [pscustomobject]@{ sha = $sha; encoding = 'base64'; size = $bytes.Length; content = [Convert]::ToBase64String($bytes) }
        [pscustomobject]@{ path = $path; type = 'blob'; mode = '100644'; size = $bytes.Length; sha = $sha }
    })
    $script:head = [pscustomobject]@{ sha = $commit; commit = [pscustomobject]@{ tree = [pscustomobject]@{ sha = ('d' * 40) }; message = 'Repo update fixture' } }
    $script:tree = [pscustomobject]@{ sha = ('d' * 40); truncated = $false; tree = $entries }
}
function Invoke-DeployGitHub([string]$endpoint) {
    $script:requests += $endpoint
    if ($endpoint -eq 'commits/main') { return $script:head }
    if ($endpoint -eq ('git/trees/' + ('d' * 40) + '?recursive=1')) { return $script:tree }
    if ($endpoint -match '^git/blobs/([0-9a-f]{40})$' -and $script:blobs.ContainsKey($Matches[1])) { return $script:blobs[$Matches[1]] }
    throw "Unexpected request: $endpoint"
}
function Build-DeployRepositoryLauncher([string]$payload) {
    $script:compileCount++
    [IO.File]::WriteAllText((Join-Path $payload 'TechMaster Deploy.exe'), 'compiled test launcher, never executed')
}
function Put([string]$path, [string]$content) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-repo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$savedLocalAppData = $env:LOCALAPPDATA
try {
    Assert ((Get-DeployGitBlobHash ([byte[]]@())) -ceq 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391') 'Git blob hash matches the canonical empty blob ID'
    Assert ((Get-DeployGitBlobHash ([Text.Encoding]::UTF8.GetBytes("hello`n"))) -ceq 'ce013625030ba8dba906f756967f9e9ca394464a') 'Git blob hash matches the canonical nonempty blob ID'
    $env:LOCALAPPDATA = Join-Path $temp 'credentials test'
    $headers = Get-DeployGitHubHeaders
    Assert (-not $headers.ContainsKey('Authorization')) 'Public repo does not require or invent a token'
    Expect-Failure { & $script:realGitHub 'https://other.example/token' } 'Endpoint repo'

    Make-Remote '1.2.0.0' ('b' * 40)
    $state = Get-DeployApiRelease ('b' * 40)
    Assert ($state.unchanged -and $script:requests.Count -eq 1) 'Same commit stops after one request without downloading files'
    $state = Get-DeployApiRelease ('a' * 40)
    Assert ($state.version -eq '1.2.0.0' -and $state.commit -ceq ('b' * 40)) 'Version, tree and blobs belong to a single resolved commit'
    Assert ('BienBan/Logo.svg' -notin $state.files.path -and 'BienBan/BienBan-Config.json' -notin $state.files.path -and 'Office/ODT/setup.exe' -notin $state.files.path) 'Repo credentials, personal configuration, logo and ODT are outside the download set'
    $script:tree.truncated = $true
    Expect-Failure { Get-DeployApiRelease } 'chưa đầy đủ'
    $script:tree.truncated = $false
    $versionEntry = @($script:tree.tree | Where-Object { $_.path -eq 'version.txt' })[0]
    $script:blobs[$versionEntry.sha].content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('9.9.9.9'))
    Expect-Failure { Get-DeployRepositoryBlob $versionEntry } 'không khớp'
    Make-Remote '1.2.0.0' ('b' * 40)
    $script:tree.tree = @($script:tree.tree | Where-Object { $_.path -ne 'version.txt' })
    Expect-Failure { Get-DeployApiRelease } 'version.txt'
    Make-Remote '1.2.0.0' ('b' * 40)
    (@($script:tree.tree | Where-Object { $_.path -eq 'App/Launcher.cs' }))[0].mode = '120000'
    Expect-Failure { Get-DeployApiRelease } 'link'
    Make-Remote '1.2.0.0' ('b' * 40)
    $state = Get-DeployApiRelease
    $root = Join-Path $temp 'installed'
    foreach ($f in $state.files) { Put (Join-Path $root $f.path) $script:text[$f.path] }
    Put (Join-Path $root 'version.txt') '1.1.0.0'
    Put (Join-Path $root 'App/TechMaster-Deploy.ps1') '# old app'
    Put (Join-Path $root 'TechMaster Deploy.exe') 'old launcher'
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        [pscustomobject]@{ path = $_.FullName.Substring($root.Length+1).Replace('\','/'); sha256 = (Get-DeployHash $_.FullName); preserve = $false }
    })
    $manifest = [pscustomobject]@{ schema = 1; product = 'TechMaster.Deploy'; version = '1.1.0.0'; files = $files; source = [pscustomobject]@{ repository = $script:DeployRepository; branch = 'main'; commit = ('a' * 40); dirty = $false } }
    Write-DeployJson $manifest (Join-Path $root 'update-package.json')
    Put (Join-Path $root 'BienBan/Logo.svg') 'my logo'
    Put (Join-Path $root 'BienBan/BienBan-Config.json') 'my config'
    Put (Join-Path $root 'Office/ODT/setup.exe') 'cached ODT'
    $script:compileCount = 0
    $beforeRequests = $script:requests.Count
    $payload = Join-Path $temp 'payload'
    $newManifest = Save-DeployRepositoryPayload $state $payload $root
    Assert ($script:requests.Count - $beforeRequests -eq 1) 'Only the changed app blob is downloaded; other source files are reused after Git-hash verification'
    Assert ($script:compileCount -eq 1) 'Launcher uses the installed compiler wrapper, never a downloaded build script'
    Assert ($newManifest.source.commit -ceq ('b' * 40) -and $newManifest.version -eq '1.2.0.0') 'Staged manifest records exact commit and version'
    $backup = Install-DeployUpdate $root $payload
    Assert ((Get-DeployVersion $root) -eq [version]'1.2.0.0') 'Repo snapshot installed through the real transaction engine'
    Assert ([IO.File]::ReadAllText((Join-Path $root 'BienBan/BienBan-Config.json')) -eq 'my config' -and [IO.File]::ReadAllText((Join-Path $root 'BienBan/Logo.svg')) -eq 'my logo') 'Repo update preserves configuration and custom logo'
    Assert ([IO.File]::ReadAllText((Join-Path $root 'Office/ODT/setup.exe')) -eq 'cached ODT') 'Repo update preserves cached ODT'
    Undo-DeployUpdate $root $backup
    Assert ((Get-DeployVersion $root) -eq [version]'1.1.0.0' -and [IO.File]::ReadAllText((Join-Path $root 'App/TechMaster-Deploy.ps1')) -eq '# old app') 'Real rollback restores prior source and version'

    Make-Remote '1.1.0.0' ('c' * 40)
    $sameVersionState = Get-DeployApiRelease
    $sameVersionPayload = Join-Path $temp 'same-version'
    $null = Save-DeployRepositoryPayload $sameVersionState $sameVersionPayload $root
    $samePlan = Get-DeployUpdatePlan $root $sameVersionPayload
    Assert ($samePlan.from -eq $samePlan.to) 'A new commit can update the same display version without claiming a downgrade'
    $backup2 = Install-DeployUpdate $root $sameVersionPayload
    Assert ((Read-DeployManifest (Join-Path $root 'update-package.json')).source.commit -ceq ('c' * 40)) 'Same-version update advances stored commit identity'
    Undo-DeployUpdate $root $backup2
    Assert ((Read-DeployManifest (Join-Path $root 'update-package.json')).source.commit -ceq ('a' * 40)) 'Same-version rollback restores original commit identity'
    Expect-Failure { Save-DeployRepositoryPayload $state $payload $root } 'đã tồn tại'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $dummy = ConvertTo-SecureString 'test-only-not-a-token' -AsPlainText -Force
        try { Expect-Failure { Save-DeployGitHubToken $dummy } 'Windows DPAPI' } finally { $dummy.Dispose() }
        Assert (-not (Test-Path (Get-DeployCredentialPath))) 'No plaintext or portable encrypted-token fallback is written on non-Windows hosts'
    }
    function Get-DeployGitHubHeaders { @{ Authorization = 'Bearer TEST-DUMMY-NOT-A-TOKEN' } }
    function Invoke-RestMethod {
        [CmdletBinding()]
        param([string]$Uri, [hashtable]$Headers, [string]$UserAgent, [switch]$UseBasicParsing, [int]$TimeoutSec)
        $script:requestedUri = $Uri
        $script:hadAuthorization = $Headers.ContainsKey('Authorization')
        $script:requestHeaders = $Headers
        throw 'Simulated failure containing TEST-DUMMY-NOT-A-TOKEN'
    }
    $requestError = ''
    try { & $script:realGitHub 'commits/main' | Out-Null } catch { $requestError = $_.Exception.Message }
    Assert ($script:requestedUri -ceq 'https://api.github.com/repos/dangvien-dev/TechMaster-Deploy/commits/main' -and $script:hadAuthorization) 'Private repo authorization is sent only to the fixed GitHub API endpoint'
    Assert ($requestError -match 'Không kết nối được máy chủ cập nhật' -and $requestError -notmatch 'TEST-DUMMY-NOT-A-TOKEN') 'Request errors do not expose authorization contents'
    Assert (-not $script:requestHeaders.ContainsKey('Authorization')) 'Authorization header is cleared after a request failure'
} finally { $env:LOCALAPPDATA = $savedLocalAppData; Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "PASS: $script:checks repo updater assertions; commit-pinned blobs, changed-file reuse, install and rollback."
