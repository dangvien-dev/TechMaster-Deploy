# UI/process operations are simulated; close-request markers use real files.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$script:checks = 0
function Assert($condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $caught = ''
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -match $pattern) "Expected $pattern; got $caught"
}
function Import-Function([string]$path, [string]$name, [string]$scriptRoot) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Source syntax error' }
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    return [scriptblock]::Create($node.Extent.Text.Replace('$PSScriptRoot', ("'" + $scriptRoot.Replace("'", "''") + "'")))
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-close-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    . (Import-Function (Join-Path $PSScriptRoot 'Update-UI.ps1') 'Set-DeployUpdateBusy' $PSScriptRoot)
    . (Import-Function (Join-Path $PSScriptRoot 'Update-UI.ps1') 'Update-DeployUpdaterState' $PSScriptRoot)
    . (Import-Function (Join-Path $PSScriptRoot 'Update.Engine.ps1') 'Close-DeployForUpdate' $temp)
    function Set-Status($message) { $script:lastStatus = $message }
    function Reset-Fixture {
        $script:form = [pscustomobject]@{ IsEnabled = $true; Closed = $false; Activated = $false }
        $script:form | Add-Member ScriptMethod Close { $this.Closed = $true }
        $script:form | Add-Member ScriptMethod Activate { $this.Activated = $true }
        $script:tabs = [pscustomobject]@{ IsEnabled = $true }
        $script:header = [pscustomobject]@{ IsEnabled = $true }
        $script:btnRefresh = [pscustomobject]@{ IsEnabled = $true }
        $script:Navigation = [pscustomobject]@{ IsEnabled = $true }
        $script:updateTimer = [pscustomobject]@{ Stopped = $false }
        $script:updateTimer | Add-Member ScriptMethod Stop { $this.Stopped = $true }
        $script:updateProcess = [pscustomobject]@{ HasExited = $false; Disposed = $false }
        $script:updateProcess | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
        $script:updateCloseRequest = Join-Path $temp 'close.request'
        if (Test-Path -LiteralPath $script:updateCloseRequest) { Remove-Item -LiteralPath $script:updateCloseRequest }
        $script:parentClosed = $false
    }
    Reset-Fixture
    Set-DeployUpdateBusy $true
    Assert ($form.IsEnabled -and -not $tabs.IsEnabled -and $header.IsEnabled -and -not $btnRefresh.IsEnabled) 'Busy state leaves window enabled while blocking actions'
    Update-DeployUpdaterState
    Assert (-not $form.Closed) 'No marker means app remains open during check, download and confirmation'
    [IO.File]::WriteAllText((Join-Path $temp 'window-state.json'),'{"state":"Preparing","message":"Downloading file 4 / 95"}')
    Update-DeployUpdaterState
    Assert ($script:lastStatus -match 'Downloading file 4 / 95' -and -not $form.Closed) 'Main status reflects worker progress while keeping the update window accessible'
    [IO.File]::WriteAllText($script:updateCloseRequest, 'not-a-close-command')
    Update-DeployUpdaterState
    Assert (-not $form.Closed) 'Unrecognized marker cannot close app'
    [IO.File]::WriteAllText($script:updateCloseRequest, 'close')
    Update-DeployUpdaterState
    Assert ($form.Closed -and $updateTimer.Stopped) 'UI timer closes its own form on an explicit close request'

    Reset-Fixture
    Set-DeployUpdateBusy $true
    [IO.File]::WriteAllText($script:updateCloseRequest, 'close')
    $script:updateProcess.HasExited = $true
    $oldProcess = $script:updateProcess
    Update-DeployUpdaterState
    Assert (-not $form.Closed -and $form.IsEnabled -and $tabs.IsEnabled -and $header.IsEnabled) 'Completed/cancelled updater unlocks UI instead of honoring a stale close marker'
    Assert ($oldProcess.Disposed -and $null -eq $script:updateProcess -and -not (Test-Path (Join-Path $temp 'close.request'))) 'Updater handle and marker cleaned after exit'

    function Get-Process { if (-not $script:missingParent) { $script:parent } }
    Reset-Fixture
    $ParentId = 1234
    $CloseRequestPath = Join-Path $temp 'close.request'
    $script:missingParent = $false
    $script:parent = [pscustomobject]@{ Disposed = $false; NativeCalls = 0; Waited = $false }
    $script:parent | Add-Member ScriptMethod CloseMainWindow { $this.NativeCalls++; return $false }
    $script:parent | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $script:parent | Add-Member ScriptMethod WaitForExit {
        param($timeout)
        $this.Waited = $true
        Update-DeployUpdaterState
        return $script:form.Closed
    }
    Close-DeployForUpdate
    Assert ($script:parentClosed -and $form.Closed -and $script:parent.Waited) 'Actual request file coordinates updater wait and UI-owned close'
    Assert ($script:parent.NativeCalls -eq 0) 'Handshake works even when native CloseMainWindow would reject the disabled/modal window'
    Assert ($script:parent.Disposed -and -not (Test-Path $CloseRequestPath)) 'Successful close releases process handle and removes marker'

    Reset-Fixture
    $script:parent.Disposed = $false
    $script:parent | Add-Member ScriptMethod WaitForExit { param($timeout) return $false } -Force
    Expect-Failure { Close-DeployForUpdate } 'chưa thoát hẳn'
    Assert (-not $script:parentClosed -and -not (Test-Path $CloseRequestPath)) 'Timeout does not authorize replacing files and cancels the close marker'
    $script:parent.Disposed = $false
    $CloseRequestPath = Join-Path $temp 'unrelated.txt'
    [IO.File]::WriteAllText($CloseRequestPath, 'keep')
    Expect-Failure { Close-DeployForUpdate } 'không hợp lệ'
    Assert ([IO.File]::ReadAllText($CloseRequestPath) -eq 'keep') 'Caller cannot overwrite/delete arbitrary files through close signaling'
    $CloseRequestPath = Join-Path $temp 'close.request'
    $script:missingParent = $true
    Close-DeployForUpdate
    Assert ($script:parentClosed -and -not (Test-Path $CloseRequestPath)) 'An already closed app does not block updates'
    $ParentId = 0; $CloseRequestPath = ''; $script:parentClosed = $false
    Close-DeployForUpdate
    Assert (-not $script:parentClosed) 'Standalone updater never closes an unrelated window'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "PASS: $script:checks close-handshake assertions; real marker files, simulated UI and process handles."
