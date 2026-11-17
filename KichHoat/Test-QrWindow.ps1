# Exercises generated HTML and fallback paths without opening/closing a browser.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QrWindow.Core.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'QrWindow.cs')
$script:checks = 0
function Assert($condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $caught = ''
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -match $pattern) "Expected $pattern; got $caught"
}
function Get-CidBrowserPath { return $null }
function Start-Process($FilePath) { $script:openedPath = $FilePath }
$oldTemp = $env:TEMP
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-qr-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$env:TEMP = $temp
try {
    $tpl = Join-Path $PSScriptRoot 'QR-Template.html'
    $session = Open-CidQrWindow $tpl ('1' * 63) 'PC & <test>' 'Office' 'https://visualsupport.microsoft.com/' 'http://192.168.1.10:23456/abcdef123456/'
    $html = [IO.File]::ReadAllText($session.Path)
    Assert ($script:openedPath -eq $session.Path -and -not $session.Owned) 'Unsupported browsers open normally and are never marked as owned'
    Assert ($session.Token -match '^[a-f0-9]{32}$' -and $html.Contains('TMQR-' + $session.Token)) 'Each QR window has a unique matching title marker'
    Assert ($html.Contains('PC &amp; &lt;test&gt;') -and -not $html.Contains('PC & <test>')) 'Computer name is HTML-escaped'
    Assert ($html.Contains('class="portal" href="https://visualsupport.microsoft.com/"') -and $html.Contains('Mở portal Microsoft')) 'Main portal button points to the official activation page'
    Assert ($html.Contains('target="_blank" rel="noopener noreferrer"')) 'Portal opens separately from the QR window'
    Assert (-not ($html -match '__IID__|__PCNAME__|__PRODUCT__|__URL__|__CIDURL__|__QRSESSION__')) 'Template placeholders are all resolved'
    Close-CidQrWindow $session
    Assert ((Test-Path $session.Path) -and -not $session.Owned) 'Closing an unowned/default browser session does not close a browser or delete its page'
    $other = Open-CidQrWindow $tpl ('2' * 63) 'PC2' 'Windows' 'https://aka.ms/WindowsActivate' ''
    Assert ($other.Path -ne $session.Path -and $other.Token -ne $session.Token) 'Concurrent sessions cannot overwrite or close one another'
    Assert ([IO.File]::ReadAllText($other.Path).Contains('href="https://aka.ms/WindowsActivate"')) 'Windows uses its own official portal'
    Expect-Failure { Open-CidQrWindow $tpl '<script>' 'PC' 'Office' 'https://visualsupport.microsoft.com/' '' } 'Installation ID'
    Expect-Failure { Open-CidQrWindow $tpl '123' 'PC' 'Office' 'https://other.example/' '' } 'Portal'
    Expect-Failure { Open-CidQrWindow $tpl '123' 'PC' 'Office' 'https://visualsupport.microsoft.com/' 'javascript:bad' } 'CID'
    Expect-Failure { [TechMaster.QrWindow]::Capture('not-a-session') } 'Invalid QR window token'
    Expect-Failure { [TechMaster.QrWindow]::Close(1, 'not-a-session') } 'Invalid QR window token'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        Assert ([TechMaster.QrWindow]::Capture($session.Token) -eq 0 -and -not [TechMaster.QrWindow]::Close(1, $session.Token)) 'Non-Windows hosts never invoke native window operations'
    }
    $fake = Join-Path $temp 'chrome.exe'
    [IO.File]::WriteAllText($fake, 'not really a browser')
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
    Assert (-not (Test-CidBrowserExecutable $fake)) 'Unsigned executable cannot be launched as the owned QR browser'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Browser, O=Google LLC, C=US' } } }
    Assert (Test-CidBrowserExecutable $fake) 'Valid Google publisher is supported'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Browser, O=Other Company, C=US' } } }
    Assert (-not (Test-CidBrowserExecutable $fake)) 'Other publishers are not treated as Chrome/Edge'
} finally { $env:TEMP = $oldTemp; Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "PASS: $script:checks QR-window assertions; generated portal links and owned-window safety guards."
