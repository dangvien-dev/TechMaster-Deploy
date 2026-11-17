# Execute the production phone/CID flow in a child shell with all OS/browser/
# licensing calls replaced by fakes. The real script file is never modified.
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-cid-flow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    foreach ($file in 'Activation.Core.ps1', 'QrWindow.Core.ps1', 'QR-Template.html') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $temp
    }
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Kich-Hoat.ps1'))
    $begin = $source.IndexOf('# ---------- Quyền Admin ----------')
    $end = $source.IndexOf('# ---------- CHẾ ĐỘ TEST ----------')
    if ($begin -lt 0 -or $end -le $begin) { throw 'Cannot isolate the Windows-only privilege check safely.' }
    $result = Join-Path $temp 'result.json'
    $fake = @'
$global:CidFlow = [pscustomobject]@{ Events = @(); Portal = ''; Active = $false }
$global:CidLicense = [pscustomobject]@{ Name = 'Office test'; ID = 'fixture'; ApplicationID = '0ff1ce15-a989-479d-af46-f275c6370663'; PartialProductKey = 'ABCDE'; LicenseStatus = 2; OfflineInstallationId = ('1' * 63) }
function Get-LicProducts { $global:CidLicense }
function Get-CimInstance { [pscustomobject]@{ Name = 'fake service' } }
function Invoke-CimMethod {}
function Set-Clipboard {}
function Confirm-Box {$true}
function Select-DeployOption {'Primary'}
function Remove-NetFirewallRule {}
function Read-Host($Prompt) {
    if ($Prompt -match 'Làm portal') { return '1' }
    if ($Prompt -match 'Nhấn Enter') { return '' }
    throw ('Unexpected interactive prompt: ' + $Prompt)
}
function Start-CidReceiver {
    $listener = [pscustomobject]@{}
    $listener | Add-Member ScriptMethod Stop {}
    $listener | Add-Member ScriptMethod Close {}
    @{ Url = 'http://192.168.1.10:23456/abcdef123456/'; Listener = $listener }
}
function Open-CidQrWindow($template, $iid, $computer, $product, $portal, $receiver) {
    $global:CidFlow.Events += 'open'
    $global:CidFlow.Portal = $portal
    return [pscustomobject]@{ Fixture = $true }
}
function Wait-Cid($receiver) { $global:CidFlow.Events += 'receive'; return ('2' * 48) }
function Close-CidQrWindow($window) {
    if (-not $window.Fixture) { throw 'QR session lost' }
    $global:CidFlow.Events += 'close'
}
function Invoke-VerifiedLicenseActivation($license, $method, $iid, $cid) {
    if ($method -eq 'Activate') { return [pscustomobject]@{ State = 'Failed'; Detail = 'expected fixture offline flow' } }
    if (($global:CidFlow.Events -join ',') -ne 'open,receive,close' -or $cid -ne ('2' * 48)) { throw 'QR not closed before CID submission' }
    $global:CidFlow.Events += 'activate'
    $global:CidFlow.Active = $true
    $global:CidLicense.LicenseStatus = 1
    [pscustomobject]@{ State = 'Activated'; Detail = 'fixture only' }
}
'@
    $testSource = $source.Substring(0, $begin) + $fake + "`n" + $source.Substring($end)
    $testSource += "`n[IO.File]::WriteAllText('" + $result.Replace("'", "''") + "', (`$global:CidFlow | ConvertTo-Json), [Text.UTF8Encoding]::new(`$false))`n"
    $runner = Join-Path $temp 'Kich-Hoat-Fixture.ps1'
    [IO.File]::WriteAllText($runner, $testSource, [Text.UTF8Encoding]::new($true))
    $engine = (Get-Process -Id $PID).Path
    $stdout = Join-Path $temp 'out.txt'; $stderr = Join-Path $temp 'err.txt'
    $p = Start-Process -FilePath $engine -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Product Office' -f $runner) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    if ($p.ExitCode -ne 0 -or -not (Test-Path $result)) { throw ('Workflow fixture failed: ' + [IO.File]::ReadAllText($stderr)) }
    $state = Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
    if (($state.Events -join ',') -ne 'open,receive,close,activate' -or -not $state.Active -or $state.Portal -cne 'https://visualsupport.microsoft.com/') { throw 'Wrong portal or QR close/CID order.' }
    Write-Host 'PASS: actual phone activation flow opens official portal QR, receives CID, closes QR, then submits activation; all external effects mocked.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
