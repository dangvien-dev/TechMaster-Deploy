# Native WPF windows for folder sharing and client connection; dialogs, confirmation and workers are intercepted.
# Native checks use a throw-away Credential Manager entry and a share that does not exist.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
. (Join-Path $PSScriptRoot 'LanShare.Core.ps1')
. (Join-Path $PSScriptRoot 'LanShare.UI.ps1')
. (Join-Path $PSScriptRoot 'LanConnect.Core.ps1')
. (Join-Path $PSScriptRoot 'LanConnect.UI.ps1')
. (Join-Path $PSScriptRoot 'NetworkRun.UI.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
Initialize-DeployConnectNative
Assert ([bool]('TechMaster.LanConnectNative' -as [type])) 'Credential Manager / connection interop compiles on Windows PowerShell'
$probe='techmaster-test-'+[guid]::NewGuid().ToString('N')+'.invalid'
$secret=ConvertTo-SecureString 'Probe@2026' -AsPlainText -Force
$saved=$false
try{
    Assert ($null -eq [TechMaster.LanConnectNative]::SavedUser($probe)) 'A server without a saved password reads as none'
    try{[TechMaster.LanConnectNative]::SavePassword($probe,'PROBE\share',$secret);$saved=$true}
    catch{
        $native=$_.Exception.GetBaseException()
        if($native -is [ComponentModel.Win32Exception] -and $native.NativeErrorCode -eq 1312){Write-Host 'SKIP: this CI logon session has no Credential Manager store (1312); save / read / delete round trip not run.'}else{throw}
    }
    if($saved){Assert ([TechMaster.LanConnectNative]::SavedUser($probe) -ceq 'PROBE\share') 'A saved password is found again with its account'}
}finally{[void][TechMaster.LanConnectNative]::DeletePassword($probe)}
if($saved){Assert ($null -eq [TechMaster.LanConnectNative]::SavedUser($probe) -and -not [TechMaster.LanConnectNative]::DeletePassword($probe)) 'A removed password is gone'}
$code=[TechMaster.LanConnectNative]::TestConnection('\\127.0.0.1\TECHMASTER_NO_SUCH_SHARE','techmaster-no-user',$secret)
Assert ($code -ne 0) "Connecting to a share that does not exist reports an error code ($code) and saves nothing"
Assert ($null -eq [TechMaster.LanConnectNative]::SavedUser('127.0.0.1')) 'The connection test leaves no saved password behind'
$originalWorker=${function:Start-DeployWork}
$originalConfirm=${function:Confirm-Box}
$originalFolder=${function:Select-DeployFolder}
function Start-DeployWork([string]$code,[object[]]$arguments){$script:captured=@{Code=$code;Args=$arguments};@{Async=[pscustomobject]@{IsCompleted=$false}}}
function Confirm-Box([string]$message,[string]$title='Xác nhận',[string]$ConfirmText='Xác nhận',[string]$CancelText='Huỷ',[switch]$Danger,$Owner=$null){$script:prompt=$message;$script:answer}
function Click($window,$name){$window.FindName($name).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
function Reset-Window($window){$window.Tag.Timer.Stop();$window.Tag.Job=$null}
$share=New-DeployShareWindow
$connect=New-DeployConnectWindow
$run=New-DeployNetworkRunWindow 'D:\TechMaster-Deploy'
try{
    $pc=$env:COMPUTERNAME
    $state=[pscustomobject]@{Computer=$pc;
        Accounts=@([pscustomobject]@{Role='Scan';Name='scan';Account="$pc\scan";Exists=$true},[pscustomobject]@{Role='Share';Name='share';Account="$pc\share";Exists=$true},[pscustomobject]@{Role='Print';Name='print';Account="$pc\print";Exists=$false});
        Folder=[pscustomobject]@{Path='D:\KeToan';Warning='';DefaultName='KeToan'};FolderError='';Shares=@([pscustomobject]@{Name='Scan';Path='D:\Scan'});SharesError='';Existing=$null;CurrentAccess=@{};
        Firewall=@();FirewallReady=$false;Profiles=@([pscustomobject]@{Index=7;Alias='Wi-Fi';Name='VanPhong';Category='Public'},[pscustomobject]@{Index=12;Alias='Ethernet';Name='CongTy';Category='Private'});ProfileError='';Server='Running'}
    Set-DeployShareView $share $state
    Assert ($share.FindName('FolderPath').Text -ceq 'D:\KeToan' -and $share.FindName('ShareName').Text -ceq 'KeToan' -and $share.FindName('ShareHint').Text.Contains("\\$pc\KeToan")) 'A chosen folder fills the share name and the network path'
    Assert ((Get-DeployShareAccessChoice $share.FindName('AccessShare')) -ceq 'Change' -and (Get-DeployShareAccessChoice $share.FindName('AccessScan')) -ceq 'None' -and -not $share.FindName('AccessPrint').IsEnabled -and $share.FindName('AccessNotePrint').Text -match 'Chưa có tài khoản') 'A new share starts with share = read & write; accounts that do not exist cannot be chosen'
    Assert ($share.FindName('MakePrivate').IsEnabled -and $share.FindName('MakePrivate').IsChecked -ne $true -and $share.FindName('NetworkState').Text -match 'VanPhong' -and $share.FindName('SharesList').Text.Contains("\\$pc\Scan")) 'A Public network is shown and can be switched only on request; existing shares are listed'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        foreach($window in $share,$connect){$window.Content.Measure($size);$window.Content.Arrange([Windows.Rect]::new($size));$window.UpdateLayout()}
        Assert ($share.FindName('Apply').ActualHeight -gt 0 -and $share.FindName('Browse').ActualWidth -gt 0 -and $share.FindName('AccessShare').ActualWidth -gt 40 -and $connect.FindName('Connect').ActualHeight -gt 0 -and $connect.FindName('Password').ActualWidth -gt 40) "Share and connection windows are laid out at $scale"
    }
    $existing=$state.PSObject.Copy();$existing.Folder=[pscustomobject]@{Path='D:\Scan';Warning='';DefaultName='Scan'};$existing.Existing=[pscustomobject]@{Name='ScanDocs';Path='D:\Scan'};$existing.CurrentAccess=@{"$pc\scan"='Change';"$pc\share"='Read';"$pc\print"='None'}
    Set-DeployShareView $share $existing
    Assert ($share.FindName('ShareName').Text -ceq 'ScanDocs' -and (Get-DeployShareAccessChoice $share.FindName('AccessScan')) -ceq 'Change' -and (Get-DeployShareAccessChoice $share.FindName('AccessShare')) -ceq 'Read' -and $share.FindName('FolderNote').Text -match 'đang được chia sẻ') 'An already shared folder loads its name and current permissions'
    Set-DeployShareView $share $state
    function Select-DeployFolder([string]$Description,[string]$Start=''){'D:\Moi'}
    $script:captured=$null;Click $share 'Browse'
    Assert ($share.FindName('FolderPath').Text -ceq 'D:\Moi' -and $script:captured.Args[1] -ceq 'Inspect' -and $script:captured.Args[2] -ceq 'D:\Moi') 'Choosing a folder reads its sharing state in the background'
    Reset-Window $share;Set-DeployShareBusy $share $false
    $share.FindName('ShareName').Text='Bad$';$script:captured=$null
    Click $share 'Apply'
    Assert ($null -eq $script:captured -and $share.FindName('Status').Text -match 'Tên chia sẻ') 'An invalid share name stops before confirmation'
    $share.FindName('ShareName').Text='KeToan'
    foreach($role in 'Scan','Share','Print'){Set-DeployShareAccessChoice ($share.FindName('Access'+$role)) 'None'}
    Click $share 'Apply'
    Assert ($null -eq $script:captured -and $share.FindName('Status').Text -match 'ít nhất một') 'Sharing without any access is refused'
    Set-DeployShareAccessChoice ($share.FindName('AccessShare')) 'Change';Set-DeployShareAccessChoice ($share.FindName('AccessScan')) 'Read'
    $share.FindName('MakePrivate').IsChecked=$true;$script:answer=$false
    Click $share 'Apply'
    Assert ($null -eq $script:captured -and $script:prompt.Contains("\\$pc\KeToan") -and $script:prompt -match 'share: Đọc & ghi' -and $script:prompt -match 'Private') 'Cancelled confirmation shares nothing and listed the permissions'
    $script:answer=$true
    Click $share 'Apply'
    $grants=@($script:captured.Args[4])
    Assert ($share.Tag.Job -and $script:captured.Args[1] -ceq 'Apply' -and $script:captured.Args[2] -ceq 'D:\Moi' -and $script:captured.Args[3] -ceq 'KeToan' -and $grants.Count -eq 3 -and @($grants | Where-Object {$_.Role -eq 'Share' -and $_.Access -eq 'Change'}).Count -eq 1 -and @($grants | Where-Object {$_.Role -eq 'Scan' -and $_.Access -eq 'Read'}).Count -eq 1 -and $script:captured.Args[5] -eq $true -and (@($script:captured.Args[6]) -join ',') -ceq '7') 'Confirmed sharing sends folder, name, permissions, firewall and only the Public network to change'
    Assert (-not $share.FindName('Choices').IsEnabled -and -not $share.FindName('Close').IsEnabled) 'The share window is locked while the worker runs'
    Reset-Window $share;Set-DeployShareBusy $share $false

    Assert ($connect.FindName('Account').Text -ceq 'share' -and @($connect.FindName('Drive').ItemsSource)[0] -ceq 'Không' -and $connect.FindName('Drive').SelectedItem -ceq 'Không' -and $connect.FindName('Shortcut').IsChecked -eq $true) 'The connection window starts with the share account, a desktop shortcut and no drive letter'
    $connect.FindName('UncPath').Text='KY-THUAT\KeToan';$script:captured=$null
    Click $connect 'Connect'
    Assert ($null -eq $script:captured -and $connect.FindName('Status').Text -match 'TÊN-MÁY') 'A path without \\ is refused before anything runs'
    $connect.FindName('UncPath').Text='\\KY-THUAT\KeToan'
    Click $connect 'Connect'
    Assert ($null -eq $script:captured -and $connect.FindName('Status').Text -match 'mật khẩu') 'An empty password is refused'
    $connect.FindName('Password').Password='Share@2026'
    Click $connect 'Connect'
    Assert ($connect.Tag.Job -and $script:captured.Args[1] -ceq 'Connect' -and $script:captured.Args[2] -ceq '\\KY-THUAT\KeToan' -and $script:captured.Args[3] -ceq 'share' -and $script:captured.Args[4] -is [Security.SecureString] -and $script:captured.Args[4].IsReadOnly() -and $script:captured.Args[5] -eq $true -and $script:captured.Args[6] -ceq '') 'The connection request carries the password only as read-only SecureString'
    Reset-Window $connect;Set-DeployConnectBusy $connect $false
    $script:answer=$false;$script:captured=$null
    Click $connect 'RemoveSaved'
    Assert ($null -eq $script:captured -and $script:prompt -match 'KY-THUAT') 'Removing a saved password asks first'
    $script:answer=$true
    Click $connect 'RemoveSaved'
    Assert ($connect.Tag.Job -and $script:captured.Args[1] -ceq 'Remove' -and $null -eq $script:captured.Args[4]) 'Removal sends no password'
    Reset-Window $connect;Set-DeployConnectBusy $connect $false

    $paths=@("\\$pc\TechMaster`$\App\Chay-Tu-Mang.bat","\\192.168.1.20\TechMaster`$\App\Chay-Tu-Mang.bat")
    $runState=[pscustomobject]@{Computer=$pc;Root='D:\TechMaster-Deploy';RootError='';SourceProblems=@();Share=$null;ShareError='';Active=$false;Account='';
        Accounts=@([pscustomobject]@{Account="$pc\tech";Label="$pc\tech (tài khoản đang dùng)";Lan=$false},[pscustomobject]@{Account="$pc\share";Label="$pc\share (tài khoản LAN chỉ dùng qua mạng)";Lan=$true});
        Firewall=@();FirewallReady=$false;Profiles=$state.Profiles;ProfileError='';Server='Running';Addresses=@('192.168.1.20');ClientPaths=$paths}
    Set-DeployNetworkRunView $run $runState
    Assert ($run.FindName('ClientPath').Text -ceq $paths[0] -and $run.FindName('ClientNote').Text.Contains($paths[1]) -and $run.FindName('Account').SelectedItem.Account -ceq "$pc\tech") 'The other computer gets the launcher path by name and by IP; the account using the app is offered first'
    Assert (-not $run.FindName('StopShare').IsEnabled -and $run.FindName('Apply').Content -ceq 'Chia sẻ TechMaster' -and $run.FindName('MakePrivate').IsEnabled -and $run.FindName('RootNote').Text -match 'Chưa chia sẻ' -and $run.FindName('NetworkState').Text -match 'VanPhong') 'Not shared yet: nothing to stop, the Public network can be switched on request'
    foreach($scale in 1.0,1.25,1.5){
        $size=[Windows.Size]::new((1024/$scale),(768/$scale))
        $run.Content.Measure($size);$run.Content.Arrange([Windows.Rect]::new($size));$run.UpdateLayout()
        Assert ($run.FindName('Apply').ActualHeight -gt 0 -and $run.FindName('StopShare').ActualWidth -gt 0 -and $run.FindName('ClientPath').ActualWidth -gt 200 -and $run.FindName('Account').ActualWidth -gt 200) "Network run window is laid out at $scale"
    }
    $run.FindName('Account').SelectedIndex=1;$run.FindName('MakePrivate').IsChecked=$true
    $script:answer=$false;$script:captured=$null
    Click $run 'Apply'
    Assert ($null -eq $script:captured -and $script:prompt.Contains("\\$pc\TechMaster`$") -and $script:prompt.Contains("$pc\share") -and $script:prompt -match 'chỉ đọc' -and $script:prompt -match 'Private') 'Cancelled sharing changes nothing and named the share, account and network change'
    $script:answer=$true
    Click $run 'Apply'
    Assert ($run.Tag.Job -and $script:captured.Args[1] -ceq 'Apply' -and $script:captured.Args[2] -ceq 'D:\TechMaster-Deploy' -and $script:captured.Args[3] -ceq "$pc\share" -and $script:captured.Args[4] -eq $true -and (@($script:captured.Args[5]) -join ',') -ceq '7') 'Confirmed sharing sends the program folder, account, firewall and only the Public network'
    Assert (-not $run.FindName('Choices').IsEnabled -and -not $run.FindName('Close').IsEnabled -and -not $run.FindName('StopShare').IsEnabled) 'The window is locked while the worker runs'
    Reset-Window $run;Set-DeployNetworkRunBusy $run $false
    $active=$runState.PSObject.Copy();$active.Share=[pscustomobject]@{Name='TechMaster$';Path='D:\TechMaster-Deploy';Ours=$true;Access=@([pscustomobject]@{Account="$pc\share";Right='Read'})};$active.Active=$true;$active.Account="$pc\share"
    Set-DeployNetworkRunView $run $active
    Assert ($run.FindName('StopShare').IsEnabled -and $run.FindName('Apply').Content -ceq 'Cập nhật chia sẻ' -and $run.FindName('Account').SelectedItem.Account -ceq "$pc\share" -and $run.FindName('RootNote').Text -match 'Đang chia sẻ') 'An active share can be updated or stopped and keeps its account'
    $script:answer=$true;$script:captured=$null
    Click $run 'StopShare'
    Assert ($run.Tag.Job -and $script:captured.Args[1] -ceq 'Stop' -and $script:captured.Args[3] -ceq '' -and $script:prompt -match 'Ngừng chia sẻ') 'Stopping asks first and sends no account'
    Reset-Window $run;Set-DeployNetworkRunBusy $run $false
    $broken=$runState.PSObject.Copy();$broken.RootError='Thư mục TechMaster thiếu update-source.json.'
    Set-DeployNetworkRunView $run $broken;$script:captured=$null
    Click $run 'Apply'
    Assert ($null -eq $script:captured -and $run.FindName('Status').Text -match 'thiếu update-source.json' -and $run.FindName('RootNote').Text -match '✗') 'A folder that cannot be shared stops before confirmation'
    $changed=$runState.PSObject.Copy();$changed.SourceProblems=@('App/MainWindow.xml')
    Set-DeployNetworkRunView $run $changed
    Assert ($run.FindName('RootNote').Text -match 'App/MainWindow.xml') 'Changed program files are named before sharing'
}finally{
    Set-Item Function:Start-DeployWork $originalWorker;Set-Item Function:Confirm-Box $originalConfirm;Set-Item Function:Select-DeployFolder $originalFolder
    foreach($window in $share,$connect,$run){$window.Tag.Job=$null;$window.Close();$window.Tag.Timer.Stop()}
}
Write-Host "PASS: $checks native LAN share / connection / network run assertions; Credential Manager round trip, failed connection saves nothing, folder choice, permissions, network profile and worker arguments."
