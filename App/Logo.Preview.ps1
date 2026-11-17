# All logo previews use WPF ImageSource, so ScrollViewer clipping works for SVG too.
function Get-DeployLogoPreview([string]$Path) {
    if(-not ('TechMaster.LogoPreview' -as [type])){
        Add-Type -AssemblyName PresentationCore,WindowsBase
        $references=@([Windows.Media.DrawingImage].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[Xml.XmlDocument].Assembly.Location,'System.dll')
        Add-Type -Path (Join-Path $PSScriptRoot 'LogoPreview.cs') -ReferencedAssemblies $references -ErrorAction Stop
    }
    return [TechMaster.LogoPreview]::Load($Path)
}
