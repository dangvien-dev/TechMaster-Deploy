# Shared WPF helpers. Background pipelines never access UI controls.
function Import-DeployWindow([string]$path) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not ('TechMaster.DesktopIdentity' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'DesktopIdentity.cs') }
    [TechMaster.DesktopIdentity]::Initialize()
    $reader = [Xml.XmlReader]::Create($path, [Xml.XmlReaderSettings]@{ DtdProcessing = 'Prohibit'; XmlResolver = $null })
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $stream = [IO.File]::OpenRead((Join-Path $PSScriptRoot 'TechMaster.ico'))
    try {
        $icon = New-Object Windows.Media.Imaging.BitmapImage
        $icon.BeginInit(); $icon.CacheOption = 'OnLoad'; $icon.StreamSource = $stream; $icon.EndInit(); $icon.Freeze()
        $window.Icon = $icon
    } finally { $stream.Dispose() }
    $area=[Windows.SystemParameters]::WorkArea
    $window.MinHeight=[Math]::Min($window.MinHeight,[Math]::Max(320,$area.Height-30))
    $window.MaxHeight=[Math]::Min($window.MaxHeight,$area.Height-30)
    if(-not [double]::IsNaN($window.Height)){$window.Height=[Math]::Min($window.Height,$window.MaxHeight)}
    $window.MinWidth=[Math]::Min($window.MinWidth,[Math]::Max(320,$area.Width-30))
    $window.MaxWidth=[Math]::Min($window.MaxWidth,$area.Width-30)
    if(-not [double]::IsNaN($window.Width)){$window.Width=[Math]::Min($window.Width,$window.MaxWidth)}
    # Clip only marked containers. Native input/grid/progress templates stay intact.
    $pending=New-Object Collections.Queue
    $pending.Enqueue($window)
    while($pending.Count){
        $element=$pending.Dequeue()
        if($element -is [Windows.Controls.Border] -and $element.Tag -ceq 'RoundedClip'){
            $element.Add_SizeChanged({param($sender,$event)
                $radius=[Math]::Min($sender.CornerRadius.TopLeft,[Math]::Min($sender.ActualWidth,$sender.ActualHeight)/2)
                $sender.Clip=[Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$sender.ActualWidth,$sender.ActualHeight),$radius,$radius)
            })
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
        if ($work.Pipeline.HadErrors) { throw $work.Pipeline.Streams.Error[0].Exception }
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
