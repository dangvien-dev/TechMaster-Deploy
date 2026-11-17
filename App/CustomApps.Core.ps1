# Per-user catalog only. No repository or remote synchronization.
function Get-DeployCustomAppsPath {return (Join-Path $env:LOCALAPPDATA 'TechMaster Deploy/CustomApps.json')}
function New-DeployCustomApp {
    param([string]$Name,[ValidateSet('WinGet','Local')][string]$Source,[string]$PackageId='',[string]$Path='',[string]$Arguments='',[string]$Key='')
    $Name=$Name.Trim()
    if(-not $Name -or $Name.Length -gt 100 -or $Name -match '[\r\n\x00]'){throw 'Nhập tên ứng dụng, tối đa 100 ký tự.'}
    if(-not $Key){$Key=[guid]::NewGuid().ToString('N')}
    if($Key -notmatch '^[a-fA-F0-9]{32}$'){throw 'Mã mục ứng dụng không hợp lệ.'}
    if($Source -eq 'WinGet'){
        $PackageId=$PackageId.Trim()
        if($PackageId.Length -gt 200 -or $PackageId -notmatch '^[A-Za-z0-9][A-Za-z0-9+_.-]*\.[A-Za-z0-9+_.-]+$'){throw 'ID WinGet không hợp lệ, ví dụ Microsoft.PowerToys.'}
        $Path='';$Arguments='';$id=$PackageId;$description='WinGet · '+$PackageId
    }else{
        if(-not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -notin '.exe','.msi' -or $Path -match '["\r\n\x00]'){throw 'Chọn đường dẫn đầy đủ tới bộ cài EXE hoặc MSI.'}
        if($Arguments.Length -gt 4096 -or $Arguments -match '[\r\n\x00]'){throw 'Tham số cài không hợp lệ.'}
        $id='Local.'+$Key.ToLowerInvariant();$description='Bộ cài trên máy · '+[IO.Path]::GetFileName($Path)
    }
    return [pscustomobject]@{Key=$Key.ToLowerInvariant();Name=$Name;Source=$Source;Id=$id;Path=$Path;Arguments=$Arguments;Description=$description;Custom=$true}
}
function Get-DeployCustomApps([string]$path) {
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    if((Get-Item -LiteralPath $path).Length -gt 1MB){throw 'Danh sách ứng dụng quá lớn.'}
    $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($data.Schema -ne 1 -or @($data.Apps).Count -gt 100){throw 'Định dạng danh sách ứng dụng không hợp lệ.'}
    $keys=@{};$ids=@{}
    foreach($app in @($data.Apps)){
        $item=New-DeployCustomApp -Name $app.Name -Source $app.Source -PackageId $app.Id -Path $app.Path -Arguments $app.Arguments -Key $app.Key
        if($keys.ContainsKey($item.Key) -or $ids.ContainsKey($item.Id)){throw 'Danh sách có mục trùng.'}
        $keys[$item.Key]=$true;$ids[$item.Id]=$true
        $item
    }
}
function Save-DeployCustomApps([string]$path,[object[]]$apps) {
    $directory=Split-Path -Parent $path;New-Item -ItemType Directory -Path $directory -Force|Out-Null
    $temp=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($temp,([pscustomobject]@{Schema=1;Apps=@($apps)}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        $null=@(Get-DeployCustomApps $temp)
        Move-Item -LiteralPath $temp -Destination $path -Force
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function New-DeployBasicStartInfo($app,[string]$winget) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    if($app.Source -eq 'Local'){
        if(-not (Test-Path -LiteralPath $app.Path -PathType Leaf) -or [IO.Path]::GetExtension($app.Path) -notin '.exe','.msi'){throw 'Không tìm thấy bộ cài. Kiểm tra lại USB / đường dẫn trong Quản lý ứng dụng.'}
        if([IO.Path]::GetExtension($app.Path) -ieq '.msi'){
            $start.FileName=Join-Path $env:SystemRoot 'System32/msiexec.exe';$start.Arguments='/i "'+$app.Path+'" /norestart '+$app.Arguments
        }else{$start.FileName=$app.Path;$start.Arguments=$app.Arguments}
    }else{
        if(-not $winget){throw 'Không tìm thấy WinGet.'}
        if($app.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9+_.-]*\.[A-Za-z0-9+_.-]+$'){throw 'ID WinGet không hợp lệ.'}
        $start.FileName=$winget
        $start.Arguments="install --id $($app.Id) --exact --source winget --silent --no-upgrade --disable-interactivity --accept-source-agreements --accept-package-agreements"
    }
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8
    return $start
}
