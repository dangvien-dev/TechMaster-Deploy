# Real ZIP/file transactions in a disposable folder; no network or Windows app execution.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$script:checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $caught = ''
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -match $pattern) "Expected $pattern; got: $caught"
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
function New-TestPayload([string]$path, [string]$version, [switch]$Old) {
    Put (Join-Path $path 'version.txt') $version
    Put (Join-Path $path 'App/TechMaster-Deploy.ps1') ('# app ' + $version)
    Put (Join-Path $path 'TechMaster Deploy.exe') 'fake launcher; never executed'
    Put (Join-Path $path 'BienBan/Logo.svg') 'default release logo'
    if ($Old) { Put (Join-Path $path 'App/Obsolete.ps1') 'old file' }
    else { Put (Join-Path $path 'App/Added.ps1') 'new file' }
    $files = @(Get-ChildItem -LiteralPath $path -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($path.Length + 1).Replace('\', '/')
        [pscustomobject]@{ path = $relative; sha256 = (Get-DeployHash $_.FullName); preserve = ($relative -eq 'BienBan/Logo.svg') }
    })
    Write-DeployJson ([pscustomobject]@{ schema = 1; product = 'TechMaster.Deploy'; version = $version; files = $files }) (Join-Path $path 'update-package.json')
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-updates-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $stage = Join-Path $temp 'stage'
    $payload = Join-Path $stage 'TechMaster-Deploy'
    New-TestPayload $payload '1.2.0.0'
    $zipPath = Join-Path $temp 'release.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
    $extracted = Join-Path $temp 'extracted'
    $m = Expand-DeployPackage $zipPath $extracted (Get-DeployHash $zipPath)
    Assert ($m.version -eq '1.2.0.0' -and (Get-DeployVersion $extracted) -eq [version]'1.2.0.0') 'Valid ZIP extracted and all content hashes verified'
    Expect-Failure { Expand-DeployPackage $zipPath (Join-Path $temp 'wrong-sha') ('0' * 64) } 'SHA256'
    Expect-Failure { Expand-DeployPackage $zipPath $extracted } 'đã tồn tại'
    foreach ($badPath in @('../outside.ps1', 'App/../../outside.ps1', 'App\evil.ps1', 'App/a:stream.ps1', 'App/CON.ps1', 'App/file.ps1 ', 'BienBan/BienBan-Config.json', 'BienBan/Logo.svg', 'Office/ODT/setup.exe', 'FixClone/Reinstall/user.ps1', '.updates/receipt.json')) {
        Expect-Failure { Assert-DeployPath $badPath } 'không hợp lệ|ngoài phạm vi'
    }
    $evilZip = Join-Path $temp 'evil.zip'
    [IO.File]::Copy($zipPath, $evilZip)
    $archive = [IO.Compression.ZipFile]::Open($evilZip, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.CreateEntry('TechMaster-Deploy/../outside.ps1')
        $writer = New-Object IO.StreamWriter($entry.Open()); $writer.Write('evil'); $writer.Dispose()
    } finally { $archive.Dispose() }
    Expect-Failure { Expand-DeployPackage $evilZip (Join-Path $temp 'evil-out') } 'không khai báo'
    Assert (-not (Test-Path (Join-Path $temp 'outside.ps1'))) 'Zip traversal created nothing outside extraction root'
    $badContentZip = Join-Path $temp 'bad-content.zip'
    [IO.File]::Copy($zipPath, $badContentZip)
    $archive = [IO.Compression.ZipFile]::Open($badContentZip, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $archive.GetEntry('TechMaster-Deploy/App/TechMaster-Deploy.ps1').Delete()
        $entry = $archive.CreateEntry('TechMaster-Deploy/App/TechMaster-Deploy.ps1')
        $writer = New-Object IO.StreamWriter($entry.Open()); $writer.Write('changed bytes'); $writer.Dispose()
    } finally { $archive.Dispose() }
    Expect-Failure { Expand-DeployPackage $badContentZip (Join-Path $temp 'bad-content-out') } 'SHA256 tệp'

    $root = Join-Path $temp 'installed'
    New-TestPayload $root '1.1.0.0' -Old
    $userFiles = @('BienBan/BienBan-Config.json', 'BienBan/Logo.svg', 'BienBan/Logo.png', 'BienBan/BienBan/customer.html', 'KhoOffice/data.bin', 'Office/ODT/setup.exe', 'FixClone/Logs/user.log', 'FixClone/Reinstall/installer.exe', 'desktop.ini')
    foreach ($path in $userFiles) { Put (Join-Path $root $path) ('personal ' + $path) }
    $plan = Get-DeployUpdatePlan $root $extracted
    Assert (-not $plan.firstUpdate -and $plan.to -eq '1.2.0.0') 'Normal upgrade plan uses installed manifest'
    Assert ('TechMaster Deploy.exe' -notin $plan.changes.path) 'Unchanged launcher is not copied'
    Assert ('App/Obsolete.ps1' -in $plan.changes.path) 'Removed managed source is included in transaction'
    Put (Join-Path $root 'App/TechMaster-Deploy.ps1') 'custom local edit'
    Expect-Failure { Get-DeployUpdatePlan $root $extracted } 'sửa riêng'
    Put (Join-Path $root 'App/TechMaster-Deploy.ps1') '# app 1.1.0.0'
    $backup = Install-DeployUpdate $root $extracted
    Assert ((Get-DeployVersion $root) -eq [version]'1.2.0.0') 'Upgrade installed actual version files'
    Assert (-not (Test-Path (Join-Path $root 'App/Obsolete.ps1')) -and (Test-Path (Join-Path $root 'App/Added.ps1'))) 'Obsolete file removed; new file installed'
    foreach ($path in $userFiles) { Assert ([IO.File]::ReadAllText((Join-Path $root $path)) -ceq ('personal ' + $path)) "User data retained: $path" }
    $history = @(Get-DeployHistory $root)
    Assert ($history.Count -eq 1 -and $history[0].Status -eq 'installed' -and $history[0].To -eq '1.2.0.0') 'History records successful version transaction'
    Expect-Failure { Get-DeployUpdatePlan $root $extracted } 'không mới hơn'
    Put (Join-Path $root 'App/TechMaster-Deploy.ps1') 'edit after update'
    Expect-Failure { Undo-DeployUpdate $root $backup } 'thay đổi sau cập nhật'
    Put (Join-Path $root 'App/TechMaster-Deploy.ps1') '# app 1.2.0.0'
    Undo-DeployUpdate $root $backup
    Assert ((Get-DeployVersion $root) -eq [version]'1.1.0.0') 'Rollback restores prior version'
    Assert ((Test-Path (Join-Path $root 'App/Obsolete.ps1')) -and -not (Test-Path (Join-Path $root 'App/Added.ps1'))) 'Rollback restores deleted files and removes only updater-created files'
    Assert ((@(Get-DeployHistory $root))[0].Status -eq 'rolled-back') 'History marks completed rollback'
    foreach ($path in $userFiles) { Assert ([IO.File]::ReadAllText((Join-Path $root $path)) -ceq ('personal ' + $path)) "Rollback keeps user data: $path" }

    # Cause a failure after the first write; exercise actual automatic restore.
    $script:realSet = ${function:Set-DeployFile}
    $script:writeCount = 0
    function Set-DeployFile([string]$source, [string]$target) {
        $script:writeCount++
        if ($script:writeCount -eq 2) { throw 'simulated disk failure' }
        & $script:realSet $source $target
    }
    Expect-Failure { Install-DeployUpdate $root $extracted } 'đã khôi phục bản cũ'
    Assert ((Get-DeployVersion $root) -eq [version]'1.1.0.0' -and [IO.File]::ReadAllText((Join-Path $root 'App/TechMaster-Deploy.ps1')) -eq '# app 1.1.0.0') 'Partial upgrade failure restores original source and version'
    Set-Item Function:Set-DeployFile $script:realSet
    $hold = [IO.File]::Open((Join-Path $root '.updates/update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Expect-Failure { Install-DeployUpdate $root $extracted } 'used by another|another process|process cannot|sharing|being used|in use' }
    finally { $hold.Dispose() }
    Put (Join-Path $extracted 'App/TechMaster-Deploy.ps1') 'changed after validation'
    Expect-Failure { Install-DeployUpdate $root $extracted } 'Gói đã thay đổi'
    Assert ((Get-DeployVersion $root) -eq [version]'1.1.0.0') 'Staging drift aborts before any version change'
    Put (Join-Path $extracted 'App/TechMaster-Deploy.ps1') '# app 1.2.0.0'
    $newBackup = Install-DeployUpdate $root $extracted
    Put (Join-Path $newBackup 'before/version.txt') 'broken backup'
    Expect-Failure { Undo-DeployUpdate $root $newBackup } 'Bản sao lưu không khớp'
    Assert ((Get-DeployVersion $root) -eq [version]'1.2.0.0') 'Corrupt backup does not trigger partial rollback'
    Put (Join-Path $newBackup 'before/version.txt') '1.1.0.0'
    Undo-DeployUpdate $root $newBackup

    # Migration from a ZIP delivered before versioning existed.
    $legacy = Join-Path $temp 'legacy'
    Put (Join-Path $legacy 'App/TechMaster-Deploy.ps1') 'old unversioned app'
    Put (Join-Path $legacy 'BienBan/BienBan-Config.json') 'legacy config'
    $legacyPlan = Get-DeployUpdatePlan $legacy $extracted
    Assert ($legacyPlan.firstUpdate -and $legacyPlan.from -eq '0.0.0.0') 'First update can adopt legacy app with an explicit backup'
    $legacyBackup = Install-DeployUpdate $legacy $extracted
    Undo-DeployUpdate $legacy $legacyBackup
    Assert ([IO.File]::ReadAllText((Join-Path $legacy 'App/TechMaster-Deploy.ps1')) -eq 'old unversioned app' -and -not (Test-Path (Join-Path $legacy 'version.txt'))) 'Legacy rollback restores unversioned app exactly'
    Assert ([IO.File]::ReadAllText((Join-Path $legacy 'BienBan/BienBan-Config.json')) -eq 'legacy config') 'Migration and rollback preserve legacy config'

    # The actual UI starter must encode paths correctly, including Vietnamese,
    # spaces, apostrophes and characters that would be PowerShell syntax.
    $savedLocalAppData = $env:LOCALAPPDATA
    $savedSystemRoot = $env:SystemRoot
    try {
        $env:LOCALAPPDATA = Join-Path $temp 'local data'
        $env:SystemRoot = Join-Path $temp 'windows'
        $Root = Join-Path $temp "Người dùng's app"
        $chosenZip = Join-Path $temp "Bản mới's [1].zip"
        $script:officeRun = $null; $script:basicAppRun = $null; $script:mediaDownload = $null; $script:updateProcess = $null
        $form = [pscustomobject]@{ Enabled = $true }
        $tabs = [pscustomobject]@{ Enabled = $true }
        $header = [pscustomobject]@{ Enabled = $true }
        $updateTimer = [pscustomobject]@{ Active = $false }
        $updateTimer | Add-Member ScriptMethod Start { $this.Active = $true }
        function Set-Status($message) {}
        function Start-Process($FilePath, $ArgumentList, $WorkingDirectory) {
            $script:startedArguments = $ArgumentList
            [pscustomobject]@{ Handle = 1 }
        }
        $tokens = $null; $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Update-UI.ps1'), [ref]$tokens, [ref]$parseErrors)
        $busy = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-DeployUpdateBusy' }, $true)
        Invoke-Expression $busy.Extent.Text
        $starter = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-DeployUpdater' }, $true)
        # Surface errors in the test runner instead of opening a WinForms dialog.
        $starterText = [regex]::Replace($starter.Extent.Text, '(?m)^\s*\[void\]\[System.Windows.Forms.MessageBox\].*$', 'throw')
        $starterText = $starterText.Replace('$PSScriptRoot', ("'" + $PSScriptRoot.Replace("'", "''") + "'"))
        Invoke-Expression $starterText
        Start-DeployUpdater 'Local' $chosenZip
        $base64 = $script:startedArguments -replace '^.*-EncodedCommand ', ''
        $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($base64))
        Assert ($decoded.Contains("-Root '" + $Root.Replace("'", "''") + "'") -and $decoded.Contains("-PackagePath '" + $chosenZip.Replace("'", "''") + "'")) 'GUI starter preserves Unicode, whitespace and apostrophes without command injection'
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($decoded, [ref]$tokens, [ref]$parseErrors)
        Assert ($parseErrors.Count -eq 0 -and $form.Enabled -and -not $tabs.Enabled -and -not $header.Enabled -and $updateTimer.Active) 'Encoded updater command parses; controls are blocked while main window remains closable'
        Assert ($decoded.Contains("-CloseRequestPath '" + $script:updateCloseRequest.Replace("'", "''") + "'")) 'Updater receives the unique per-run close request path'
    } finally { $env:LOCALAPPDATA = $savedLocalAppData; $env:SystemRoot = $savedSystemRoot }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "PASS: $script:checks updater assertions; real ZIP, install, preservation and rollback transactions."
