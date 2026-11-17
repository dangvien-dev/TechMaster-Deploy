# Current-user keyboard settings only. No language pack or application is removed.
$script:EvKeyUsTip = '0409:00000409'

function Get-KeyboardSnapshot([string]$userSid) {
    $nativeList = Get-WinUserLanguageList -ErrorAction Stop
    $list = @(foreach ($entry in $nativeList) { $entry })
    if (-not $list.Count) { throw 'Không đọc được danh sách ngôn ngữ hiện tại.' }
    $input = Get-WinDefaultInputMethodOverride -ErrorAction Stop
    [pscustomobject]@{
        schema = 1; userSid = $userSid; date = (Get-Date).ToString('o')
        defaultTip = [string]$input.InputMethodTip
        languages = @($list | ForEach-Object {
            [pscustomobject]@{ tag = $_.LanguageTag; tips = @($_.InputMethodTips); spellchecking = $_.Spellchecking; handwriting = $_.Handwriting }
        })
    }
}

function Assert-KeyboardSnapshot($snapshot, [string]$userSid) {
    if ($snapshot.schema -ne 1 -or $snapshot.userSid -cne $userSid -or @($snapshot.languages).Count -lt 1 -or @($snapshot.languages).Count -gt 50) { throw 'Bản sao lưu bàn phím không khớp user này.' }
    foreach ($language in $snapshot.languages) {
        $null = [Globalization.CultureInfo]::GetCultureInfo([string]$language.tag)
        foreach ($tip in $language.tips) {
            if ($tip -notmatch '^[a-f0-9]{4}:(?:[a-f0-9]{8}|(?:\{[a-f0-9-]{36}\}){1,2})$') { throw 'Mã bàn phím trong sao lưu không hợp lệ.' }
        }
    }
}

function Set-KeyboardFromSnapshot($snapshot, [string]$userSid) {
    Assert-KeyboardSnapshot $snapshot $userSid
    $list = $null
    foreach ($language in $snapshot.languages) {
        $one = New-WinUserLanguageList -Language $language.tag -ErrorAction Stop
        $entry = $one[0]
        $entry.InputMethodTips.Clear()
        foreach ($tip in $language.tips) { $entry.InputMethodTips.Add([string]$tip) }
        if ($null -ne $language.spellchecking) { $entry.Spellchecking = [bool]$language.spellchecking }
        if ($null -ne $language.handwriting) { $entry.Handwriting = [bool]$language.handwriting }
        if ($null -eq $list) { $list = $one } else { $list.Add($entry) }
    }
    Set-WinUserLanguageList -LanguageList $list -Force -ErrorAction Stop
    if ($snapshot.defaultTip) { Set-WinDefaultInputMethodOverride -InputTip $snapshot.defaultTip -ErrorAction Stop }
    else { Set-WinDefaultInputMethodOverride -ErrorAction Stop }
}

function Compare-KeyboardSnapshot($a, $b) {
    if ($a.defaultTip -cne $b.defaultTip -or @($a.languages).Count -ne @($b.languages).Count) { return $false }
    for ($i = 0; $i -lt @($a.languages).Count; $i++) {
        if ($a.languages[$i].tag -cne $b.languages[$i].tag -or (@($a.languages[$i].tips) -join '|') -cne (@($b.languages[$i].tips) -join '|') -or
            $a.languages[$i].spellchecking -ne $b.languages[$i].spellchecking -or $a.languages[$i].handwriting -ne $b.languages[$i].handwriting) { return $false }
    }
    return $true
}

function Set-EvKeyUsKeyboard([string]$backupDirectory, [string]$userSid) {
    $before = Get-KeyboardSnapshot $userSid
    Assert-KeyboardSnapshot $before $userSid
    $tips = @($before.languages | ForEach-Object { $_.tips } | Sort-Object -Unique)
    if ($tips.Count -eq 1 -and $tips[0] -ceq $script:EvKeyUsTip -and $before.defaultTip -ceq $script:EvKeyUsTip) {
        Write-Host 'Đang chỉ dùng bàn phím US; không cần thay đổi.'
        return $null
    }
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $path = Join-Path $backupDirectory ('before-' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($path, ($before | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $next = Get-WinUserLanguageList -ErrorAction Stop
    foreach ($entry in $next) {
        $entry.InputMethodTips.Clear()
        $entry.InputMethodTips.Add($script:EvKeyUsTip)
    }
    try {
        Set-WinUserLanguageList -LanguageList $next -Force -ErrorAction Stop
        Set-WinDefaultInputMethodOverride -InputTip $script:EvKeyUsTip -ErrorAction Stop
        $after = Get-KeyboardSnapshot $userSid
        $remaining = @($after.languages | ForEach-Object { $_.tips } | Sort-Object -Unique)
        if (($before.languages.tag -join '|') -cne ($after.languages.tag -join '|') -or $remaining.Count -ne 1 -or $remaining[0] -cne $script:EvKeyUsTip -or $after.defaultTip -cne $script:EvKeyUsTip) {
            throw 'Windows chưa giữ được cấu hình chỉ bàn phím US.'
        }
    } catch {
        $failure = $_.Exception.Message
        try {
            Set-KeyboardFromSnapshot $before $userSid
            if (-not (Compare-KeyboardSnapshot $before (Get-KeyboardSnapshot $userSid))) { throw 'Trạng thái đọc lại chưa khớp sao lưu.' }
        }
        catch { throw "Chưa cấu hình xong và chưa khôi phục được bàn phím. Sao lưu: $path. $failure; $($_.Exception.Message)" }
        throw "Chưa cấu hình xong; đã gửi khôi phục cấu hình cũ. $failure"
    }
    return $path
}

function Restore-EvKeyKeyboard([string]$path, [string]$userSid) {
    $saved = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    Assert-KeyboardSnapshot $saved $userSid
    Set-KeyboardFromSnapshot $saved $userSid
    if (-not (Compare-KeyboardSnapshot $saved (Get-KeyboardSnapshot $userSid))) { throw 'Chưa xác nhận được bàn phím đã khôi phục đúng sao lưu.' }
}
