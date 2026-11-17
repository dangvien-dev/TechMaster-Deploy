# Shared, noninteractive updater. Importing this file does not modify the app.
$script:DeployProduct = 'TechMaster.Deploy'
$script:DeployRepository = 'dangvien-dev/TechMaster-Deploy'
$script:DeployBranch = 'main'

function Assert-DeployPath([string]$path, [switch]$Manifest) {
    if ($Manifest -and $path -ceq 'update-package.json') { return }
    if (-not $path -or $path.Contains('\') -or $path.Contains(':') -or $path.StartsWith('/')) { throw "Đường dẫn gói không hợp lệ: $path" }
    foreach ($part in ($path -split '/')) {
        if (-not $part -or $part -in '.', '..' -or $part -match '[.\s]$|[\x00-\x1f<>"|?*]' -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Đường dẫn gói không hợp lệ: $path" }
    }
    $allowed = $path -match '^(App|Office|KichHoat|FixClone|BienBan)/[^/]+\.(ps1|cs|ico|svg|html|bat|xml|manifest|md)$' -or
        $path -in 'README.md', 'PROGRESS.md', 'CHANGELOG.md', 'RELEASING.md', 'version.txt', 'TechMaster Deploy.exe'
    if (-not $allowed -or $path -match '^BienBan/Logo\.' -or $path -eq 'App/desktop.ini') {
        throw "Tệp nằm ngoài phạm vi cập nhật chương trình: $path"
    }
}

function Assert-DeployRegularPath([string]$root, [string]$path = '') {
    $current = [IO.Path]::GetFullPath($root)
    if (Test-Path -LiteralPath $current) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Không cập nhật qua symbolic link / junction.' }
    }
    foreach ($part in ($path -split '/')) {
        if (-not $part) { continue }
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Không cập nhật qua symbolic link / junction: $path" }
        }
    }
}

function Get-DeployHash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }

function Read-DeployManifest([string]$path) {
    $m = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($m.product -cne $script:DeployProduct -or $m.schema -ne 1) { throw 'Gói không phải TechMaster Deploy hoặc sai định dạng.' }
    $v = $null
    if (-not [version]::TryParse([string]$m.version, [ref]$v)) { throw 'Số phiên bản gói không hợp lệ.' }
    if ($m.source -and ($m.source.repository -cne $script:DeployRepository -or $m.source.branch -cne $script:DeployBranch -or $m.source.commit -notmatch '^[0-9a-f]{40}$')) { throw 'Nguồn repo của gói không hợp lệ.' }
    if (@($m.files).Count -lt 3 -or @($m.files).Count -gt 500) { throw 'Danh sách tệp trong gói không hợp lệ.' }
    $seen = @{}
    foreach ($f in $m.files) {
        $isDefault = $f.path -cin @('BienBan/Logo.svg', 'FixClone/Reinstall/_DOC-TRUOC.txt')
        if ($f.preserve -eq $true -and -not $isDefault) { throw 'Gói khai báo sai tệp cấu hình cần giữ.' }
        if ($isDefault -and $f.preserve -eq $true) { } else { Assert-DeployPath $f.path }
        if ($seen.ContainsKey($f.path) -or $f.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Tên tệp trùng hoặc thiếu SHA256 trong gói.' }
        $seen[$f.path] = $true
    }
    foreach ($required in 'version.txt', 'App/TechMaster-Deploy.ps1', 'TechMaster Deploy.exe') {
        if (-not $seen.ContainsKey($required)) { throw "Gói thiếu tệp bắt buộc: $required" }
    }
    return $m
}

function Get-DeployVersion([string]$root) {
    Assert-DeployRegularPath $root 'version.txt'
    $p = Join-Path $root 'version.txt'
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return [version]'0.0.0.0' }
    $v = $null
    if (-not [version]::TryParse(([IO.File]::ReadAllText($p)).Trim(), [ref]$v)) { throw 'version.txt hiện tại không hợp lệ.' }
    return $v
}

function Get-DeployCredentialPath {
    Join-Path $env:LOCALAPPDATA 'TechMaster Deploy/credentials/github-read.dpapi'
}

function Save-DeployGitHubToken([securestring]$token) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Chỉ lưu token bằng Windows DPAPI trên máy Windows dùng app.' }
    if (-not $token -or $token.Length -eq 0) { throw 'Chưa nhập token; không thay đổi quyền đã lưu.' }
    $path = Get-DeployCredentialPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    $encrypted = ConvertFrom-SecureString -SecureString $token -ErrorAction Stop
    [IO.File]::WriteAllText($path, $encrypted, [Text.UTF8Encoding]::new($false))
}

function Get-DeployGitHubHeaders {
    $headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $path = Get-DeployCredentialPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Token này chỉ đọc được bởi user Windows đã lưu.' }
        $secret = ConvertTo-SecureString ([IO.File]::ReadAllText($path)) -ErrorAction Stop
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            if ($plain -match '[\r\n]') { throw 'Token có ký tự không hợp lệ; nhập lại trong Quyền truy cập repo.' }
            $headers.Authorization = 'Bearer ' + $plain
        } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secret.Dispose() }
    }
    return $headers
}

function Invoke-DeployGitHub([string]$endpoint) {
    if ($endpoint -notmatch '^(commits/main|git/trees/[0-9a-f]{40}\?recursive=1|git/blobs/[0-9a-f]{40})$') { throw 'Endpoint repo không hợp lệ.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = Get-DeployGitHubHeaders
    try {
        Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $script:DeployRepository + '/' + $endpoint) `
            -Headers $headers -UserAgent 'TechMaster-Deploy-Updater' -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    } catch {
        # Do not include request headers or a token value in diagnostics.
        $status = 'không xác định'
        try { if ($null -ne $_.Exception.Response.StatusCode) { $status = [string][int]$_.Exception.Response.StatusCode } } catch {}
        throw "Không kết nối được máy chủ cập nhật (HTTP $status). Kiểm tra Internet và thử lại sau."
    } finally { $headers.Remove('Authorization') }
}

function Get-DeployGitBlobHash([byte[]]$bytes) {
    $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
    $sha = [Security.Cryptography.SHA1]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([byte[]]($header + $bytes)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# Public downloads never load or send a saved API token. Both destinations are
# fixed here, redirects are refused, and streaming reads enforce a size limit.
function Read-DeployPublicBytes([ValidateSet('Refs', 'File')][string]$kind, [string]$commit = '', [string]$path = '', [long]$limit = 20MB) {
    if ($limit -le 0 -or $limit -gt 20MB) { throw 'Giới hạn tải không hợp lệ.' }
    if ($kind -eq 'Refs') {
        $url = 'https://github.com/' + $script:DeployRepository + '.git/info/refs?service=git-upload-pack'
    } else {
        if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Mã phiên bản tải không hợp lệ.' }
        if ($path -cne 'update-source.json') { Assert-DeployPath $path }
        $escaped = @($path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        $url = 'https://raw.githubusercontent.com/' + $script:DeployRepository + '/' + $commit + '/' + $escaped
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($url)
    $request.Method = 'GET'; $request.UserAgent = 'TechMaster-Deploy-Updater'
    $request.AllowAutoRedirect = $false; $request.Timeout = 60000; $request.ReadWriteTimeout = 30000
    $request.Headers['Cache-Control'] = 'no-cache'
    $response = $null; $stream = $null; $memory = New-Object IO.MemoryStream
    try {
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt $limit) { throw 'Phản hồi tải không hợp lệ hoặc quá lớn.' }
        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] 16384
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $limit) { throw 'Dữ liệu tải vượt giới hạn.' }
            $memory.Write($buffer, 0, $read)
        }
        return ,$memory.ToArray()
    } catch {
        throw 'Không tải được dữ liệu cập nhật. Kiểm tra kết nối Internet và thử lại sau.'
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $memory.Dispose()
    }
}

function ConvertFrom-DeployGitRefs([byte[]]$bytes) {
    # Git protocol v0 pkt-lines; do not infer a commit from an HTML error page.
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $position = 0; $head = ''; $service = $false
    while ($position -lt $text.Length) {
        if ($position + 4 -gt $text.Length) { throw 'Thông tin phiên bản bị cắt ngắn.' }
        $prefix = $text.Substring($position, 4)
        if ($prefix -notmatch '^[a-fA-F0-9]{4}$') { throw 'Thông tin phiên bản không hợp lệ.' }
        $length = [Convert]::ToInt32($prefix, 16); $position += 4
        if ($length -eq 0) { continue }
        if ($length -lt 4 -or $position + $length - 4 -gt $text.Length) { throw 'Thông tin phiên bản bị cắt ngắn.' }
        $line = $text.Substring($position, $length - 4); $position += $length - 4
        if ($line -ceq "# service=git-upload-pack`n") { $service = $true; continue }
        $line = ($line -split [char]0, 2)[0].TrimEnd([char]10)
        if ($line -cmatch '^([0-9a-f]{40}) refs/heads/main$') {
            if ($head) { throw 'Thông tin phiên bản bị trùng.' }
            $head = $Matches[1]
        }
    }
    if (-not $service -or -not $head) { throw 'Chưa đọc được phiên bản ứng dụng.' }
    return $head
}

function Get-DeployPublicRelease([string]$commit, [byte[]]$indexBytes) {
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Mã phiên bản tải không hợp lệ.' }
    $index = [Text.Encoding]::UTF8.GetString($indexBytes).TrimStart([char]0xfeff) | ConvertFrom-Json -ErrorAction Stop
    $version = $null
    if ($index.schema -ne 1 -or $index.product -cne $script:DeployProduct -or $index.repository -cne $script:DeployRepository -or
        $index.branch -cne $script:DeployBranch -or -not [version]::TryParse([string]$index.version, [ref]$version)) { throw 'Danh sách cập nhật không hợp lệ.' }
    if (@($index.files).Count -lt 8 -or @($index.files).Count -gt 499) { throw 'Danh sách cập nhật không đầy đủ.' }
    $seen = @{}; $files = @(); $total = [long]0
    foreach ($f in $index.files) {
        Assert-DeployPath $f.path
        if ($f.path -ceq 'TechMaster Deploy.exe' -or $seen.ContainsKey($f.path) -or $f.sha -notmatch '^[0-9a-f]{40}$' -or
            $null -eq $f.size -or [long]$f.size -lt 0 -or [long]$f.size -gt 20MB -or $f.mode -notin '100644', '100755') { throw 'Danh sách cập nhật có tệp không hợp lệ.' }
        $total += [long]$f.size
        if ($total -gt 100MB) { throw 'Dữ liệu cập nhật vượt giới hạn.' }
        $seen[$f.path] = $true
        $files += [pscustomobject]@{ path = [string]$f.path; sha = [string]$f.sha; size = [long]$f.size; mode = [string]$f.mode; publicCommit = $commit }
    }
    foreach ($required in 'version.txt', 'App/TechMaster-Deploy.ps1', 'App/Launcher.cs', 'App/Launcher.manifest', 'App/TechMaster.ico', 'App/Update.Core.ps1', 'App/Update-App.ps1', 'App/Update-UI.ps1') {
        if (-not $seen.ContainsKey($required)) { throw "Danh sách cập nhật thiếu tệp: $required" }
    }
    $versionFile = @($files | Where-Object { $_.path -ceq 'version.txt' })[0]
    [byte[]]$versionBytes = Get-DeployRepositoryBlob $versionFile
    $actual = [Text.Encoding]::UTF8.GetString($versionBytes).TrimStart([char]0xfeff).Trim()
    if ($actual -cne $version.ToString()) { throw 'Số phiên bản không khớp danh sách cập nhật.' }
    return [pscustomobject]@{ unchanged = $false; version = $version.ToString(); commit = $commit; files = $files; versionBytes = $versionBytes; notes = '' }
}

function Get-DeployRepositoryBlob($file) {
    if ($file.sha -notmatch '^[0-9a-f]{40}$') { throw 'Git blob ID không hợp lệ.' }
    if ($file.publicCommit) {
        [byte[]]$bytes = Read-DeployPublicBytes -kind File -commit $file.publicCommit -path $file.path
        $size = [long]$file.size
    } else {
        $blob = Invoke-DeployGitHub ('git/blobs/' + $file.sha)
        if ($blob.sha -cne $file.sha -or $blob.encoding -cne 'base64' -or $null -eq $blob.size -or [long]$blob.size -gt 20MB -or [long]$blob.size -lt 0) { throw 'GitHub trả blob không hợp lệ.' }
        [byte[]]$bytes = [Convert]::FromBase64String([string]$blob.content)
        $size = [long]$blob.size
    }
    if ($bytes.Length -ne $size -or (Get-DeployGitBlobHash $bytes) -cne $file.sha) { throw "Nội dung tệp không khớp Git blob: $($file.path)" }
    return ,$bytes
}

function Get-DeployOnlineRelease([string]$knownCommit = '') {
    # Public repo: resolve main via Git, then use only immutable raw URLs.
    # Older/private repos can still use the authenticated API path.
    $publicAvailable = $false
    try {
        [byte[]]$refs = Read-DeployPublicBytes -kind Refs -limit 2MB
        $commit = ConvertFrom-DeployGitRefs $refs
        if ($knownCommit -and $commit -ceq $knownCommit) { return [pscustomobject]@{ unchanged = $true; commit = $commit } }
        [byte[]]$index = Read-DeployPublicBytes -kind File -commit $commit -path 'update-source.json' -limit 1MB
        $publicAvailable = $true
    } catch { Write-Verbose 'Đang thử kết nối cập nhật dự phòng.' }
    # Validation errors must stop the update, never silently bypass validation.
    if ($publicAvailable) { return Get-DeployPublicRelease $commit $index }
    return Get-DeployApiRelease $knownCommit
}

function Get-DeployApiRelease([string]$knownCommit = '') {
    $commit = Invoke-DeployGitHub ('commits/' + $script:DeployBranch)
    if ($commit.sha -notmatch '^[0-9a-f]{40}$' -or $commit.commit.tree.sha -notmatch '^[0-9a-f]{40}$') { throw 'GitHub không trả commit / tree hợp lệ.' }
    if ($knownCommit -and $commit.sha -ceq $knownCommit) {
        return [pscustomobject]@{ unchanged = $true; commit = $commit.sha }
    }
    $tree = Invoke-DeployGitHub ('git/trees/' + $commit.commit.tree.sha + '?recursive=1')
    if ($tree.sha -cne $commit.commit.tree.sha -or $tree.truncated -ne $false -or @($tree.tree).Count -gt 5000) { throw 'Danh sách tệp GitHub chưa đầy đủ; không cập nhật.' }
    $files = @()
    $seen = @{}
    foreach ($f in $tree.tree) {
        if ($f.type -ne 'blob') { continue }
        try { Assert-DeployPath $f.path } catch { continue }
        if ($seen.ContainsKey($f.path) -or $f.mode -notin '100644', '100755' -or $f.sha -notmatch '^[0-9a-f]{40}$' -or [long]$f.size -gt 20MB) { throw 'Repo có tệp trùng, link hoặc blob không hỗ trợ.' }
        $seen[$f.path] = $true
        $files += $f
    }
    foreach ($required in 'version.txt', 'App/TechMaster-Deploy.ps1', 'App/Launcher.cs', 'App/Launcher.manifest', 'App/TechMaster.ico', 'App/Update.Core.ps1', 'App/Update-App.ps1', 'App/Update-UI.ps1') {
        if (-not $seen.ContainsKey($required)) { throw "Repo chưa có mã cập nhật hoặc thiếu $required. Cần đẩy mã nguồn mới lên nhánh main; app hiện tại được giữ nguyên." }
    }
    if ($files.Count -gt 499) { throw 'Repo có quá nhiều tệp chương trình.' }
    $versionFile = @($files | Where-Object { $_.path -ceq 'version.txt' })[0]
    [byte[]]$versionBytes = Get-DeployRepositoryBlob $versionFile
    $v = $null
    $versionText = [Text.Encoding]::UTF8.GetString($versionBytes).TrimStart([char]0xfeff).Trim()
    if (-not [version]::TryParse($versionText, [ref]$v)) { throw 'version.txt trên repo không hợp lệ.' }
    [pscustomobject]@{
        unchanged = $false; version = $v.ToString(); commit = $commit.sha
        files = $files; versionBytes = $versionBytes
        notes = ([string]$commit.commit.message -replace '[\x00-\x08\x0b-\x1f]', '')
    }
}

function Build-DeployRepositoryLauncher([string]$payload) {
    $framework = if ([Environment]::Is64BitOperatingSystem) { 'Framework64' } else { 'Framework' }
    $compiler = Join-Path $env:WINDIR "Microsoft.NET/$framework/v4.0.30319/csc.exe"
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Không tìm thấy trình biên dịch .NET Framework của Windows để dựng launcher. Chưa thay đổi app.' }
    & $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 `
        ('/out:' + (Join-Path $payload 'TechMaster Deploy.exe')) `
        ('/win32icon:' + (Join-Path $payload 'App/TechMaster.ico')) `
        ('/win32manifest:' + (Join-Path $payload 'App/Launcher.manifest')) `
        (Join-Path $payload 'App/Launcher.cs') | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $payload 'TechMaster Deploy.exe'))) { throw 'Không build được launcher từ repo; chưa thay đổi app.' }
}

function Save-DeployRepositoryPayload($release, [string]$payload, [string]$installedRoot, [scriptblock]$Progress = $null) {
    if ($release.unchanged -or $release.commit -notmatch '^[0-9a-f]{40}$') { throw 'Chưa có snapshot repo mới để cài.' }
    if (Test-Path -LiteralPath $payload) { throw 'Thư mục chuẩn bị repo đã tồn tại.' }
    New-Item -ItemType Directory -Path $payload | Out-Null
    $total = [long]0
    $completedFiles = 0
    foreach ($f in $release.files) {
        if ($Progress) { & $Progress $completedFiles @($release.files).Count $f.path }
        Assert-DeployPath $f.path
        if ($f.path -ceq 'TechMaster Deploy.exe') { throw 'Nguồn repo phải dùng Launcher.cs thay cho exe không kiểm soát.' }
        Assert-DeployRegularPath $installedRoot $f.path
        $existing = Join-Path $installedRoot $f.path
        [byte[]]$bytes = @()
        if ($f.path -ceq 'version.txt') { $bytes = $release.versionBytes }
        elseif ((Test-Path -LiteralPath $existing -PathType Leaf) -and (Get-DeployGitBlobHash ([IO.File]::ReadAllBytes($existing))) -ceq $f.sha) { $bytes = [IO.File]::ReadAllBytes($existing) }
        else { $bytes = Get-DeployRepositoryBlob $f }
        if ((Get-DeployGitBlobHash $bytes) -cne $f.sha) { throw "Snapshot không khớp nội dung: $($f.path)" }
        $total += $bytes.Length
        if ($total -gt 100MB) { throw 'Snapshot repo quá lớn.' }
        $target = Join-Path $payload $f.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        [IO.File]::WriteAllBytes($target, $bytes)
        $completedFiles++
        if ($Progress) { try { & $Progress $completedFiles @($release.files).Count } catch {} }
    }
    # Compile with our installed updater code; never execute a downloaded build script.
    Build-DeployRepositoryLauncher $payload
    $files = @(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
        [pscustomobject]@{ path = $_.FullName.Substring($payload.Length + 1).Replace('\', '/'); sha256 = (Get-DeployHash $_.FullName); preserve = $false }
    })
    $m = [pscustomobject]@{
        schema = 1; product = $script:DeployProduct; version = $release.version; notes = $release.notes
        source = [pscustomobject]@{ repository = $script:DeployRepository; branch = $script:DeployBranch; commit = $release.commit; dirty = $false }
        files = $files
    }
    Write-DeployJson $m (Join-Path $payload 'update-package.json')
    return (Read-DeployManifest (Join-Path $payload 'update-package.json'))
}

function Assert-DeployToolsClosed([string]$root, [int]$ignoreId = 0) {
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='cmd.exe' OR Name='TechMaster Deploy.exe'" -ErrorAction Stop)
    foreach ($p in $processes) {
        if ($p.ProcessId -in @($PID, $ignoreId) -or -not $p.CommandLine) { continue }
        $command = [string]$p.CommandLine
        if ($command -match '(?i)-EncodedCommand\s+"?([A-Za-z0-9+/=]{1,65536})') {
            try { $command += ' ' + [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1])) } catch {}
        }
        if ($command.IndexOf($root, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Còn cửa sổ công cụ TechMaster đang mở (PID $($p.ProcessId)). Đóng cửa sổ đó rồi cập nhật lại."
        }
    }
}

function New-DeployArchive([string]$directory, [string]$zipPath) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $directory = [IO.Path]::GetFullPath($directory).TrimEnd([char[]]@('\','/'))
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in (Get-ChildItem -LiteralPath $directory -Recurse -File)) {
            $relative = $file.FullName.Substring($directory.Length + 1).Replace('\','/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }
}

function Expand-DeployPackage([string]$zipPath, [string]$work, [string]$expectedHash = '') {
    if ((Get-Item -LiteralPath $zipPath -ErrorAction Stop).Length -gt 100MB) { throw 'Gói cập nhật vượt quá 100 MB.' }
    if ($expectedHash -and (Get-DeployHash $zipPath) -ne $expectedHash.ToLowerInvariant()) { throw 'SHA256 của bản tải về không khớp; không cài.' }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $work) { throw 'Thư mục chuẩn bị gói đã tồn tại.' }
    New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($zip.Entries.Count -gt 600) { throw 'ZIP chứa quá nhiều mục.' }
        $prefix = 'TechMaster-Deploy/'
        # .NET Framework's legacy ZIP writer emits Windows backslashes. Normalize
        # only entry separators; manifest paths still use the strict allowlist.
        $manifestEntry = @($zip.Entries | Where-Object { $_.FullName.Replace('\','/') -ceq ($prefix + 'update-package.json') })
        if ($manifestEntry.Count -ne 1 -or $manifestEntry[0].Length -gt 1MB) { throw 'ZIP thiếu manifest cập nhật TechMaster Deploy.' }
        $mp = Join-Path $work 'update-package.json'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($manifestEntry[0], $mp)
        $manifest = Read-DeployManifest $mp
        $declared = @{}
        foreach ($f in $manifest.files) { $declared[$f.path] = $f }
        $seen = @{}
        $total = [long]0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if (-not $name.StartsWith($prefix, [StringComparison]::Ordinal)) { throw 'ZIP chứa tệp ngoài thư mục TechMaster-Deploy.' }
            if (($entry.ExternalAttributes -shr 16 -band 0xF000) -eq 0xA000) { throw 'ZIP chứa symbolic link.' }
            if ($name -ceq ($prefix + 'update-package.json')) { continue }
            $relative = $name.Substring($prefix.Length)
            if (-not $relative -or $relative.EndsWith('/')) {
                if ($relative -and $relative -notmatch '^(App|Office|KichHoat|FixClone|BienBan)/$') { throw 'Thư mục không hợp lệ trong ZIP.' }
                continue
            }
            if (-not $declared.ContainsKey($relative) -or $seen.ContainsKey($relative)) { throw "Tệp không khai báo hoặc trùng trong ZIP: $relative" }
            $seen[$relative] = $true
            $total += $entry.Length
            if ($entry.Length -gt 20MB -or $total -gt 100MB) { throw 'Dữ liệu giải nén vượt giới hạn.' }
            $target = Join-Path $work $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
            if ((Get-DeployHash $target) -ne $declared[$relative].sha256.ToLowerInvariant()) { throw "SHA256 tệp không khớp: $relative" }
        }
        if ($seen.Count -ne $declared.Count) { throw 'ZIP thiếu tệp đã khai báo.' }
        if ((Get-DeployVersion $work) -ne [version]$manifest.version) { throw 'Phiên bản trong ZIP không khớp manifest.' }
        return $manifest
    } finally { $zip.Dispose() }
}

function Get-DeployUpdatePlan([string]$root, [string]$payload) {
    Assert-DeployRegularPath $root
    Assert-DeployRegularPath $root 'update-package.json'
    Assert-DeployRegularPath $payload 'update-package.json'
    $next = Read-DeployManifest (Join-Path $payload 'update-package.json')
    $current = Get-DeployVersion $root
    $old = $null
    if (Test-Path -LiteralPath (Join-Path $root 'update-package.json') -PathType Leaf) { $old = Read-DeployManifest (Join-Path $root 'update-package.json') }
    $newCommit = $next.source -and (-not $old -or -not $old.source -or $next.source.commit -cne $old.source.commit)
    if ([version]$next.version -lt $current -or ([version]$next.version -eq $current -and -not $newCommit)) { throw "Bản $($next.version) không mới hơn bản $current. Dùng Quay lại để khôi phục phiên bản trước." }
    $oldMap = @{}
    $oldManifest = Join-Path $root 'update-package.json'
    if (Test-Path -LiteralPath $oldManifest) {
        $old = Read-DeployManifest $oldManifest
        if ([version]$old.version -ne $current) { throw 'Manifest và version.txt hiện tại không khớp.' }
        foreach ($f in $old.files) { if ($f.preserve -ne $true) { $oldMap[$f.path] = $f.sha256 } }
    }
    $newMap = @{}
    $changes = @()
    foreach ($f in $next.files) {
        if ($f.preserve -eq $true) { continue }
        Assert-DeployRegularPath $payload $f.path
        $newMap[$f.path] = $f.sha256
        Assert-DeployRegularPath $root $f.path
        $target = Join-Path $root $f.path
        $exists = Test-Path -LiteralPath $target -PathType Leaf
        $hash = if ($exists) { Get-DeployHash $target } else { '' }
        if ($hash -eq $f.sha256) { continue }
        if ((Test-Path -LiteralPath $oldManifest) -and $exists -and (-not $oldMap.ContainsKey($f.path) -or $hash -ne $oldMap[$f.path])) {
            throw "Tệp chương trình đã được sửa riêng, không ghi đè: $($f.path)"
        }
        $changes += [pscustomobject]@{ path = $f.path; beforeExists = $exists; beforeHash = $hash; afterHash = $f.sha256 }
    }
    foreach ($path in $oldMap.Keys) {
        if ($newMap.ContainsKey($path)) { continue }
        Assert-DeployRegularPath $root $path
        $target = Join-Path $root $path
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $hash = Get-DeployHash $target
            if ($hash -ne $oldMap[$path]) { throw "Tệp đã sửa riêng, không xoá: $path" }
            $changes += [pscustomobject]@{ path = $path; beforeExists = $true; beforeHash = $hash; afterHash = '' }
        }
    }
    $changes += [pscustomobject]@{ path = 'update-package.json'; beforeExists = (Test-Path -LiteralPath $oldManifest -PathType Leaf); beforeHash = $(if (Test-Path -LiteralPath $oldManifest -PathType Leaf) { Get-DeployHash $oldManifest } else { '' }); afterHash = (Get-DeployHash (Join-Path $payload 'update-package.json')) }
    [pscustomobject]@{ from = $current.ToString(); to = [string]$next.version; changes = $changes; firstUpdate = (-not (Test-Path -LiteralPath $oldManifest)) }
}

function Write-DeployJson($value, [string]$path) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false)) }

function Set-DeployFile([string]$source, [string]$target) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $temp = $target + '.tm-update-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::Copy($source, $temp)
        if ([IO.File]::Exists($target)) {
            try { [IO.File]::Replace($temp, $target, [NullString]::Value) }
            catch {
                $cause = $_.Exception.GetBaseException()
                if ($cause -isnot [NotSupportedException] -and ($cause.HResult -band 0xffff) -notin 1, 50) { throw }
                # Some portable drives do not support ReplaceFile. Keep a local
                # rename fallback in addition to the already verified full backup.
                $old = $target + '.tm-old-' + [guid]::NewGuid().ToString('N')
                [IO.File]::Move($target, $old)
                try { [IO.File]::Move($temp, $target) }
                catch { if (-not [IO.File]::Exists($target)) { [IO.File]::Move($old, $target) }; throw }
                finally { if ([IO.File]::Exists($old) -and [IO.File]::Exists($target)) { [IO.File]::Delete($old) } }
            }
        }
        else { [IO.File]::Move($temp, $target) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Restore-DeployFiles([string]$root, [string]$backup, $changes) {
    # Validate the entire backup before modifying any target.
    foreach ($f in $changes) {
        Assert-DeployPath $f.path -Manifest
        Assert-DeployRegularPath $root $f.path
        Assert-DeployRegularPath $backup ('before/' + $f.path)
        if ($f.beforeExists -and (Get-DeployHash (Join-Path $backup ('before/' + $f.path))) -ne $f.beforeHash) { throw "Bản sao lưu không khớp: $($f.path)" }
    }
    foreach ($f in $changes) {
        $target = Join-Path $root $f.path
        if ($f.beforeExists) {
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Get-DeployHash $target) -eq $f.beforeHash) { continue }
            Set-DeployFile (Join-Path $backup ('before/' + $f.path)) $target
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) { [IO.File]::Delete($target) }
    }
}

function Install-DeployUpdate([string]$root, [string]$payload) {
    Assert-DeployRegularPath $root '.updates'
    $store = Join-Path $root '.updates'
    New-Item -ItemType Directory -Path $store -Force | Out-Null
    $lock = [IO.File]::Open((Join-Path $store 'update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        # Rebuild the plan immediately before writing, rather than trusting a stale UI plan.
        $plan = Get-DeployUpdatePlan $root $payload
        foreach ($f in $plan.changes) {
            if ($f.afterHash -and (Get-DeployHash (Join-Path $payload $f.path)) -ne $f.afterHash) { throw "Gói đã thay đổi sau khi xác minh: $($f.path)" }
        }
        $backup = Join-Path $store ((Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $backup | Out-Null
        foreach ($f in $plan.changes) {
            if ($f.beforeExists) {
                $dest = Join-Path $backup ('before/' + $f.path)
                New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                [IO.File]::Copy((Join-Path $root $f.path), $dest)
                if ((Get-DeployHash $dest) -ne $f.beforeHash) { throw 'Tệp đã thay đổi trong lúc sao lưu; chưa cài cập nhật.' }
            }
        }
        $receipt = [pscustomobject]@{ schema = 1; product = $script:DeployProduct; from = $plan.from; to = $plan.to; date = (Get-Date).ToString('o'); status = 'prepared'; changes = @($plan.changes) }
        $receiptPath = Join-Path $backup 'receipt.json'
        Write-DeployJson $receipt $receiptPath
        try {
            foreach ($f in $plan.changes) {
                $target = Join-Path $root $f.path
                if ($f.afterHash) { Set-DeployFile (Join-Path $payload $f.path) $target }
                else { [IO.File]::Delete($target) }
            }
            foreach ($f in $plan.changes) {
                if ($f.afterHash -and (Get-DeployHash (Join-Path $root $f.path)) -ne $f.afterHash) { throw 'Không xác minh được tệp sau cập nhật.' }
            }
            $receipt.status = 'installed'
            Write-DeployJson $receipt $receiptPath
        } catch {
            $originalError = $_.Exception.Message
            try { Restore-DeployFiles $root $backup $plan.changes; $receipt.status = 'failed-restored'; Write-DeployJson $receipt $receiptPath }
            catch { throw "Cập nhật lỗi và chưa khôi phục xong. Giữ bản sao lưu tại $backup. Lỗi: $originalError; $($_.Exception.Message)" }
            throw "Cập nhật lỗi; đã khôi phục bản cũ. $originalError"
        }
        return $backup
    } finally { $lock.Dispose() }
}

function Get-DeployHistory([string]$root) {
    Assert-DeployRegularPath $root '.updates'
    $store = Join-Path $root '.updates'
    if (-not (Test-Path -LiteralPath $store)) { return }
    foreach ($dir in (Get-ChildItem -LiteralPath $store -Directory | Sort-Object Name -Descending)) {
        Assert-DeployRegularPath $store $dir.Name
        $path = Join-Path $dir.FullName 'receipt.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $r = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.product -cne $script:DeployProduct -or $r.schema -ne 1) { throw 'Lịch sử cập nhật không hợp lệ.' }
        [pscustomobject]@{ From = $r.from; To = $r.to; Date = $r.date; Status = $r.status; Backup = $dir.FullName }
    }
}

function Undo-DeployUpdate([string]$root, [string]$backup) {
    Assert-DeployRegularPath $root '.updates'
    $store = [IO.Path]::GetFullPath((Join-Path $root '.updates'))
    if ([IO.Path]::GetFullPath((Split-Path -Parent $backup)) -ne $store) { throw 'Bản sao lưu không nằm trong lịch sử ứng dụng này.' }
    Assert-DeployRegularPath $store (Split-Path -Leaf $backup)
    $lock = [IO.File]::Open((Join-Path $store 'update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $r = Get-Content -LiteralPath (Join-Path $backup 'receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.product -cne $script:DeployProduct -or $r.schema -ne 1 -or $r.status -ne 'installed' -or [version]$r.to -ne (Get-DeployVersion $root)) { throw 'Bản sao lưu không khớp phiên bản đang dùng.' }
        foreach ($f in $r.changes) {
            Assert-DeployPath $f.path -Manifest
            Assert-DeployRegularPath $root $f.path
            $target = Join-Path $root $f.path
            if ($f.afterHash) {
                if ((Get-DeployHash $target) -ne $f.afterHash) { throw "Tệp đã thay đổi sau cập nhật; không ghi đè khi quay lại: $($f.path)" }
            } elseif (Test-Path -LiteralPath $target) { throw "Tệp đã được tạo lại; không xoá khi quay lại: $($f.path)" }
        }
        Restore-DeployFiles $root $backup $r.changes
        $r.status = 'rolled-back'
        Write-DeployJson $r (Join-Path $backup 'receipt.json')
    } finally { $lock.Dispose() }
}
