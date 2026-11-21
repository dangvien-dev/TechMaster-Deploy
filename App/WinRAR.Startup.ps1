# WinRAR may finish its per-user Explorer integration on first launch after cloning.
# Read the existing installation and open its UI; do not reinstall or edit shell keys.
function Get-DeployWinRarPath {
    $candidates=New-Object Collections.Generic.List[string]
    $views=@([Microsoft.Win32.RegistryView]::Registry32)
    if([Environment]::Is64BitOperatingSystem){$views=@([Microsoft.Win32.RegistryView]::Registry64)+$views}
    foreach($view in $views){foreach($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)){
        $root=$null;$key=$null
        try{
            $root=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
            $key=$root.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WinRAR.exe')
            if($key){$value=[Environment]::ExpandEnvironmentVariables(([string]$key.GetValue('')).Trim().Trim('"'));if($value){$candidates.Add($value)}}
        }finally{if($key){$key.Dispose()};if($root){$root.Dispose()}}
    }}
    foreach($directory in @($env:ProgramW6432,$env:ProgramFiles,${env:ProgramFiles(x86)})|Where-Object {$_}|Select-Object -Unique){$candidates.Add((Join-Path $directory 'WinRAR/WinRAR.exe'))}
    foreach($candidate in $candidates|Select-Object -Unique){
        if([IO.Path]::IsPathRooted($candidate) -and [IO.Path]::GetFileName($candidate) -ieq 'WinRAR.exe' -and (Test-Path -LiteralPath $candidate -PathType Leaf)){return $candidate}
    }
    return ''
}
function Get-DeployWinRarRunning([string]$Path) {
    # Get-Process -Name with SilentlyContinue still sets PowerShell.HadErrors
    # when no process exists, which would invalidate an otherwise successful worker.
    $processes=[Diagnostics.Process]::GetProcessesByName('WinRAR')
    try{
        foreach($process in $processes){
            try{if($process.MainModule.FileName -ieq $Path -and -not $process.HasExited){return $true}}catch{}
        }
        return $false
    }finally{foreach($process in $processes){$process.Dispose()}}
}
function Complete-DeployWinRarStartup($Result,[string]$Details,[string]$LogPath) {
    if($Result.Group -notin 'Installed','Skipped','Restart'){return [pscustomobject]@{Status=$Result.Status;Group=$Result.Group;Details=$Details}}
    try{
        $path=Get-DeployWinRarPath
        if(-not $path){throw 'Chưa tìm thấy WinRAR.exe để mở lần đầu. Mở WinRAR từ Start rồi kiểm tra menu chuột phải.'}
        $opened=$false
        if(-not (Get-DeployWinRarRunning $path)){
            [IO.File]::AppendAllText($LogPath,("`r`nWinRAR first launch: "+$path+"`r`n"),[Text.UTF8Encoding]::new($false))
            # Do not wait for the user to close WinRAR. Never pass archive arguments.
            $process=Start-Process -FilePath $path -PassThru -ErrorAction Stop
            if($process){$process.Dispose()};$opened=$true
        }
        $message=if($opened){'Đã mở WinRAR · kiểm tra menu chuột phải'}else{'WinRAR đang mở · kiểm tra menu chuột phải'}
        if($Result.Group -eq 'Restart'){$message+=' · cần khởi động lại'}
        return [pscustomobject]@{Status=$message;Group=$Result.Group;Details=($Details+"`r`nWinRAR: "+$path+"`r`n"+$message+"`r`nHoàn tất thông báo lần đầu trong WinRAR nếu có, rồi thử chuột phải trên tệp / thư mục. Việc mở ứng dụng chưa tự xác nhận được menu đã xuất hiện.")}
    }catch{
        return [pscustomobject]@{Status=($Result.Status+' · chưa mở được WinRAR');Group='Failed';Details=($Details+"`r`n"+$_.Exception.GetBaseException().Message)}
    }
}
