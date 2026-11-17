# Read-only availability check shared with the isolated background probe.
function Get-DeployUpdateAvailability([string]$Root) {
    $known='';$manifest=Join-Path $Root 'update-package.json'
    if(Test-Path -LiteralPath $manifest){try{$known=[string](Read-DeployManifest $manifest).source.commit}catch{}}
    try{
        $release=Get-DeployOnlineRelease $known
        if($release.unchanged){return [pscustomobject]@{Success=$true;Available=$false;Version=''}}
        $current=Get-DeployVersion $Root
        $available=([version]$release.version -gt $current) -or ([version]$release.version -eq $current -and $known -match '^[0-9a-f]{40}$' -and $release.commit -cne $known)
        return [pscustomobject]@{Success=$true;Available=[bool]$available;Version=[string]$release.version}
    }catch{return [pscustomobject]@{Success=$false;Available=$false;Version=''}}
}
