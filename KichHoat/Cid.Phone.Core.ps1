# Render only; never starts a listener or changes activation.
function New-CidPhonePage {
    param([string]$InstallationId,[string]$Computer,[string]$Product,[string]$Portal,[string]$Message='')
    if($InstallationId -notmatch '^[0-9]+$'){throw 'Installation ID không hợp lệ.'}
    if($Portal -notin 'https://visualsupport.microsoft.com/','https://aka.ms/WindowsActivate'){throw 'Portal không thuộc địa chỉ Microsoft được hỗ trợ.'}
    $page=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CID-Phone.html'))
    $page=$page.Replace('__IID__',$InstallationId).Replace('__PORTAL__',$Portal).Replace('__MSG__',$Message)
    return $page.Replace('__PCNAME__',[Net.WebUtility]::HtmlEncode($Computer)).Replace('__PRODUCT__',[Net.WebUtility]::HtmlEncode($Product))
}
