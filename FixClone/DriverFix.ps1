param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'DriverFix.Engine.ps1')
. (Join-Path $PSScriptRoot 'DriverFix.Report.ps1')
if(-not $ValidateOnly -and -not (Test-DriverFixAdmin)){
    $command="& '{0}'" -f $PSCommandPath.Replace("'","''")
    try{Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))|Out-Null}
    catch{Show-DeployMessage 'Cần chấp nhận quyền Administrator để cài / disable thiết bị.' 'Fix Driver'}
    return
}
$driverWindow=Import-DeployWindow (Join-Path $PSScriptRoot 'DriverFix.xml')
$script:driverFix=@{Session=$null;Work=$null;PowerBoxes=@();Closing=$false}
function Set-DriverFixStatus([string]$Text,[ValidateSet('Info','Working','Attention','Success','Error')][string]$Kind='Info'){Set-DeployNotice ($driverWindow.FindName('Status')) $Text $Kind}
function Select-DriverFixFolder([string]$Title){
    Add-Type -AssemblyName System.Windows.Forms
    $picker=New-Object Windows.Forms.FolderBrowserDialog;$picker.Description=$Title;$picker.ShowNewFolderButton=$false
    try{if($picker.ShowDialog() -eq 'OK'){return $picker.SelectedPath};return $null}finally{$picker.Dispose()}
}
function Update-DriverFixSelection {
    $device=$driverWindow.FindName('Devices').SelectedItem
    $driverWindow.FindName('Disable').IsEnabled=$false
    if(-not $device){$driverWindow.FindName('DeviceDetails').Text='Chọn thiết bị để xem toàn bộ Hardware ID, InstanceId và link Catalog.';$driverWindow.FindName('CatalogLinks').ItemsSource=@();return}
    $driverWindow.FindName('DeviceDetails').Text=$device.Name+"`r`nCode "+$device.ErrorCode+' · '+$device.Description+"`r`nInstanceId: "+$device.InstanceId+"`r`nHardware ID:`r`n"+($device.HardwareIds -join "`r`n")
    $driverWindow.FindName('CatalogLinks').ItemsSource=@(Get-DriverFixCatalogLinks $device.HardwareIds)
    if($script:driverFix.Session.Profile -and -not $script:driverFix.Work){$driverWindow.FindName('Disable').IsEnabled=($device.ErrorCode -ne 22 -and [bool](Get-DriverFixDisableRule $device $script:driverFix.Session.Profile))}
}
function Update-DriverFixView {
    $s=$script:driverFix.Session;if(-not $s){return}
    $driverWindow.FindName('MachineInfo').Text=$s.Machine.ComputerName+' · '+$s.Machine.Manufacturer+' '+$s.Machine.Model+' · BIOS '+$s.Machine.Bios+' · '+$s.Current.Problems.Count+' thiết bị có mã lỗi'
    $selected=$driverWindow.FindName('Devices').SelectedItem;$selectedId=if($selected){$selected.InstanceId}else{''}
    $driverWindow.FindName('Devices').ItemsSource=@($s.Current.Problems)
    $same=@($s.Current.Problems|Where-Object InstanceId -eq $selectedId)
    if($same.Count){$driverWindow.FindName('Devices').SelectedItem=$same[0]}elseif($s.Current.Problems.Count){$driverWindow.FindName('Devices').SelectedIndex=0}
    $text=Get-DriverFixProfileText $s.Profile
    if($s.MatchedCount -gt 1){$text='Nhiều profile cùng khớp: không bật disable / chỉnh nguồn. Sửa điều kiện JSON để chỉ khớp một profile.'+"`r`n"+$text}
    if($s.Profiles.Errors.Count){$text+="`r`n`r`nProfile bị bỏ qua:`r`n"+($s.Profiles.Errors -join "`r`n")}
    $driverWindow.FindName('ProfileDetails').Text=$text
    if(-not $script:driverFix.PowerBoxes.Count -and $s.Profile){
        foreach($action in $s.Profile.powerActions){$box=New-Object Windows.Controls.CheckBox;$box.Content=$action.name;$box.Tag=$action.id;$driverWindow.FindName('PowerChoices').Children.Add($box)|Out-Null;$script:driverFix.PowerBoxes+=,$box}
    }
    $driverWindow.FindName('ApplyPower').IsEnabled=[bool]$s.Profile
    Update-DriverFixSelection
}
function Set-DriverFixBusy([bool]$Value){
    foreach($name in 'ScanControls','InstallControls','ProfileControls','ApplyPower','PowerChoices','Report','Close'){$driverWindow.FindName($name).IsEnabled=-not $Value}
    $driverWindow.FindName('Busy').Visibility=if($Value){'Visible'}else{'Collapsed'}
    $driverWindow.FindName('Cancel').Visibility=if($Value -and $script:driverFix.Session){'Visible'}else{'Collapsed'}
    $driverWindow.FindName('Cancel').IsEnabled=$true
    if(-not $Value){Update-DriverFixView}
}
function Start-DriverFixOperation([ValidateSet('Init','Scan','Rescan','Source','Repository','Disable','Power','Report')][string]$Operation,$Payload=$null){
    if($script:driverFix.Work){return}
    if($Operation -ne 'Init' -and -not $script:driverFix.Session){Set-DriverFixStatus 'Chưa đọc được thiết bị. Bấm Quét lại để thử lại.';return}
    if($script:driverFix.Session -and (Test-Path -LiteralPath $script:driverFix.Session.CancelPath)){Remove-Item -LiteralPath $script:driverFix.Session.CancelPath -Force}
    $script:driverFix.ActionStart=if($script:driverFix.Session){$script:driverFix.Session.Actions.Count}else{0}
    Set-DriverFixBusy $true;Set-DriverFixStatus 'Đang xử lý… Nhật ký được ghi trong phiên. Chờ lệnh hiện tại hoàn tất trước khi đóng.' 'Working'
    try{
        $script:driverFix.Work=Start-DeployWork @'
param($engine,$report,$operation,$session,$payload)
$ErrorActionPreference='Stop'
. $engine
. $report
if($operation -eq 'Init'){$session=New-DriverFixSession;return [pscustomobject]@{Session=$session;Result=$null;Operation=$operation;Error=''}}
$result=$null;$errorText=''
try{
    switch($operation){
        'Scan' {$result=Update-DriverFixSession $session}
        'Rescan' {$result=Invoke-DriverFixRescan $session}
        'Source' {$result=Invoke-DriverFixInstallSource $session $payload}
        'Repository' {$result=Invoke-DriverFixRepository $session $payload}
        'Disable' {Invoke-DriverFixDisable $session $payload.InstanceId $payload.HardwareIds}
        'Power' {Invoke-DriverFixPower $session $payload}
        'Report' {$result=Export-DriverFixReport $session}
    }
}catch{
    $errorText=$_.Exception.GetBaseException().Message
    Write-DriverFixLog $session 'operation-failed' @{operation=$operation;error=$errorText}
    # Best-effort inventory after partial failure, preserve original error.
    if($operation -in 'Source','Repository','Disable'){try{$null=Update-DriverFixSession $session}catch{Write-DriverFixLog $session 'scan-failed' $_.Exception.Message}}
}
[pscustomobject]@{Session=$session;Result=$result;Operation=$operation;Error=$errorText}
'@ @((Join-Path $PSScriptRoot 'DriverFix.Engine.ps1'),(Join-Path $PSScriptRoot 'DriverFix.Report.ps1'),$Operation,$script:driverFix.Session,$Payload)
        $driverTimer.Start()
    }catch{$script:driverFix.Work=$null;Set-DriverFixBusy $false;Set-DriverFixStatus $_.Exception.Message 'Error'}
}
$driverTimer=New-DeployTimer 200 {
    if(-not $script:driverFix.Work -or -not $script:driverFix.Work.Async.IsCompleted){return}
    $driverTimer.Stop();$work=$script:driverFix.Work;$script:driverFix.Work=$null
    try{
        $response=@(Receive-DeployWork $work)[-1];$script:driverFix.Session=$response.Session
        if($response.Error){throw $response.Error}
        if($response.Operation -eq 'Report'){Set-DriverFixStatus ('Đã xuất: '+$response.Result) 'Success';Start-Process -FilePath $response.Result|Out-Null}
        else{
            $s=$response.Session;$delta=Compare-DriverFixSnapshot $s.Before $s.Current
            $message='Còn '+$s.Current.Problems.Count+' thiết bị có mã lỗi · Đã xác nhận Code 0: '+$delta.Resolved.Count
            if($s.LastDelta -and $s.LastDelta.NewProblems.Count){$message+=' · Phát hiện '+$s.LastDelta.NewProblems.Count+' thiết bị lỗi mới: '+(@($s.LastDelta.NewProblems|ForEach-Object Name)-join ', ')+'. Mở Catalog để tải gói tiếp.'}
            if($response.Operation -in 'Source','Repository'){$message+=' · Đã chạy '+$response.Result.Attempts+' lượt cài.';if($response.Result.Cancelled){$message+=' Đã dừng theo yêu cầu.'}}
            $failedActions=@($s.Actions|Select-Object -Skip $script:driverFix.ActionStart|Where-Object {-not $_.Success})
            if($failedActions.Count){$message+=' · Có '+$failedActions.Count+' thao tác không thành công; xem nhật ký. '+(@($failedActions|ForEach-Object {$_.Kind+': Exit '+$_.ExitCode+' '+$_.Message}) -join ' | ')}
            if(@($s.Actions|Where-Object RebootRequired).Count){$message+=' Có lệnh yêu cầu khởi động lại; hãy chủ động lưu công việc rồi restart.'}
            if($response.Operation -eq 'Power'){$message+=' · '+(@($s.Actions|Where-Object Kind -eq 'Power'|ForEach-Object {$_.Source+': '+$_.Message}) -join ' | ')}
            Set-DriverFixStatus $message $(if($failedActions.Count){'Attention'}else{'Info'})
        }
    }catch{Set-DriverFixStatus ('Chưa hoàn tất: '+$_.Exception.GetBaseException().Message) 'Error'}
    finally{Set-DriverFixBusy $false}
}
$driverWindow.FindName('Devices').Add_SelectionChanged({Update-DriverFixSelection})
$driverWindow.FindName('CatalogLinks').AddHandler([Windows.Documents.Hyperlink]::RequestNavigateEvent,[Windows.Navigation.RequestNavigateEventHandler]{param($sender,$event)
    if($event.Uri.Scheme -eq 'https' -and $event.Uri.Host -eq 'www.catalog.update.microsoft.com' -and $event.Uri.AbsolutePath -eq '/Search.aspx'){Start-Process -FilePath $event.Uri.AbsoluteUri|Out-Null};$event.Handled=$true
})
$driverWindow.FindName('Scan').Add_Click({if($script:driverFix.Session){Start-DriverFixOperation Scan}else{Start-DriverFixOperation Init}})
$driverWindow.FindName('Rescan').Add_Click({Start-DriverFixOperation Rescan})
$driverWindow.FindName('CopyIds').Add_Click({
    $d=$driverWindow.FindName('Devices').SelectedItem
    if($d){try{[Windows.Clipboard]::SetText(($d.HardwareIds -join "`r`n"));Set-DriverFixStatus 'Đã copy toàn bộ Hardware ID của thiết bị đang chọn.'}catch{Set-DriverFixStatus 'Không copy được; có thể chọn và copy trong ô chi tiết.' 'Error'}}
})
$driverWindow.FindName('InstallCab').Add_Click({
    $path=Select-DeployFile 'Chọn CAB driver đã tải' 'Driver CAB (*.cab)|*.cab'
    if($path -and (Confirm-Box ("Giải nén và cài các INF trong CAB này?`r`n"+$path+"`r`nSau cài sẽ dò và quét lại thiết bị. Không tự restart.") 'Cài driver' -ConfirmText 'Cài và quét lại' -Owner $driverWindow)){Start-DriverFixOperation Source $path}
})
$driverWindow.FindName('InstallFolder').Add_Click({
    $path=Select-DriverFixFolder 'Chọn thư mục driver đã giải nén (có .inf)'
    if($path -and (Confirm-Box ("Thêm và cài driver từ các INF trong thư mục (kể cả thư mục con)?`r`n"+$path) 'Cài driver' -ConfirmText 'Cài và quét lại' -Owner $driverWindow)){Start-DriverFixOperation Source $path}
})
$driverWindow.FindName('Repository').Add_Click({
    $path=Select-DriverFixFolder 'Chọn kho driver INF trên USB / NAS'
    if($path -and (Confirm-Box ("Đối chiếu Hardware ID, cài INF khớp từ kho này tối đa 4 vòng?`r`n"+$path+"`r`nƯu tiên thứ tự và phiên bản trong profile. pnputil quyết định driver áp dụng cho phần cứng.") 'Cài từ kho cục bộ' -ConfirmText 'Đối chiếu và cài' -Owner $driverWindow)){Start-DriverFixOperation Repository $path}
})
$driverWindow.FindName('Disable').Add_Click({
    $d=$driverWindow.FindName('Devices').SelectedItem;if(-not $d){return}
    $rule=Get-DriverFixDisableRule $d $script:driverFix.Session.Profile
    if($rule -and (Confirm-Box ($d.Name+"`r`n"+$d.InstanceId+"`r`n"+$rule.reason+"`r`nDisable làm ngừng tính năng này. Có thể bật lại trong Device Manager → Enable device.") 'Disable thiết bị con' -ConfirmText 'Disable thiết bị' -Danger -Owner $driverWindow)){Start-DriverFixOperation Disable $d}
})
$driverWindow.FindName('ApplyPower').Add_Click({
    $chosen=@($script:driverFix.PowerBoxes|Where-Object IsChecked)
    if(-not $chosen.Count){Set-DriverFixStatus 'Chọn ít nhất một tinh chỉnh nguồn trong profile.' 'Attention';return}
    if(Confirm-Box ((@($chosen|ForEach-Object Content)-join "`r`n")+"`r`nThiết lập power scheme chỉ đổi nguồn AC; WMI đổi quyền tắt nguồn USB/HID nếu thiết bị hỗ trợ. Giá trị cũ được ghi log.") 'Tinh chỉnh nguồn' -ConfirmText 'Áp dụng mục đã chọn' -Owner $driverWindow){Start-DriverFixOperation Power @($chosen|ForEach-Object Tag)}
})
$driverWindow.FindName('OpenProfiles').Add_Click({
    $path=Join-Path (Get-DriverFixHome) 'Profiles';New-Item -ItemType Directory -Path $path -Force|Out-Null
    Start-Process explorer.exe ('"'+$path+'"')|Out-Null;Set-DriverFixStatus 'Sau khi sửa / thêm JSON, đóng và mở lại Fix Driver để nạp profile.'
})
$driverWindow.FindName('OpenLogs').Add_Click({if($script:driverFix.Session){Start-Process explorer.exe ('"'+$script:driverFix.Session.Directory+'"')|Out-Null}})
$driverWindow.FindName('Report').Add_Click({Start-DriverFixOperation Report})
$driverWindow.FindName('Help').Add_Click({
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Info.UI.ps1')
    $view=New-DeployInfoWindow (Split-Path -Parent $PSScriptRoot) -Owner $driverWindow -Section 'Fix Driver'
    [void]$view.ShowDialog()
})
$driverWindow.FindName('Cancel').Add_Click({
    if($script:driverFix.Session){[IO.File]::WriteAllText($script:driverFix.Session.CancelPath,'cancel');$driverWindow.FindName('Cancel').IsEnabled=$false;Set-DriverFixStatus 'Đã yêu cầu dừng. Chờ lệnh đang chạy hoàn tất; không ngắt pnputil giữa chừng.' 'Attention'}
})
$driverWindow.FindName('Close').Add_Click({$driverWindow.Close()})
$driverWindow.Add_Closing({param($sender,$event)if($script:driverFix.Work){$event.Cancel=$true;Set-DriverFixStatus 'Đang xử lý. Có thể yêu cầu dừng sau gói hiện tại rồi đóng.'}})
$driverWindow.Add_ContentRendered({Start-DriverFixOperation Init})
if($ValidateOnly){return $driverWindow}
try{[void]$driverWindow.ShowDialog()}finally{$driverTimer.Stop()}
