# Only identity inputs/assets are changed; exported reports are retained.
function Remove-DeployReportLogo([string]$directory) {
    foreach($name in 'Logo.svg','Logo.png','Logo.jpg','Logo.jpeg'){
        $path=Join-Path $directory $name
        if(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
    }
}
function Save-DeployReportIdentity {
    param([string]$Directory,[string]$Company,[string]$Address,[string]$Phone,[string]$Technician)
    $cfg=[pscustomobject]@{Company=$Company.Trim();Address=$Address.Trim();Phone=$Phone.Trim();Technician=$Technician.Trim()}
    New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop|Out-Null
    $path=Join-Path $Directory 'BienBan-Config.json'
    [IO.File]::WriteAllText($path,($cfg|ConvertTo-Json),[Text.UTF8Encoding]::new($true))
    return $cfg
}
function Reset-DeployReportIdentity([string]$directory) {
    $path=Join-Path $directory 'BienBan-Config.json'
    if(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
    Remove-DeployReportLogo $directory
}
