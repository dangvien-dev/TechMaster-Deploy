# International cmdlets are mocked. Tests never alter the host keyboard.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Fix-BanPhim.Core.ps1')
$script:checks = 0
function Assert($condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Expect-Failure([scriptblock]$action, [string]$pattern) {
    $caught = ''
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -match $pattern) "Expected $pattern; got $caught"
}
function Make-Language([string]$tag, [string[]]$tips) {
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($tip in $tips) { $list.Add($tip) }
    [pscustomobject]@{ LanguageTag = $tag; InputMethodTips = $list; Spellchecking = $true; Handwriting = $false }
}
function Get-WinUserLanguageList {
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $script:state) {
        $copy = Make-Language $row.LanguageTag @($row.InputMethodTips)
        $copy.Spellchecking = $row.Spellchecking; $copy.Handwriting = $row.Handwriting
        $list.Add($copy)
    }
    return ,$list
}
function New-WinUserLanguageList($Language) {
    $list = New-Object 'System.Collections.Generic.List[object]'
    $list.Add((Make-Language $Language @()))
    return ,$list
}
function Get-WinDefaultInputMethodOverride { [pscustomobject]@{ InputMethodTip = $script:defaultTip } }
function Set-WinDefaultInputMethodOverride($InputTip) { $script:defaultTip = [string]$InputTip }
function Set-WinUserLanguageList($LanguageList, [switch]$Force) {
    $script:setCalls++
    if ($script:failOnce) { $script:failOnce = $false; throw 'simulated language failure' }
    $script:state = @(foreach ($row in $LanguageList) {
        $copy = Make-Language $row.LanguageTag @($row.InputMethodTips)
        $copy.Spellchecking = $row.Spellchecking; $copy.Handwriting = $row.Handwriting
        $copy
    })
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tm-keyboard-' + [guid]::NewGuid().ToString('N'))
try {
    $script:state = @((Make-Language 'vi-VN' @('042a:0000042a','042a:{11111111-1111-1111-1111-111111111111}{22222222-2222-2222-2222-222222222222}')), (Make-Language 'en-US' @('0409:00000409')), (Make-Language 'en-GB' @('0809:00000809')))
    $script:defaultTip = ''; $script:setCalls = 0; $script:failOnce = $false
    $script:state[0].Handwriting = $true; $script:state[0].Spellchecking = $false
    $sid = 'test-user-sid'
    $before = Get-KeyboardSnapshot $sid
    Assert ($before.languages.Count -eq 3 -and $before.languages[0].tag -eq 'vi-VN') 'Native list object is expanded into individual language records'
    $backup = Set-EvKeyUsKeyboard $temp $sid
    Assert (Test-Path -LiteralPath $backup) 'Original input settings saved before changes'
    $after = Get-KeyboardSnapshot $sid
    Assert (($after.languages.tag -join ',') -eq 'vi-VN,en-US,en-GB') 'Language preference order and Vietnamese display-language entry retained'
    Assert ($after.languages[0].handwriting -and -not $after.languages[0].spellchecking) 'Existing handwriting/spelling preferences survive changing input methods'
    foreach ($row in $after.languages) { Assert (@($row.tips).Count -eq 1 -and $row.tips[0] -eq '0409:00000409') 'Each language uses only the US input method' }
    Assert ($after.defaultTip -eq '0409:00000409') 'Default input method set to US'
    $count = @(Get-ChildItem -LiteralPath $temp -Filter '*.json').Count
    $calls = $script:setCalls
    $none = Set-EvKeyUsKeyboard $temp $sid
    Assert ($null -eq $none -and $script:setCalls -eq $calls -and @(Get-ChildItem -LiteralPath $temp -Filter '*.json').Count -eq $count) 'Already-US state does not replace the useful original backup'
    Restore-EvKeyKeyboard $backup $sid
    Assert (Compare-KeyboardSnapshot $before (Get-KeyboardSnapshot $sid)) 'Manual restore recovers all original input methods including Telex GUIDs and no override'
    Expect-Failure { Restore-EvKeyKeyboard $backup 'different-user' } 'không khớp user'
    $script:failOnce = $true
    Expect-Failure { Set-EvKeyUsKeyboard $temp $sid } 'khôi phục cấu hình cũ'
    Assert (Compare-KeyboardSnapshot $before (Get-KeyboardSnapshot $sid)) 'Failed apply rolls back original list and default method'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
Write-Host "PASS: $script:checks keyboard assertions; mocked Windows International cmdlets and real backup files."
