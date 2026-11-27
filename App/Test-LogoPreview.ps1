# Native rendering regression: a real SVG WPF Image must obey the report viewport.
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Write-Host 'SKIP: WPF SVG preview requires Windows.';return}
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'Logo.Preview.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Pixel($visual,[int]$x,[int]$y){
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($visual.ActualWidth),[int][Math]::Ceiling($visual.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual);$pixel=New-Object byte[] 4
    $bitmap.CopyPixels([Windows.Int32Rect]::new($x,$y,1,1),$pixel,4,0)
    return ($pixel -join ',')
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-logo-'+[guid]::NewGuid().ToString('N'))
$preview=$null
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    $svg=Join-Path $temp 'Logo.svg'
    [IO.File]::WriteAllText($svg,'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><g fill-rule="evenodd" fill="#f97316"><path d="M0,0 H200 V200 H0 Z"/></g></svg>')
    $defaultSvg=Join-Path $temp 'Default.svg'
    [IO.File]::WriteAllText($defaultSvg,'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0H10V10H0Z"/></svg>')
    Assert ((Get-DeployLogoPreview $defaultSvg) -is [Windows.Media.DrawingImage]) 'Default and named SVG fill colors are supported'
    $source=Get-DeployLogoPreview $svg
    Assert ($source -is [Windows.Media.DrawingImage] -and $source.IsFrozen) 'SVG becomes a frozen native drawing, with no browser child window'
    $preview=Import-DeployWindow (Join-Path $PSScriptRoot 'MainWindow.xml')
    $preview.Width=1000;$preview.Height=620;$preview.FindName('tabs').SelectedItem=$preview.FindName('tabLicense')
    $image=$preview.FindName('logoBox');$image.Source=$source
    Assert (-not $preview.FindName('logoWeb')) 'The report no longer contains the airspace WebBrowser host'
    $preview.Show();$preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle);$preview.UpdateLayout()
    $scroll=[Windows.Media.VisualTreeHelper]::GetParent($image)
    while($scroll -and $scroll -isnot [Windows.Controls.ScrollViewer]){$scroll=[Windows.Media.VisualTreeHelper]::GetParent($scroll)}
    $surface=$preview.Content
    $top=$scroll.TranslatePoint([Windows.Point]::new(0,0),$surface).Y
    $location=$image.TranslatePoint([Windows.Point]::new(0,0),$surface)
    $x=[int]($location.X+$image.ActualWidth/2)
    Assert ((Pixel $surface $x ([int]($location.Y+$image.ActualHeight/2))) -eq '22,115,249,255') 'SVG is actually visible, with its original fill color'
    $header=Pixel $surface $x ([int]($top-20))
    $scroll.ScrollToVerticalOffset($location.Y-$top+45);$preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle);$preview.UpdateLayout()
    Assert ((Pixel $surface $x ([int]($top-20))) -eq $header) 'A partially scrolled SVG cannot paint over the header'
    Assert ((Pixel $surface $x ([int]($top+10))) -eq '22,115,249,255') 'The portion inside the scrolling viewport remains visible'
    $scroll.ScrollToVerticalOffset($location.Y+$image.ActualHeight-$top+10);$preview.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle);$preview.UpdateLayout()
    Assert ((Pixel $surface $x ([int]($top+10))) -ne '22,115,249,255') 'The logo disappears completely after scrolling beyond the viewport'
    Assert ((Get-DeployLogoPreview (Join-Path $PSScriptRoot 'TechMaster-Icon.svg')) -is [Windows.Media.DrawingImage]) 'Embedded PNG artwork in SVG also uses the native image path'
    $png=Join-Path $temp 'Logo.png';$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($preview.Icon))
    $stream=[IO.File]::Create($png);try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Assert ((Get-DeployLogoPreview $png) -is [Windows.Media.Imaging.BitmapImage]) 'PNG logo support is preserved'
    Remove-Item -LiteralPath $png -Force
    Assert (-not (Test-Path $png)) 'Raster preview releases its source file handle'
    [IO.File]::WriteAllText($svg,'<svg xmlns="http://www.w3.org/2000/svg"><use href="https://example.invalid/logo.svg#logo"/></svg>')
    $blocked=$false;try{Get-DeployLogoPreview $svg|Out-Null}catch{$blocked=$true}
    Assert $blocked 'Preview does not load external SVG references'
}finally{if($preview){$preview.Close()};if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks native SVG logo assertions; rendered pixels, partial/full scrolling, header clipping, embedded PNG and file handles."
