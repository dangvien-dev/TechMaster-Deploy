param([switch]$AfterClone, [switch]$ValidateOnly, [string]$OptionsPath='')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'Master.Preflight.Core.ps1')
$window=Import-DeployWindow (Join-Path $PSScriptRoot 'Master-Preflight.xml')
$script:preflight = @{ Plan=@(); Allowed=$false }
if ($AfterClone) { $window.FindName('DeploymentOptions').Visibility='Collapsed'; $window.Title='Desktop và phím chụp màn hình'; $window.FindName('Continue').Content='Đóng'; $window.FindName('Continue').IsEnabled=$true }
function Refresh-Preflight {
    try {
        $script:preflight.Plan = @(Get-OfficeShortcutPlan)
        $lines = @($script:preflight.Plan | ForEach-Object { $_.App + ': ' + @($_.Remove).Count + ' shortcut trùng; ' + $(if ($_.Create) { 'sẽ tạo 1 icon dùng chung.' } else { 'đã có icon dùng chung.' }) })
        $window.FindName('DesktopStatus').Text = if ($lines.Count) { $lines -join "`n" } else { 'Không tìm thấy shortcut Word / Excel hợp lệ.' }
        $window.FindName('CleanDesktop').IsEnabled = @($script:preflight.Plan | Where-Object { $_.Create -or @($_.Remove).Count }).Count -gt 0
    } catch { $script:preflight.Plan=@(); $window.FindName('DesktopStatus').Text=$_.Exception.Message; $window.FindName('CleanDesktop').IsEnabled=$false }
    $window.FindName('ScreenStatus').Text = if (Get-ScreenClipChoice) { 'Đã có lựa chọn mặc định. Kiểm tra đúng Screen Snipping; lựa chọn này sẽ được xuất cho user mới.' } else { 'Chưa có lựa chọn mặc định; chọn Screen Snipping và Always trước khi Sysprep.' }
}
$script:officeReview=$null;$script:windowsReview=$null
$window.FindName('ReviewOfficeKeys').Add_Click({
    if($script:officeReview -and -not $script:officeReview.HasExited){return}
    $entry=Join-Path (Split-Path -Parent $PSScriptRoot) 'Office/Office-Cleanup.ps1'
    $command="& '{0}'" -f $entry.Replace("'","''")
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $script:officeReview=Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -WindowStyle Hidden -PassThru
})
$window.FindName('ReviewWindowsKey').Add_Click({
    if($script:windowsReview -and -not $script:windowsReview.HasExited){return}
    $entry=Join-Path $PSScriptRoot 'Windows-SetupKey.ps1'
    $command="& '{0}'" -f $entry.Replace("'","''")
    $script:windowsReview=Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))) -WindowStyle Hidden -PassThru
})
$window.FindName('OpenCapture').Add_Click({ Start-Process 'ms-screenclip:' })
$window.FindName('OpenDefaults').Add_Click({ Start-Process 'ms-settings:defaultapps' })
$window.FindName('Refresh').Add_Click({ Refresh-Preflight })
$window.FindName('CleanDesktop').Add_Click({
    if (-not (Confirm-Box 'Sao lưu và dọn các icon cùng trỏ tới Word / Excel, giữ một icon dùng chung? Thiết lập Word và tài liệu được giữ nguyên.' 'Dọn icon trùng' -ConfirmText 'Sao lưu và dọn' -Owner $window)) { return }
    try {
        $backup = Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Desktop Backups/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
        Invoke-OfficeShortcutPlan $script:preflight.Plan $backup
        Refresh-Preflight
        Show-DeployMessage ('Đã dọn icon. Sao lưu: '+$backup) 'Desktop'
    } catch { Show-DeployMessage $_.Exception.Message 'Chưa dọn được Desktop' 'Error'; Refresh-Preflight }
})
$changed = {
    if (-not $AfterClone) { $window.FindName('Continue').IsEnabled = $window.FindName('ScreenReviewed').IsChecked -and $window.FindName('DesktopReviewed').IsChecked }
}
$window.FindName('ScreenReviewed').Add_Click($changed); $window.FindName('DesktopReviewed').Add_Click($changed)
$window.FindName('Continue').Add_Click({
    if($script:officeReview -and -not $script:officeReview.HasExited){Show-DeployMessage 'Đóng cửa sổ Gỡ / dọn Office trước khi tiếp tục.';return}
    if($script:windowsReview -and -not $script:windowsReview.HasExited){Show-DeployMessage 'Đóng cửa sổ Key cài đặt chung Windows trước khi tiếp tục.';return}
    if($OptionsPath -and -not $AfterClone) {
        $options=[pscustomobject]@{Schema=1;CleanOfficeTrial=[bool]$window.FindName('CleanOfficeTrial').IsChecked;PrepareUltra=[bool]$window.FindName('PrepareUltra').IsChecked;CleanWindowsSetupKey=[bool]$window.FindName('CleanWindowsSetupKey').IsChecked}
        [IO.File]::WriteAllText($OptionsPath,($options|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    $script:preflight.Allowed=$true; $window.Close()
})
$window.FindName('Cancel').Add_Click({ $window.Close() })
$script:trialCheck=$null
$trialTimer=New-DeployTimer 200 {
    if(-not $script:trialCheck -or -not $script:trialCheck.Async.IsCompleted){return}
    $trialTimer.Stop();$job=$script:trialCheck;$script:trialCheck=$null
    try{$result=@(Receive-DeployWork $job)[-1];$window.FindName('TrialStatus').Text=$result}
    catch{$window.FindName('TrialStatus').Text='Chưa đọc được đầy đủ Windows / Office. Bước cuối sẽ kiểm tra lại và dừng nếu không xác minh được.'}
}
$window.Add_ContentRendered({
    if(-not $AfterClone){
        $office=Join-Path (Split-Path -Parent $PSScriptRoot) 'Office/Office-Cleanup.Core.ps1'
        $script:trialCheck=Start-DeployWork 'param($core,$windowsCore) $ErrorActionPreference="Stop"; . $core; . $windowsCore; $w=Get-WindowsSetupKeyInventory; $i=Get-OfficeCleanupInventory; $p=Get-OfficeTemporaryPlan $i; "Key dùng thử có thể dọn: $(@($p.Keys).Count). Key khác giữ lại: $(@($p.PreservedKeys).Count).`nWindows: $(@($w.Items|Where-Object Eligible).Count) key chung Pro chưa kích hoạt đủ điều kiện dọn; key khác giữ nguyên."' @($office,(Join-Path $PSScriptRoot 'Windows.License.Core.ps1'))
        $trialTimer.Start()
    }
})
$window.Add_Closing({param($sender,$event)if($script:trialCheck -or ($script:officeReview -and -not $script:officeReview.HasExited) -or ($script:windowsReview -and -not $script:windowsReview.HasExited)){$event.Cancel=$true}})
Refresh-Preflight
if ($ValidateOnly) { return $window }
[void]$window.ShowDialog()
if (-not $script:preflight.Allowed -and -not $AfterClone) { exit 1 }
