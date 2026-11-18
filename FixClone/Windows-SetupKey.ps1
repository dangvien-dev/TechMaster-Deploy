param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Ui.ps1')
. (Join-Path $PSScriptRoot 'Windows.License.Core.ps1')
if(-not $ValidateOnly){
    $principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        $command="& '{0}'" -f $PSCommandPath.Replace("'","''")
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))|Out-Null
        return
    }
}
$keyWindow=Import-DeployWindow (Join-Path $PSScriptRoot 'Windows-SetupKey.xml')
$script:keyReview=@{Work=$null;Inventory=$null;Receipt=''}
function Start-WindowsKeyReview([ValidateSet('Inspect','Clean','Restore')][string]$Operation){
    if($script:keyReview.Work){return}
    if($Operation -eq 'Clean'){
        if(-not $script:keyReview.Inventory -or -not @($script:keyReview.Inventory.Items|Where-Object Eligible).Count){return}
        if(-not (Confirm-Box 'Dọn key cài đặt chung Pro chưa kích hoạt đã liệt kê? Sau đó nhập key bản quyền của máy khách trong Windows Settings.' 'Dọn key chung Windows' -ConfirmText 'Dọn key chung' -Owner $keyWindow)){return}
        $script:keyReview.Receipt=Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Windows Key Backups/'+[guid]::NewGuid().ToString('N')+'.json')
    }
    if($Operation -eq 'Restore' -and -not (Confirm-Box 'Khôi phục key cài đặt chung Pro của lần dọn này? Nếu Windows đã có key mới, công cụ sẽ giữ nguyên key mới.' 'Hoàn tác key chung' -ConfirmText 'Hoàn tác' -Owner $keyWindow)){return}
    foreach($name in 'Refresh','Clean','Restore','Close'){$keyWindow.FindName($name).IsEnabled=$false}
    $keyWindow.FindName('Status').Text='Đang kiểm tra / xử lý key Windows…'
    try {
    $script:keyReview.Work=Start-DeployWork @'
param($core,$operation,$inventory,$receipt)
$ErrorActionPreference='Stop'
. $core
$message='';$path=''
if($operation -eq 'Clean'){$result=Invoke-WindowsSetupKeyCleanup -ReceiptPath $receipt -Inventory $inventory;$message=$result.Message;$path=$result.ReceiptPath}
elseif($operation -eq 'Restore'){$message=(Restore-WindowsSetupKeyCleanup $receipt).Message}
[pscustomobject]@{Inventory=(Get-WindowsSetupKeyInventory);Message=$message;Receipt=$path}
'@ @((Join-Path $PSScriptRoot 'Windows.License.Core.ps1'),$Operation,$script:keyReview.Inventory,$script:keyReview.Receipt)
    $keyTimer.Start()
    }catch{
        $script:keyReview.Work=$null
        $keyWindow.FindName('Refresh').IsEnabled=$true;$keyWindow.FindName('Close').IsEnabled=$true
        $keyWindow.FindName('Status').Text=$_.Exception.GetBaseException().Message
    }
}
$keyTimer=New-DeployTimer 200 {
    if(-not $script:keyReview.Work -or -not $script:keyReview.Work.Async.IsCompleted){return}
    $keyTimer.Stop();$job=$script:keyReview.Work;$script:keyReview.Work=$null
    try{
        $result=@(Receive-DeployWork $job)[-1];$script:keyReview.Inventory=$result.Inventory
        $lines=@($result.Inventory.Items|ForEach-Object {$_.Name+' · *****-'+$_.KeyTail+"`n"+$_.State+' · '+$_.Channel+"`n"+$_.Reason})
        $keyWindow.FindName('Inventory').Text=if($lines.Count){$lines -join "`n`n"}else{'Không tìm thấy giấy phép Windows đang dùng key trên máy.'}
        $keyWindow.FindName('Status').Text=$result.Message
        if($result.Receipt){$script:keyReview.Receipt=$result.Receipt}
        $keyWindow.FindName('Clean').IsEnabled=@($result.Inventory.Items|Where-Object Eligible).Count -gt 0
    }catch{$script:keyReview.Inventory=$null;$keyWindow.FindName('Status').Text=$_.Exception.GetBaseException().Message}
    finally{
        $keyWindow.FindName('Refresh').IsEnabled=$true;$keyWindow.FindName('Close').IsEnabled=$true
        $keyWindow.FindName('Restore').IsEnabled=[bool]($script:keyReview.Receipt -and (Test-Path -LiteralPath $script:keyReview.Receipt))
    }
}
$keyWindow.FindName('Refresh').Add_Click({Start-WindowsKeyReview 'Inspect'})
$keyWindow.FindName('Clean').Add_Click({Start-WindowsKeyReview 'Clean'})
$keyWindow.FindName('Restore').Add_Click({Start-WindowsKeyReview 'Restore'})
$keyWindow.FindName('Close').Add_Click({$keyWindow.Close()})
$keyWindow.Add_Closing({param($sender,$event)if($script:keyReview.Work){$event.Cancel=$true}})
$keyWindow.Add_ContentRendered({Start-WindowsKeyReview 'Inspect'})
if($ValidateOnly){return $keyWindow}
try{[void]$keyWindow.ShowDialog()}finally{$keyTimer.Stop()}
