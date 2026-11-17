# Desktop shortcut work is isolated from Word templates, options and documents.
function Get-OfficeShortcutPlan {
    param(
        [string]$UserDesktop = [Environment]::GetFolderPath('DesktopDirectory'),
        [string]$PublicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [string[]]$StartMenus = @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs'))
    )
    $shell = New-Object -ComObject WScript.Shell
    $links = @()
    $locations = @(@{ Scope = 'User'; Path = $UserDesktop }, @{ Scope = 'Public'; Path = $PublicDesktop })
    foreach ($menu in $StartMenus) { $locations += @{ Scope = 'StartMenu'; Path = $menu } }
    foreach ($location in $locations) {
        if (-not $location.Path -or -not (Test-Path -LiteralPath $location.Path)) { continue }
        $files = if ($location.Scope -eq 'StartMenu') { @(Get-ChildItem -LiteralPath $location.Path -Filter '*.lnk' -File -Recurse) } else { @(Get-ChildItem -LiteralPath $location.Path -Filter '*.lnk' -File) }
        foreach ($file in $files) {
            $shortcut = $shell.CreateShortcut($file.FullName)
            if ([string]::IsNullOrWhiteSpace($shortcut.TargetPath)) { continue }
            $app = switch ([IO.Path]::GetFileName($shortcut.TargetPath).ToUpperInvariant()) { 'WINWORD.EXE' { 'Word' }; 'EXCEL.EXE' { 'Excel' }; default { '' } }
            if (-not $app -or $shortcut.Arguments -or -not (Test-Path -LiteralPath $shortcut.TargetPath -PathType Leaf)) { continue }
            $links += [pscustomobject]@{ App = $app; Scope = $location.Scope; Path = $file.FullName; Target = [IO.Path]::GetFullPath($shortcut.TargetPath); Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
        }
    }
    $plans = @()
    foreach ($app in 'Word','Excel') {
        $matches = @($links | Where-Object App -eq $app | Sort-Object Path -Unique)
        $canonical = @($matches | Where-Object Scope -eq 'Public' | Sort-Object Path | Select-Object -First 1)
        if (-not $canonical.Count) { $canonical = @($matches | Where-Object Scope -eq 'User' | Select-Object -First 1) }
        if (-not $canonical.Count) { $canonical = @($matches | Where-Object Scope -eq 'StartMenu' | Select-Object -First 1) }
        if (-not $canonical.Count) { continue }
        $source = $canonical[0]
        $destination = if ($source.Scope -eq 'Public') { $source.Path } else { Join-Path $PublicDesktop ($app + '.lnk') }
        if ($destination -ne $source.Path -and (Test-Path -LiteralPath $destination)) {
            $destination = Join-Path $PublicDesktop ($app + ' (TechMaster).lnk')
            if (Test-Path -LiteralPath $destination) { throw "Đã có shortcut khác tại $destination. Kiểm tra thủ công trước khi dọn." }
        }
        $duplicates = @($matches | Where-Object { $_.Scope -in 'User','Public' -and $_.Path -ne $destination -and $_.Target -eq $source.Target })
        $plans += [pscustomobject]@{ App = $app; Source = $source; Destination = $destination; Create = $destination -ne $source.Path; Remove = $duplicates }
    }
    return $plans
}
function Invoke-OfficeShortcutPlan($Plan, [string]$BackupDirectory) {
    # Validate the complete plan before creating/removing anything.
    foreach ($item in $Plan) {
        foreach ($link in @($item.Source) + @($item.Remove)) {
            if (-not (Test-Path -LiteralPath $link.Path -PathType Leaf) -or (Get-FileHash -LiteralPath $link.Path -Algorithm SHA256).Hash -cne $link.Hash) { throw 'Shortcut đã thay đổi sau khi kiểm tra. Làm mới danh sách rồi thử lại.' }
        }
        if ($item.Create -and (Test-Path -LiteralPath $item.Destination)) { throw 'Đích shortcut đã xuất hiện. Làm mới danh sách rồi thử lại.' }
    }
    foreach ($item in $Plan) {
        foreach ($link in @($item.Remove)) {
            $backup = Join-Path (Join-Path $BackupDirectory $link.Scope) ([IO.Path]::GetFileName($link.Path))
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            [IO.File]::Copy($link.Path, $backup, $false)
        }
    }
    foreach ($item in $Plan) {
        if ($item.Create) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $item.Destination) -Force | Out-Null
            [IO.File]::Copy($item.Source.Path, $item.Destination, $false)
        }
        foreach ($link in @($item.Remove)) { Remove-Item -LiteralPath $link.Path -Force -ErrorAction Stop }
    }
}
function Get-ScreenClipChoice {
    $choice = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\ms-screenclip\UserChoice' -ErrorAction SilentlyContinue
    if ($choice.ProgId -and $choice.ProgId -match '^[A-Za-z0-9_.-]+$') { return [string]$choice.ProgId }
    return ''
}
function Add-ScreenClipDefault([string]$Path) {
    $progId = Get-ScreenClipChoice
    if (-not $progId) { return $false }
    $doc = New-Object Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.Load($Path)
    if ($doc.DocumentElement.Name -cne 'DefaultAssociations') { throw 'File ứng dụng mặc định không hợp lệ.' }
    foreach ($old in @($doc.SelectNodes('/DefaultAssociations/Association[@Identifier="ms-screenclip"]'))) { $null = $old.ParentNode.RemoveChild($old) }
    $node = $doc.CreateElement('Association')
    $node.SetAttribute('Identifier','ms-screenclip'); $node.SetAttribute('ProgId',$progId)
    $node.SetAttribute('ApplicationName','Screen capture')
    $null = $doc.DocumentElement.AppendChild($node)
    $doc.Save($Path)
    return $true
}
