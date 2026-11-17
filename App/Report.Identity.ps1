# Reset only identity inputs/assets; exported reports and other program data are retained.
function Reset-DeployReportIdentity([string]$directory) {
    foreach($name in 'BienBan-Config.json','Logo.svg','Logo.png','Logo.jpg','Logo.jpeg'){
        $path=Join-Path $directory $name
        if(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
    }
}
