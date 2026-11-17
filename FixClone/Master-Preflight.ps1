param([switch]$AfterClone, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'Master.Preflight.Core.ps1')
$reader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'Master-Preflight.xml'), [Xml.XmlReaderSettings]@{ DtdProcessing='Prohibit';XmlResolver=$null })
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$script:preflight = @{ Plan=@(); Allowed=$false }
if ($AfterClone) { $window.Title='Desktop và phím chụp màn hình'; $window.FindName('Continue').Content='Đóng'; $window.FindName('Continue').IsEnabled=$true }
function Refresh-Preflight {
    try {
        $script:preflight.Plan = @(Get-OfficeShortcutPlan)
        $lines = @($script:preflight.Plan | ForEach-Object { $_.App + ': ' + @($_.Remove).Count + ' shortcut trùng; ' + $(if ($_.Create) { 'sẽ tạo 1 icon dùng chung.' } else { 'đã có icon dùng chung.' }) })
        $window.FindName('DesktopStatus').Text = if ($lines.Count) { $lines -join "`n" } else { 'Không tìm thấy shortcut Word / Excel hợp lệ.' }
        $window.FindName('CleanDesktop').IsEnabled = @($script:preflight.Plan | Where-Object { $_.Create -or @($_.Remove).Count }).Count -gt 0
    } catch { $script:preflight.Plan=@(); $window.FindName('DesktopStatus').Text=$_.Exception.Message; $window.FindName('CleanDesktop').IsEnabled=$false }
    $window.FindName('ScreenStatus').Text = if (Get-ScreenClipChoice) { 'Đã có lựa chọn mặc định. Kiểm tra đúng Screen Snipping; lựa chọn này sẽ được xuất cho user mới.' } else { 'Chưa có lựa chọn mặc định; chọn Screen Snipping và Always trước khi Sysprep.' }
}
$window.FindName('OpenCapture').Add_Click({ Start-Process 'ms-screenclip:' })
$window.FindName('OpenDefaults').Add_Click({ Start-Process 'ms-settings:defaultapps' })
$window.FindName('Refresh').Add_Click({ Refresh-Preflight })
$window.FindName('CleanDesktop').Add_Click({
    if ([Windows.MessageBox]::Show('Sao lưu và dọn các icon cùng trỏ tới Word / Excel, giữ một icon dùng chung? Thiết lập Word và tài liệu được giữ nguyên.','Dọn icon trùng','YesNo','Question','No') -ne 'Yes') { return }
    try {
        $backup = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Desktop Backups/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
        Invoke-OfficeShortcutPlan $script:preflight.Plan $backup
        Refresh-Preflight
        [void][Windows.MessageBox]::Show('Đã dọn icon. Sao lưu: '+$backup,'Desktop','OK','Information')
    } catch { [void][Windows.MessageBox]::Show($_.Exception.Message,'Chưa dọn được Desktop','OK','Error'); Refresh-Preflight }
})
$changed = {
    if (-not $AfterClone) { $window.FindName('Continue').IsEnabled = $window.FindName('ScreenReviewed').IsChecked -and $window.FindName('DesktopReviewed').IsChecked }
}
$window.FindName('ScreenReviewed').Add_Click($changed); $window.FindName('DesktopReviewed').Add_Click($changed)
$window.FindName('Continue').Add_Click({ $script:preflight.Allowed=$true; $window.Close() })
$window.FindName('Cancel').Add_Click({ $window.Close() })
Refresh-Preflight
if ($ValidateOnly) { return $window }
[void]$window.ShowDialog()
if (-not $script:preflight.Allowed -and -not $AfterClone) { exit 1 }
