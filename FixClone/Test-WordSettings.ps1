$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Word.Settings.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Get-Process($Name,$ErrorAction){return $null}
function Test-WordOptionsPresent{$script:hasOptions}
function Invoke-WordRegistryCommand([string[]]$arguments){
    $script:events+=,$arguments
    switch($arguments[0]){
        export {[IO.File]::WriteAllText($arguments[2],"Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Word\Options]`r`n`"KeepSetting`"=`"Yes`"",[Text.Encoding]::Unicode)}
        import {$script:imported=Get-Content -LiteralPath $arguments[1] -Raw -Encoding Unicode;if($script:failImport){throw 'test import failed'}}
    }
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-word-'+[guid]::NewGuid().ToString('N'))
try{
    $roaming=Join-Path $temp 'Roaming';$local=Join-Path $temp 'Local';$default=Join-Path $temp 'Default';$work=Join-Path $temp 'Work'
    foreach($path in (Join-Path $roaming 'Microsoft/Templates'),(Join-Path $local 'Microsoft/Office'),$default,$work){New-Item -ItemType Directory -Path $path -Force|Out-Null}
    [IO.File]::WriteAllText((Join-Path $roaming 'Microsoft/Templates/Normal.dotm'),'paper-size-and-margins')
    [IO.File]::WriteAllText((Join-Path $local 'Microsoft/Office/Word.officeUI'),'ribbon-settings')
    $script:events=@();$script:hasOptions=$true;$script:failImport=$false
    Save-MasterWordPreferences $work $roaming $local $default
    Assert ((Get-Content (Join-Path $default 'AppData/Roaming/Microsoft/Templates/Normal.dotm') -Raw) -ceq 'paper-size-and-margins') 'Word document template copied exactly'
    Assert ((Get-Content (Join-Path $default 'AppData/Local/Microsoft/Office/Word.officeUI') -Raw) -ceq 'ribbon-settings') 'Ribbon preferences copied exactly'
    Assert (($script:events|ForEach-Object {$_[0]}) -join ',' -ceq 'export,load,import,unload') 'Options exported and hive always unloaded'
    Assert ($script:imported -match '\[HKEY_USERS\\FixCloneWord_[a-f0-9]{32}\\Software\\Microsoft\\Office\\16.0\\Word\\Options\]' -and $script:imported -notmatch 'HKEY_CURRENT_USER') 'Options target unique Default-profile mount'
    Assert (@(Get-ChildItem $work).Count -eq 0) 'Temporary exports removed'
    $script:events=@();$script:failImport=$true;$caught=''
    try{Save-MasterWordPreferences $work $roaming $local $default}catch{$caught=$_.Exception.Message}
    Assert ($caught -eq 'test import failed' -and $script:events[-1][0] -eq 'unload') 'Import failure stops preparation and still unloads hive'
    [IO.File]::WriteAllText((Join-Path $work 'WordOptions_export.reg'),'stale-data')
    $script:hasOptions=$false;$script:events=@()
    Save-MasterWordPreferences $work $roaming $local $default
    Assert ($script:events.Count -eq 0) 'No options means skip; stale export is never imported'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks Word preference assertions; exact template/ribbon copies, unique registry export, failure stops, hive unload and no stale import."
