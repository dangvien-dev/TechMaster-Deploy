# Shared WPF helpers. Background pipelines never access UI controls.
function Import-DeployWindow([string]$path) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $reader = [Xml.XmlReader]::Create($path, [Xml.XmlReaderSettings]@{ DtdProcessing = 'Prohibit'; XmlResolver = $null })
    try { return [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
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

function Show-DeployMessage([string]$message, [string]$title = 'TechMaster Deploy', [string]$icon = 'Information') {
    [void][Windows.MessageBox]::Show($message, $title, 'OK', $icon)
}

function Confirm-Box([string]$message, [string]$title = 'Xác nhận') {
    return [Windows.MessageBox]::Show($message, $title, 'YesNo', 'Warning', 'No') -eq 'Yes'
}

function Select-DeployFile([string]$title, [string]$filter) {
    $pick = New-Object Microsoft.Win32.OpenFileDialog
    $pick.Title = $title; $pick.Filter = $filter
    if ($pick.ShowDialog() -eq $true) { return $pick.FileName }
    return $null
}
