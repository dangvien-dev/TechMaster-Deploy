# Native WPF window and read-only native checks. Worker startup and confirmation are intercepted; no account is created.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'LanAccounts.Core.ps1')
. (Join-Path $PSScriptRoot 'LanAccounts.UI.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
Initialize-DeployLanNative
Assert ([bool]('TechMaster.LanAccountsNative' -as [type])) 'LSA / group / SecureString interop compiles on Windows PowerShell'
$rights=@([TechMaster.LanAccountsNative]::GetRights('S-1-5-32-544'))
Assert ($rights.Count -gt 0 -and @($rights | Where-Object {$_ -match '^Se[A-Za-z]+(Right|Privilege)$'}).Count -eq $rights.Count) 'LSA rights are read for the built-in Administrators group'
$me=[Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
Assert (@([TechMaster.LanAccountsNative]::LocalGroupSids($me)) -contains 'S-1-5-32-544') 'Local group membership is read as SIDs (the runner account is an administrator)'
$same1=ConvertTo-SecureString 'Same@2026' -AsPlainText -Force;$same2=ConvertTo-SecureString 'Same@2026' -AsPlainText -Force;$other=ConvertTo-SecureString 'Same@2027' -AsPlainText -Force
Assert ((Test-DeployLanPasswordMatch $same1 $same2) -and -not (Test-DeployLanPasswordMatch $same1 $other) -and -not (Test-DeployLanPasswordMatch $same1 (New-Object Security.SecureString))) 'Passwords are compared without plain-text strings'
$view=New-DeployLanAccountsWindow
$originalWorker=${function:Start-DeployWork}
$originalConfirm=${function:Confirm-Box}
function Click($name){$view.FindName($name).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
function Reset-View{$view.Tag.Timer.Stop();$view.Tag.Job=$null;Set-DeployLanAccountsBusy $view $false;Set-DeployLanAccountsView $view $view.Tag.States}
try{
    $states=@(
        [pscustomobject]@{Role='Scan';Name='scan';CanApply=$true;Status='Chưa có: sẽ tạo mới';Error=''},
        [pscustomobject]@{Role='Share';Name='share';CanApply=$false;Status="Đã có tài khoản 'share' không do TechMaster tạo: không thay đổi.";Error=''},
        [pscustomobject]@{Role='Print';Name='print';CanApply=$true;Status='Đã có (TechMaster tạo). Nhập mật khẩu mới nếu muốn đổi.';Error=''})
    Set-DeployLanAccountsView $view $states
    Assert ($view.FindName('StateScan').Text -match 'Chưa có' -and -not $view.FindName('UseShare').IsEnabled -and -not $view.FindName('PasswordShare').IsEnabled -and -not $view.FindName('ConfirmShare').IsEnabled -and $view.FindName('UsePrint').IsEnabled) 'An account not created by TechMaster cannot be selected or given a password'
    Assert ($view.FindName('Computer').Text -match [regex]::Escape($env:COMPUTERNAME+'\scan')) 'The window shows the network sign-in names'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        $view.Content.Measure($size);$view.Content.Arrange([Windows.Rect]::new($size));$view.UpdateLayout()
        Assert ($view.FindName('Apply').ActualHeight -gt 0 -and $view.FindName('Close').ActualWidth -gt 0 -and $view.FindName('PasswordScan').ActualWidth -gt 40 -and $view.FindName('ConfirmPrint').ActualWidth -gt 40) "Password fields and footer actions are laid out at $scale"
        Assert ($view.FindName('PasswordScan').Parent.CornerRadius.TopLeft -gt 0) 'Password fields use the rounded shared frame'
    }
    function Start-DeployWork([string]$code,[object[]]$arguments){$script:captured=@{Code=$code;Args=$arguments};@{Async=[pscustomobject]@{IsCompleted=$false}}}
    function Confirm-Box([string]$message,[string]$title='Xác nhận',[string]$ConfirmText='Xác nhận',[string]$CancelText='Huỷ',[switch]$Danger,$Owner=$null){$script:prompt=$message;$script:answer}
    $view.FindName('PasswordScan').Password='Kt@2026scan'
    Assert ($view.FindName('UseScan').IsChecked -eq $true -and $view.FindName('UsePrint').IsChecked -ne $true) 'Typing a password selects only that account'
    $view.FindName('ConfirmScan').Password='Kt@2026scaN';$script:captured=$null
    Click 'Apply'
    Assert (-not $view.Tag.Job -and $null -eq $script:captured -and $view.FindName('Status').Text -match 'chưa khớp') 'Mismatched passwords stop before confirmation'
    $view.FindName('ConfirmScan').Password='Kt@2026scan';$script:answer=$false
    Click 'Apply'
    Assert (-not $view.Tag.Job -and $null -eq $script:captured -and $script:prompt -match 'scan' -and -not ($script:prompt -match 'Kt@2026')) 'Cancelled confirmation creates nothing and never shows the password'
    $script:answer=$true
    Click 'Apply'
    $requests=@($script:captured.Args[2])
    Assert ($view.Tag.Job -and $script:captured.Args[1] -ceq 'Apply' -and $requests.Count -eq 1 -and $requests[0].Role -ceq 'Scan' -and $requests[0].Password -is [Security.SecureString] -and $requests[0].Password.Length -eq 11 -and $requests[0].Password.IsReadOnly()) 'Confirmed request sends only the selected account with its password as read-only SecureString'
    Assert (-not $view.FindName('Choices').IsEnabled -and -not $view.FindName('Close').IsEnabled) 'The window is locked while the worker runs'
    Reset-View
    Clear-DeployLanPasswords $view
    Assert ($view.FindName('PasswordScan').SecurePassword.Length -eq 0 -and $view.FindName('UseScan').IsChecked -ne $true) 'Passwords are cleared from the window'
    $view.FindName('UsePrint').IsChecked=$true;$script:captured=$null
    Click 'Apply'
    Assert (-not $view.Tag.Job -and $null -eq $script:captured -and $view.FindName('Status').Text -match 'Nhập mật khẩu cho print') 'A ticked account without a password is refused'
    $view.FindName('UsePrint').IsChecked=$false
    Click 'Apply'
    Assert (-not $view.Tag.Job -and $view.FindName('Status').Text -match 'Tích ít nhất') 'Nothing selected starts nothing'
    Click 'Refresh'
    Assert ($view.Tag.Job -and $script:captured.Args[1] -ceq 'Inspect' -and @($script:captured.Args[2]).Count -eq 0) 'Refresh reads accounts without sending any password'
    Reset-View
}finally{Set-Item Function:Start-DeployWork $originalWorker;Set-Item Function:Confirm-Box $originalConfirm;$view.Tag.Job=$null;$view.Close();$view.Tag.Timer.Stop()}
Write-Host "PASS: $checks native LAN account UI assertions; LSA / group / SecureString interop, locked accounts, password checks, confirmation and worker arguments."
