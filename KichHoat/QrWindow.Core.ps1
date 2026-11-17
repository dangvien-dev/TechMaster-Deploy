# Opens a dedicated browser app window; never terminates a browser process.
function Test-CidBrowserExecutable([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        return $sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match '(?:^|,\s*)O=(Microsoft Corporation|Google LLC|Google Inc\.)(?:,|$)'
    } catch { return $false }
}

function Get-CidBrowserPath {
    $order = @('chrome.exe', 'msedge.exe')
    try {
        $choice = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop
        if ($choice.ProgId -like 'MSEdge*') { $order = @('msedge.exe', 'chrome.exe') }
    } catch {}
    foreach ($exe in $order) {
        foreach ($base in @('HKCU:\Software', 'HKLM:\Software', 'HKLM:\Software\WOW6432Node')) {
            try {
                $key = Get-Item -LiteralPath ($base + '\Microsoft\Windows\CurrentVersion\App Paths\' + $exe) -ErrorAction Stop
                $path = [string]$key.GetValue('')
                if (Test-CidBrowserExecutable $path) { return $path }
            } catch {}
        }
        $relative = if ($exe -eq 'chrome.exe') { 'Google/Chrome/Application/chrome.exe' } else { 'Microsoft/Edge/Application/msedge.exe' }
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if (-not $base) { continue }
            $path = Join-Path $base $relative
            if (Test-CidBrowserExecutable $path) { return $path }
        }
    }
    return $null
}

function Open-CidQrWindow([string]$template, [string]$iid, [string]$computer, [string]$product, [string]$portal, [string]$receiver) {
    if ($iid -notmatch '^[0-9]+$') { throw 'Installation ID không hợp lệ.' }
    if ($portal -notin 'https://visualsupport.microsoft.com/', 'https://aka.ms/WindowsActivate') { throw 'Portal không thuộc địa chỉ Microsoft được hỗ trợ.' }
    if ($receiver -and $receiver -notmatch '^http://[0-9.]+:[0-9]+/[a-f0-9]+/$') { throw 'Địa chỉ nhận CID không hợp lệ.' }
    $token = [guid]::NewGuid().ToString('N')
    $html = [IO.File]::ReadAllText($template)
    $html = $html.Replace('__IID__', $iid).Replace('__PCNAME__', [Net.WebUtility]::HtmlEncode($computer))
    $html = $html.Replace('__PRODUCT__', [Net.WebUtility]::HtmlEncode($product)).Replace('__URL__', [Net.WebUtility]::HtmlEncode($portal))
    $html = $html.Replace('__CIDURL__', $receiver).Replace('__QRSESSION__', $token)
    $path = Join-Path $env:TEMP ('TechMaster_QR_' + $token + '.html')
    [IO.File]::WriteAllText($path, $html, [Text.UTF8Encoding]::new($true))
    $session = [pscustomobject]@{ Token = $token; Path = $path; Handle = [long]0; Owned = $false }
    $browser = Get-CidBrowserPath
    if (-not $browser) { Start-Process -FilePath $path | Out-Null; return $session }
    try {
        if (-not ('TechMaster.QrWindow' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'QrWindow.cs') -ErrorAction Stop }
        $uri = [uri]$path
        $process = Start-Process -FilePath $browser -ArgumentList ('--app="{0}"' -f $uri.AbsoluteUri) -PassThru -ErrorAction Stop
        if ($null -ne $process) { $process.Dispose() }
    } catch {
        Write-Verbose $_.Exception.Message
        Start-Process -FilePath $path | Out-Null
        return $session
    }
    for ($i = 0; $i -lt 50; $i++) {
        $session.Handle = [TechMaster.QrWindow]::Capture($token)
        if ($session.Handle -ne 0) { $session.Owned = $true; break }
        Start-Sleep -Milliseconds 100
    }
    return $session
}

function Close-CidQrWindow($session) {
    if ($null -eq $session -or -not $session.Owned -or $session.Handle -eq 0) { return }
    try {
        if ([TechMaster.QrWindow]::Close($session.Handle, $session.Token)) {
            $session.Owned = $false
            Write-Host '  Đã đóng cửa sổ QR.' -ForegroundColor Green
            Remove-Item -LiteralPath $session.Path -Force -ErrorAction SilentlyContinue
        }
    } catch { Write-Verbose $_.Exception.Message }
}
