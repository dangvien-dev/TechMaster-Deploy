param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'UltraViewer.Core.ps1')
$ultraWindow=Import-DeployWindow (Join-Path $PSScriptRoot 'UltraViewer-Reset.xml')
$script:ultraUi=@{Job=$null;Receipt=''}
$backupRoot=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TechMaster Deploy/UltraViewer Backups'
$markerPath=Join-Path $env:SystemDrive 'FixClone/UltraViewer-Clone.json'
function Start-UltraUiTask([string]$operation,[string]$receipt='') {
    if($script:ultraUi.Job){return}
    foreach($name in 'Reset','Check','Restore','Close'){$ultraWindow.FindName($name).IsEnabled=$false}
    $ultraWindow.FindName('Progress').IsIndeterminate=$true
    Set-DeployNotice ($ultraWindow.FindName('Status')) 'Đang xử lý… Vui lòng chờ thao tác hoàn tất.' 'Working'
    try {
    $script:ultraUi.Job=Start-DeployWork @'
param($core,$operation,$backupRoot,$marker,$receipt)
$ErrorActionPreference='Stop'
. $core
switch($operation) {
 'Reset' {$r=Invoke-UltraReset $backupRoot;[pscustomobject]@{Message=$r.Message;Receipt=$r.Receipt;UiKind='Attention'}}
 'Restore' {
    Restore-UltraReceipt $receipt
    if(Test-Path -LiteralPath $marker){$m=Get-Content $marker -Raw|ConvertFrom-Json;if($m.Receipt -eq $receipt){Remove-Item -LiteralPath $marker -Force}}
    [pscustomobject]@{Message='Đã khôi phục hai giá trị đã sao lưu. Mở UltraViewer để kiểm tra.';Receipt=$receipt;UiKind='Info'}
 }
 'Check' {
    if($receipt){$old=Read-UltraReceipt $receipt;$now=Get-UltraIdentity;$ok=Test-UltraNewIdentity $old.Identity $now
        [pscustomobject]@{Message=$(if($ok){'Đã xác minh UID và PreferID khác bản sao lưu. ID hiện tại: '+$now.PreferID.Value}else{'Chưa xác nhận ID mới. Mở UltraViewer và đợi kết nối; không reset lặp.'});Receipt=$receipt;UiKind=$(if($ok){'Success'}else{'Attention'})}
    }elseif(Test-Path -LiteralPath $marker){$r=Complete-UltraAfterClone $marker $backupRoot;[pscustomobject]@{Message=$r.Message;UiKind=$(if($r.State -eq 'Complete'){'Success'}elseif($r.State -eq 'Pending'){'Attention'}else{'Info'})}}
    else{[pscustomobject]@{Message='Chưa có lần reset để đối chiếu. Chọn Sao lưu và reset ID khi cần.';UiKind='Info'}}
 }
}
'@ @((Join-Path $PSScriptRoot 'UltraViewer.Core.ps1'),$operation,$backupRoot,$markerPath,$receipt)
    $ultraTimer.Start()
    }catch{
        $script:ultraUi.Job=$null
        Set-DeployNotice ($ultraWindow.FindName('Status')) $_.Exception.GetBaseException().Message 'Error'
        foreach($name in 'Reset','Check','Restore','Close'){$ultraWindow.FindName($name).IsEnabled=$true}
        $ultraWindow.FindName('Progress').IsIndeterminate=$false
    }
}
$ultraTimer=New-DeployTimer 200 {
    $job=$script:ultraUi.Job
    if(-not $job -or -not $job.Async.IsCompleted){return}
    $ultraTimer.Stop();$script:ultraUi.Job=$null
    try{
        $result=@(Receive-DeployWork $job)[-1]
        Set-DeployNotice ($ultraWindow.FindName('Status')) $result.Message $result.UiKind
        $ultraWindow.FindName('Check').Background=if($result.UiKind -eq 'Attention'){'#2563EB'}else{'#214674'}
        if($result.Receipt){$script:ultraUi.Receipt=$result.Receipt;$ultraWindow.FindName('Backup').Text=$result.Receipt;$ultraWindow.FindName('BackupPanel').Visibility='Visible'}
    }catch{Set-DeployNotice ($ultraWindow.FindName('Status')) $_.Exception.GetBaseException().Message 'Error';Show-DeployMessage $_.Exception.GetBaseException().Message 'UltraViewer' 'Error'}
    finally{foreach($name in 'Reset','Check','Restore','Close'){$ultraWindow.FindName($name).IsEnabled=$true};$ultraWindow.FindName('Progress').IsIndeterminate=$false}
}
$ultraWindow.FindName('Reset').Add_Click({if(Confirm-Box 'UltraViewer sẽ ngắt kết nối. Sao lưu rồi reset UID và PreferID trên máy này? Chỉ chạy tại máy hoặc qua remote khác.' 'Reset ID UltraViewer' -ConfirmText 'Sao lưu và reset' -Danger -Owner $ultraWindow){Start-UltraUiTask 'Reset'}})
$ultraWindow.FindName('Check').Add_Click({Start-UltraUiTask 'Check' $script:ultraUi.Receipt})
$ultraWindow.FindName('Restore').Add_Click({$path=Select-DeployFile 'Chọn identity.json của máy này' 'Sao lưu định danh (*.json)|*.json';if($path -and (Confirm-Box 'Khôi phục UID / PreferID từ sao lưu? UltraViewer sẽ ngắt kết nối.' 'Khôi phục UltraViewer' -ConfirmText 'Khôi phục' -Owner $ultraWindow)){Start-UltraUiTask 'Restore' $path}})
$ultraWindow.FindName('Close').Add_Click({$ultraWindow.Close()})
$ultraWindow.Add_Closing({param($sender,$event)if($script:ultraUi.Job){$event.Cancel=$true}})
if($ValidateOnly){return $ultraWindow}
try{[void]$ultraWindow.ShowDialog()}finally{$ultraTimer.Stop()}
