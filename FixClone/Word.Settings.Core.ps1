# Save application preferences without copying Office identities or activation tokens.
function Invoke-WordRegistryCommand([string[]]$arguments) {
    & reg.exe @arguments | Out-Null
    if($LASTEXITCODE -ne 0){throw ('Không lưu được Word Options: reg '+$arguments[0]+' (mã '+$LASTEXITCODE+').')}
}
function Test-WordOptionsPresent { Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Office\16.0\Word\Options' }
function Save-MasterWordPreferences {
    param([string]$Work,[string]$Roaming=$env:APPDATA,[string]$Local=$env:LOCALAPPDATA,[string]$DefaultProfile='C:\Users\Default')
    if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Đóng Word trước khi lưu thiết lập.'}
    foreach($file in @(
        @{Source=(Join-Path $Roaming 'Microsoft/Templates/Normal.dotm');Target=(Join-Path $DefaultProfile 'AppData/Roaming/Microsoft/Templates/Normal.dotm')},
        @{Source=(Join-Path $Local 'Microsoft/Office/Word.officeUI');Target=(Join-Path $DefaultProfile 'AppData/Local/Microsoft/Office/Word.officeUI')}
    )) {
        if(-not (Test-Path -LiteralPath $file.Source -PathType Leaf)){continue}
        New-Item -ItemType Directory -Path (Split-Path -Parent $file.Target) -Force|Out-Null
        Copy-Item -LiteralPath $file.Source -Destination $file.Target -Force -ErrorAction Stop
        if((Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $file.Target -Algorithm SHA256).Hash){throw 'Bản sao thiết lập Word chưa khớp; dừng trước khi dọn key.'}
    }
    # Unique exports prevent importing stale settings from an earlier preparation.
    if(-not (Test-WordOptionsPresent)){return}
    $id=[guid]::NewGuid().ToString('N');$hive='FixCloneWord_'+$id
    $export=Join-Path $Work ('WordOptions_'+$id+'.reg');$import=Join-Path $Work ('WordOptionsDefault_'+$id+'.reg')
    $loaded=$false
    try {
        Invoke-WordRegistryCommand -arguments @('export','HKCU\Software\Microsoft\Office\16.0\Word\Options',$export,'/y')
        if(-not (Test-Path -LiteralPath $export -PathType Leaf)){throw 'Thiếu bản xuất Word Options.'}
        $content=Get-Content -LiteralPath $export -Raw -Encoding Unicode
        if($content -notmatch '(?m)^\[HKEY_CURRENT_USER\\Software\\Microsoft\\Office\\16\.0\\Word\\Options(?:\\[^\]]*)?\]'){throw 'Bản xuất Word Options không hợp lệ.'}
        $content=$content -replace '(?m)^\[HKEY_CURRENT_USER\\Software\\Microsoft\\Office\\16\.0\\Word\\Options',('[HKEY_USERS\'+$hive+'\Software\Microsoft\Office\16.0\Word\Options')
        [IO.File]::WriteAllText($import,$content,[Text.Encoding]::Unicode)
        Invoke-WordRegistryCommand -arguments @('load',('HKU\'+$hive),(Join-Path $DefaultProfile 'NTUSER.DAT'));$loaded=$true
        Invoke-WordRegistryCommand -arguments @('import',$import)
    } finally {
        try {if($loaded){[gc]::Collect();Invoke-WordRegistryCommand -arguments @('unload',('HKU\'+$hive))}}
        finally {foreach($path in $export,$import){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
    }
}
