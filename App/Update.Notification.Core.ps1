# This moving URL is used only for a notification. Installing still resolves an
# immutable commit, validates the full index and checks every downloaded blob.
function Get-DeployNotificationVersion {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $url='https://raw.githubusercontent.com/dangvien-dev/TechMaster-Deploy/main/version.txt?check='+[guid]::NewGuid().ToString('N')
    $request=[Net.HttpWebRequest]::Create($url)
    $request.UserAgent='TechMaster-Deploy-Notification';$request.AllowAutoRedirect=$false
    $request.Timeout=10000;$request.ReadWriteTimeout=10000;$request.Headers['Cache-Control']='no-cache'
    $response=$null;$reader=$null
    try{
        $response=$request.GetResponse()
        if([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt 256){throw 'Invalid version response'}
        $reader=[IO.StreamReader]::new($response.GetResponseStream(),[Text.Encoding]::UTF8,$true)
        $buffer=New-Object char[] 257;$count=$reader.ReadBlock($buffer,0,257)
        if($count -gt 256){throw 'Version response is too large'}
        $value=(-join $buffer[0..([Math]::Max(0,$count-1))]).Trim([char]0xfeff).Trim()
        $version=$null
        if($value -notmatch '^\d+\.\d+\.\d+\.\d+$' -or -not [version]::TryParse($value,[ref]$version)){throw 'Invalid version number'}
        return $version
    }finally{if($reader){$reader.Dispose()};if($response){$response.Dispose()}}
}
# Read-only availability check shared with the isolated background probe.
function Get-DeployUpdateAvailability([string]$Root) {
    $known='';$manifest=Join-Path $Root 'update-package.json'
    if(Test-Path -LiteralPath $manifest){try{$known=[string](Read-DeployManifest $manifest).source.commit}catch{}}
    try{
        $current=Get-DeployVersion $Root
        try{
            $latest=Get-DeployNotificationVersion
            if($latest -ne $current -or $known -notmatch '^[0-9a-f]{40}$'){
                return [pscustomobject]@{Success=$true;Available=($latest -gt $current);Version=$latest.ToString()}
            }
        }catch{} # The existing authenticated path still supports private installations.
        $release=Get-DeployOnlineRelease $known
        if($release.unchanged){return [pscustomobject]@{Success=$true;Available=$false;Version=''}}
        $current=Get-DeployVersion $Root
        $available=([version]$release.version -gt $current) -or ([version]$release.version -eq $current -and $known -match '^[0-9a-f]{40}$' -and $release.commit -cne $known)
        return [pscustomobject]@{Success=$true;Available=[bool]$available;Version=[string]$release.version}
    }catch{return [pscustomobject]@{Success=$false;Available=$false;Version=''}}
}
