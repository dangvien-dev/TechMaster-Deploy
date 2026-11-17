$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Master.Preflight.Core.ps1')
$checks=0
function Assert($condition,$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
$script:shortcuts=@{}
function New-Object {
    param([string]$ComObject,[Parameter(Position=0)][string]$TypeName)
    if ($ComObject -eq 'WScript.Shell') {
        $shell=[pscustomobject]@{}
        $shell | Add-Member ScriptMethod CreateShortcut { param($path) return $script:shortcuts[$path] }
        return $shell
    }
    Microsoft.PowerShell.Utility\New-Object $TypeName
}
function Link($path,$target,$arguments='') {
    [IO.File]::WriteAllText($path,'shortcut '+$path)
    $script:shortcuts[$path]=[pscustomobject]@{TargetPath=$target;Arguments=$arguments}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-desktop-'+[guid]::NewGuid().ToString('N'))
try {
    $user=Join-Path $temp 'User';$public=Join-Path $temp 'Public';$menu=Join-Path $temp 'Menu'
    foreach ($path in $user,$public,$menu) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $word=Join-Path $temp 'WINWORD.EXE';$excel=Join-Path $temp 'EXCEL.EXE'
    [IO.File]::WriteAllText($word,'fake exe; never execute');[IO.File]::WriteAllText($excel,'fake exe; never execute')
    Link (Join-Path $public 'Word.lnk') $word
    Link (Join-Path $user 'Word copy.lnk') $word
    Link (Join-Path $user 'Word safe.lnk') $word '/safe'
    Link (Join-Path $user 'Excel.lnk') $excel
    Link (Join-Path $menu 'Excel.lnk') $excel
    Link (Join-Path $user 'Broken.lnk') (Join-Path $temp 'missing/WINWORD.EXE')
    Link (Join-Path $user 'My document.lnk') (Join-Path $temp 'document.docx')
    $settings=Join-Path $temp 'Normal.dotm';[IO.File]::WriteAllText($settings,'keep Word settings')
    $plan=@(Get-OfficeShortcutPlan -UserDesktop $user -PublicDesktop $public -StartMenus @($menu))
    Assert ($plan.Count -eq 2 -and @($plan | Where-Object Create).Count -eq 1) 'Only missing Excel public icon is created; existing public Word retained'
    Assert (@($plan | ForEach-Object Remove).Count -eq 2) 'Two duplicates found by executable target rather than filename'
    $changed=Join-Path $user 'Word copy.lnk';$original=[IO.File]::ReadAllText($changed);[IO.File]::WriteAllText($changed,'changed after inspection')
    $caught=''
    try { Invoke-OfficeShortcutPlan $plan (Join-Path $temp 'backup') } catch { $caught=$_.Exception.Message }
    Assert ($caught -match 'đã thay đổi' -and -not (Test-Path (Join-Path $public 'Excel.lnk')) -and (Test-Path (Join-Path $user 'Excel.lnk'))) 'Stale shortcut plan stops before any changes'
    [IO.File]::WriteAllText($changed,$original)
    $backup=Join-Path $temp 'backup'
    Invoke-OfficeShortcutPlan $plan $backup
    Assert ((Test-Path (Join-Path $public 'Word.lnk')) -and (Test-Path (Join-Path $public 'Excel.lnk'))) 'One shared shortcut exists per Office app'
    Assert (-not (Test-Path $changed) -and -not (Test-Path (Join-Path $user 'Excel.lnk'))) 'Only confirmed same-target personal duplicates removed'
    Assert ((Test-Path (Join-Path $user 'Word safe.lnk')) -and (Test-Path (Join-Path $user 'My document.lnk')) -and (Test-Path (Join-Path $menu 'Excel.lnk'))) 'Custom arguments, documents and Start Menu shortcuts preserved'
    Assert (@(Get-ChildItem -LiteralPath $backup -Recurse -File).Count -eq 2) 'Both removed shortcuts backed up'
    Assert ([IO.File]::ReadAllText($settings) -ceq 'keep Word settings') 'Normal.dotm and Office settings untouched'
    function Get-ItemProperty { [pscustomobject]@{ProgId='AppXScreenSnipping';Hash='DO-NOT-COPY-HASH'} }
    $xml=Join-Path $temp 'DefaultApps.xml'
    [IO.File]::WriteAllText($xml,'<DefaultAssociations><Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Chrome"/><Association Identifier="ms-screenclip" ProgId="old"/></DefaultAssociations>')
    Assert (Add-ScreenClipDefault $xml) 'Explicit current-user protocol choice added to default-app XML'
    [xml]$doc=[IO.File]::ReadAllText($xml)
    Assert ($doc.SelectSingleNode('/DefaultAssociations/Association[@Identifier="ms-screenclip"]').ProgId -eq 'AppXScreenSnipping') 'Chosen screen-capture handler preserved for new profiles'
    Assert ($doc.SelectNodes('/DefaultAssociations/Association[@Identifier="ms-screenclip"]').Count -eq 1 -and $doc.SelectSingleNode('/DefaultAssociations/Association[@Identifier="https"]').ProgId -eq 'ChromeHTML') 'No duplicate protocol association; other defaults preserved'
    Assert ([IO.File]::ReadAllText($xml) -notmatch 'DO-NOT-COPY-HASH|UserChoice') 'No registry UserChoice hash cloning or bypass'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
Write-Host "PASS: $checks master-preflight assertions; same-target duplicate backup/cleanup, Word settings retained and supported default-app XML."
