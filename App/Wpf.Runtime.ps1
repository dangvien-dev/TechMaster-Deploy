# Shared WPF helpers. Background pipelines never access UI controls.
function Initialize-DeployRoundedBorder([Windows.Controls.Border]$frame) {
    $content=$frame.Child
    if(-not $content){return}
    $stroke=$frame.BorderThickness
    $radius=[Math]::Max(0,$frame.CornerRadius.TopLeft-[Math]::Max([Math]::Max($stroke.Left,$stroke.Right),[Math]::Max($stroke.Top,$stroke.Bottom)))
    $frame.Child=$null
    # Clip the content, then paint a separate outline above it. Clipping the
    # complete frame lets opaque native controls cover the curved stroke.
    $frame.BorderThickness=[Windows.Thickness]::new(0)
    $layers=New-Object Windows.Controls.Grid
    $inside=New-Object Windows.Controls.Border
    $inside.Tag='RoundedContent';$inside.Margin=$stroke
    $inside.CornerRadius=[Windows.CornerRadius]::new($radius)
    $inside.Child=$content
    $inside.Add_SizeChanged({param($sender,$event)
        $r=[Math]::Min($sender.CornerRadius.TopLeft,[Math]::Min($sender.ActualWidth,$sender.ActualHeight)/2)
        $sender.Clip=[Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$sender.ActualWidth,$sender.ActualHeight),$r,$r)
    })
    $outline=New-Object Windows.Controls.Border
    $outline.Tag='RoundedOutline';$outline.BorderThickness=$stroke;$outline.IsHitTestVisible=$false
    foreach($property in 'CornerRadius','BorderBrush'){
        $binding=[Windows.Data.Binding]::new($property);$binding.Source=$frame
        [void]$outline.SetBinding([Windows.Controls.Border]::($property+'Property'),$binding)
    }
    [void]$layers.Children.Add($inside);[void]$layers.Children.Add($outline)
    $frame.Child=$layers
}
function Initialize-DeployRoundedButtons([Windows.Window]$window) {
    # Share the fallback template with the self-contained update helper too.
    # Existing window templates (including the main header) keep their styles.
    $rounded = [Windows.Markup.XamlReader]::Parse(@'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
 <Setter Property="Background" Value="#214674"/><Setter Property="Foreground" Value="White"/>
 <Setter Property="Padding" Value="16,10"/><Setter Property="Margin" Value="0,0,10,8"/>
 <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/>
 <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
 <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
  <Grid><Border x:Name="Surface" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
   <ContentPresenter x:Name="ButtonContent" HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
  </Border><Border x:Name="FocusOutline" BorderBrush="Transparent" BorderThickness="2" CornerRadius="8" IsHitTestVisible="False"/></Grid>
  <ControlTemplate.Triggers>
   <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.85"/></Trigger>
   <Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.7"/></Trigger>
   <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Surface" Property="Opacity" Value="0.45"/></Trigger>
   <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="FocusOutline" Property="BorderBrush" Value="#38BDF8"/></Trigger>
  </ControlTemplate.Triggers>
 </ControlTemplate></Setter.Value></Setter>
</Style>
'@)
    $template = @($rounded.Setters | Where-Object Property -eq ([Windows.Controls.Control]::TemplateProperty))[0].Value
    if (-not $window.Resources.Contains([Windows.Controls.Button])) { $window.Resources[[Windows.Controls.Button]] = $rounded }
    foreach ($key in @($window.Resources.Keys)) {
        $style = $window.Resources[$key]
        if ($style -isnot [Windows.Style] -or $style.TargetType -ne [Windows.Controls.Button]) { continue }
        $base = $style; $hasTemplate = $false
        while ($base) {
            foreach ($setter in $base.Setters) {
                if ($setter -is [Windows.Setter] -and $setter.Property -eq [Windows.Controls.Control]::TemplateProperty) { $hasTemplate = $true }
            }
            $base = $base.BasedOn
        }
        if ($hasTemplate) { continue }
        $replacement = [Windows.Style]::new([Windows.Controls.Button], $style)
        $replacement.Setters.Add([Windows.Setter]::new([Windows.Controls.Control]::TemplateProperty, $template))
        $replacement.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::FocusVisualStyleProperty, $null))
        $window.Resources[$key] = $replacement
    }
}
function Initialize-DeployTables([Windows.Window]$window) {
    # Visual settings only. Preserve each window's editability and column bindings.
    $theme = [Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style x:Key="Header" TargetType="DataGridColumnHeader">
  <Setter Property="Background" Value="#E7EEF8"/><Setter Property="Foreground" Value="#183655"/><Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Padding" Value="12,10"/><Setter Property="BorderBrush" Value="#DFE7F1"/><Setter Property="BorderThickness" Value="0,0,0,1"/>
  <Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="VerticalContentAlignment" Value="Center"/>
 </Style>
 <Style x:Key="Row" TargetType="DataGridRow">
  <Setter Property="MinHeight" Value="44"/><Setter Property="Foreground" Value="#10223F"/>
  <Style.Triggers>
   <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#F0F5FB"/></Trigger>
   <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#DBEAFE"/><Setter Property="Foreground" Value="#10223F"/></Trigger>
  </Style.Triggers>
 </Style>
 <Style x:Key="Cell" TargetType="DataGridCell">
  <Setter Property="Padding" Value="12,8"/><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#10223F"/>
  <Setter Property="BorderThickness" Value="0"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridCell">
   <Grid><Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/></Border>
    <Border x:Name="FocusOutline" BorderBrush="Transparent" BorderThickness="1" IsHitTestVisible="False"/>
   </Grid><ControlTemplate.Triggers><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="FocusOutline" Property="BorderBrush" Value="#38BDF8"/></Trigger></ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#10223F"/></Trigger></Style.Triggers>
 </Style>
 <Style x:Key="Table" TargetType="DataGrid">
  <Setter Property="Background" Value="White"/><Setter Property="Foreground" Value="#10223F"/><Setter Property="FontSize" Value="13"/>
  <Setter Property="RowBackground" Value="White"/><Setter Property="AlternatingRowBackground" Value="#F8FAFD"/>
  <Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="#E7EDF5"/>
  <Setter Property="ColumnHeaderHeight" Value="44"/><Setter Property="MinRowHeight" Value="44"/><Setter Property="RowHeaderWidth" Value="0"/>
  <Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="UseLayoutRounding" Value="True"/>
  <Setter Property="ColumnHeaderStyle" Value="{StaticResource Header}"/><Setter Property="RowStyle" Value="{StaticResource Row}"/><Setter Property="CellStyle" Value="{StaticResource Cell}"/>
 </Style>
</ResourceDictionary>
'@)
    $base = $window.Resources[[Windows.Controls.DataGrid]]
    $style = if($base -is [Windows.Style]){[Windows.Style]::new([Windows.Controls.DataGrid],$base)}else{[Windows.Style]::new([Windows.Controls.DataGrid])}
    foreach($setter in $theme['Table'].Setters){$style.Setters.Add([Windows.Setter]::new($setter.Property,$setter.Value))}
    $style.Setters.Add([Windows.Setter]::new([Windows.Controls.DataGrid]::RowHeightProperty,[double]::NaN))
    $window.Resources[[Windows.Controls.DataGrid]]=$style
}
function Import-DeployWindow([string]$path) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not ('TechMaster.DesktopIdentity' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'DesktopIdentity.cs') }
    [TechMaster.DesktopIdentity]::Initialize()
    $reader = [Xml.XmlReader]::Create($path, [Xml.XmlReaderSettings]@{ DtdProcessing = 'Prohibit'; XmlResolver = $null })
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    Initialize-DeployRoundedButtons $window
    Initialize-DeployTables $window
    $stream = [IO.File]::OpenRead((Join-Path $PSScriptRoot 'TechMaster.ico'))
    try {
        $icon = New-Object Windows.Media.Imaging.BitmapImage
        $icon.BeginInit(); $icon.CacheOption = 'OnLoad'; $icon.StreamSource = $stream; $icon.EndInit(); $icon.Freeze()
        $window.Icon = $icon
    } finally { $stream.Dispose() }
    $area=[Windows.SystemParameters]::WorkArea
    $initialHeight=[Math]::Max(320,$area.Height-30);$initialWidth=[Math]::Max(320,$area.Width-30)
    $window.MinHeight=[Math]::Min($window.MinHeight,$initialHeight)
    $window.MinWidth=[Math]::Min($window.MinWidth,$initialWidth)
    # Size the initial window, but let Windows maximize resizable windows to
    # the monitor work area. Permanent caps leave gaps at the right/bottom.
    if($window.ResizeMode -in 'NoResize','CanMinimize'){
        $window.MaxHeight=[Math]::Min($window.MaxHeight,$initialHeight)
        $window.MaxWidth=[Math]::Min($window.MaxWidth,$initialWidth)
    }
    if(-not [double]::IsNaN($window.Height)){$window.Height=[Math]::Min($window.Height,[Math]::Min($window.MaxHeight,$initialHeight))}
    if(-not [double]::IsNaN($window.Width)){$window.Width=[Math]::Min($window.Width,[Math]::Min($window.MaxWidth,$initialWidth))}
    # Clip only marked containers. Native input/grid/progress templates stay intact.
    $pending=New-Object Collections.Queue
    $pending.Enqueue($window)
    while($pending.Count){
        $element=$pending.Dequeue()
        if($element -is [Windows.Controls.Border] -and $element.Tag -ceq 'RoundedClip'){
            Initialize-DeployRoundedBorder $element
        }
        foreach($child in [Windows.LogicalTreeHelper]::GetChildren($element)){
            if($child -is [Windows.DependencyObject]){$pending.Enqueue($child)}
        }
    }
    return $window
}

function New-DeployTimer([int]$milliseconds, [scriptblock]$tick) {
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($milliseconds)
    $timer.Add_Tick($tick)
    return $timer
}

function Start-DeployWork([string]$code, [object[]]$arguments = @()) {
    $space = [RunspaceFactory]::CreateRunspace()
    $space.ApartmentState = 'STA'; $space.ThreadOptions = 'ReuseThread'
    $space.Open()
    $pipeline = [PowerShell]::Create()
    $pipeline.Runspace = $space
    $null = $pipeline.AddScript($code)
    foreach ($argument in $arguments) { $null = $pipeline.AddArgument($argument) }
    try {
        $async = $pipeline.BeginInvoke()
        return @{ Pipeline = $pipeline; Space = $space; Async = $async; Cancelled = $false }
    } catch { $pipeline.Dispose(); $space.Dispose(); throw }
}

function Request-DeployWorkCancel($work) {
    if ($work -and -not $work.Async.IsCompleted -and -not $work.Cancelled) {
        $work.Cancelled = $true
        $null = $work.Pipeline.BeginStop($null, $null)
    }
}

function Receive-DeployWork($work) {
    if (-not $work.Async.IsCompleted) { throw 'Background operation has not completed.' }
    try {
        $output = @($work.Pipeline.EndInvoke($work.Async))
        # Caught/suppressed cmdlet errors can set HadErrors without emitting an
        # error record. EndInvoke already throws terminating pipeline failures.
        if ($work.Pipeline.HadErrors -and $work.Pipeline.Streams.Error.Count) { throw $work.Pipeline.Streams.Error[0].Exception }
        return $output
    } finally { $work.Pipeline.Dispose(); $work.Space.Dispose() }
}

function New-DeployConfirmWindow([string]$message, [string]$title='Xác nhận', [string]$confirmText='Xác nhận', [string]$cancelText='Huỷ', [switch]$Danger, [switch]$Information, $Owner=$null) {
    $dialog = Import-DeployWindow (Join-Path $PSScriptRoot 'ConfirmWindow.xml')
    $dialog.Title = $title; $dialog.FindName('Heading').Text = $title
    $dialog.FindName('Message').Text = $message
    $dialog.FindName('Confirm').Content = $confirmText; $dialog.FindName('Cancel').Content = $cancelText
    $dialog.Tag = $false
    if ($Danger) { $dialog.FindName('Confirm').Background = '#B91C1C' }
    if ($Information) { $dialog.FindName('Cancel').Visibility='Collapsed'; $dialog.FindName('Cancel').IsDefault=$false; $dialog.FindName('Confirm').IsDefault=$true }
    if ($Owner -and $Owner.IsVisible) { $dialog.Owner=$Owner; $dialog.WindowStartupLocation='CenterOwner' }
    $dialog.FindName('Confirm').Add_Click({ param($sender,$event) $parent=[Windows.Window]::GetWindow($sender); $parent.Tag=$true; $parent.Close() })
    $dialog.FindName('Cancel').Add_Click({ param($sender,$event) [Windows.Window]::GetWindow($sender).Close() })
    return $dialog
}
function Show-DeployMessage([string]$message, [string]$title='TechMaster Deploy', [string]$icon='Information') {
    $dialog=New-DeployConfirmWindow $message $title 'Đóng' -Information -Danger:($icon -eq 'Error')
    [void]$dialog.ShowDialog()
}
function Confirm-Box([string]$message, [string]$title='Xác nhận', [string]$ConfirmText='Xác nhận', [string]$CancelText='Huỷ', [switch]$Danger, $Owner=$null) {
    $dialog=New-DeployConfirmWindow $message $title $ConfirmText $CancelText -Danger:$Danger -Owner $Owner
    [void]$dialog.ShowDialog()
    return $dialog.Tag -eq $true
}
function Select-DeployOption([string]$message, [string]$title, [string]$primaryText, [string]$alternateText) {
    $dialog=New-DeployConfirmWindow $message $title $primaryText
    $dialog.FindName('Alternate').Content=$alternateText; $dialog.FindName('Alternate').Visibility='Visible'
    $dialog.FindName('Alternate').Add_Click({param($sender,$event) $parent=[Windows.Window]::GetWindow($sender);$parent.Tag='Alternate';$parent.Close()})
    [void]$dialog.ShowDialog()
    if($dialog.Tag -eq $true){return 'Primary'}
    if($dialog.Tag -ceq 'Alternate'){return 'Alternate'}
    return $null
}
function Request-DeployText([string]$message, [string]$title='Nhập thông tin', [string]$defaultValue='') {
    $dialog=New-DeployConfirmWindow $message $title 'Tiếp tục'
    $dialog.FindName('Input').Visibility='Visible'; $dialog.FindName('Input').Text=$defaultValue
    [void]$dialog.ShowDialog()
    if ($dialog.Tag -eq $true) { return [string]$dialog.FindName('Input').Text }
    return $null
}

function Select-DeployFile([string]$title, [string]$filter) {
    $pick = New-Object Microsoft.Win32.OpenFileDialog
    $pick.Title = $title; $pick.Filter = $filter
    if ($pick.ShowDialog() -eq $true) { return $pick.FileName }
    return $null
}
