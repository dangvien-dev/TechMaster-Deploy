# Official pinned installer. Importing this module never changes the machine.
function Test-DeployUltraTargetVersion([string]$text) {
    return $text.Trim() -match '^6[.,]6[.,]133(?:[.,]0)?$'
}
function Get-DeployUltraInstalledVersion {
    foreach($path in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'){
        $app=Get-ItemProperty -Path $path -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -match '^UltraViewer(?:\s|$)'}|Select-Object -First 1
        if($app){return $(if($app.DisplayVersion){[string]$app.DisplayVersion}else{'không rõ phiên bản'})}
    }
    return ''
}
function Get-DeployUltraInstallerInfo([string]$path){return [Diagnostics.FileVersionInfo]::GetVersionInfo($path)}
function Assert-DeployUltraInstaller([string]$path) {
    $signature=Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)\bDuc\s*Fabulous\b'){
        throw 'Không xác minh được chữ ký nhà phát hành UltraViewer. Chưa chạy bộ cài.'
    }
    $info=Get-DeployUltraInstallerInfo $path
    if(-not (Test-DeployUltraTargetVersion $info.ProductVersion) -and -not (Test-DeployUltraTargetVersion $info.FileVersion)){
        throw 'Bộ cài không phải UltraViewer 6.6.133. Chưa chạy bộ cài.'
    }
}
function Save-DeployUltraInstaller([string]$path) {
    $url='https://dl2.ultraviewer.net/UltraViewer_setup_6.6.133_vi.exe'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $request=[Net.HttpWebRequest]::Create($url)
    $request.AllowAutoRedirect=$false;$request.Timeout=60000;$request.ReadWriteTimeout=30000
    $request.UserAgent='TechMaster-Deploy'
    $response=$null;$inputStream=$null;$outputStream=$null
    try{
        $response=$request.GetResponse()
        if([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt 50MB){throw 'Phản hồi tải không hợp lệ.'}
        $inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($path)
        $buffer=New-Object byte[] 65536;$total=0L
        while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
            $total+=$count;if($total -gt 50MB){throw 'Bộ cài vượt giới hạn tải.'}
            $outputStream.Write($buffer,0,$count)
        }
    }finally{
        if($outputStream){$outputStream.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()}
    }
}
function Install-DeployUltraViewer([string]$cache) {
    $version=Get-DeployUltraInstalledVersion
    if($version){return [pscustomobject]@{Status=('Đã có UltraViewer '+$version);Group='Skipped';Details='Giữ bản đã cài, không ngắt phiên hỗ trợ.'}}
    if(Get-Process -Name UltraViewer_Desktop,UltraViewer_Service -ErrorAction SilentlyContinue){return [pscustomobject]@{Status='Đang chạy UltraViewer — bỏ qua';Group='Skipped';Details='Không chạy bộ cài khi đang có phiên UltraViewer.'}}
    New-Item -ItemType Directory -Path $cache -Force|Out-Null
    $installer=Join-Path $cache 'UltraViewer-6.6.133-vi.exe'
    $temp=Join-Path $cache ([guid]::NewGuid().ToString('N')+'.download')
    try{
        $valid=$false
        if(Test-Path -LiteralPath $installer -PathType Leaf){try{Assert-DeployUltraInstaller $installer;$valid=$true}catch{Remove-Item -LiteralPath $installer -Force}}
        if(-not $valid){
            Save-DeployUltraInstaller $temp
            Assert-DeployUltraInstaller $temp
            Move-Item -LiteralPath $temp -Destination $installer -Force
        }
        # Recheck before execution, including when a cached installer was reused.
        Assert-DeployUltraInstaller $installer
        $log=Join-Path $cache ('Setup-'+[guid]::NewGuid().ToString('N')+'.log')
        $process=Start-Process -FilePath $installer -ArgumentList ('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="{0}"' -f $log) -Wait -PassThru -ErrorAction Stop
        try{$exit=$process.ExitCode}finally{$process.Dispose()}
        if($null -eq $exit -or $exit -notin 0,3010){throw ('Bộ cài UltraViewer báo lỗi '+$exit+'. Nhật ký: '+$log)}
        $after=Get-DeployUltraInstalledVersion
        if(-not (Test-DeployUltraTargetVersion $after)){throw 'Bộ cài kết thúc nhưng chưa xác nhận được UltraViewer 6.6.133 trong máy.'}
        return [pscustomobject]@{Status=$(if($exit -eq 3010){'Đã cài 6.6.133 — cần khởi động lại'}else{'Đã cài UltraViewer 6.6.133'});Group=$(if($exit -eq 3010){'Restart'}else{'Installed'});Details=('Nguồn: https://dl2.ultraviewer.net/UltraViewer_setup_6.6.133_vi.exe'+"`r`nSHA256: "+(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash+"`r`nNhật ký: "+$log)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
