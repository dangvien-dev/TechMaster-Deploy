# Functions only. Removing a key is restricted to a verified, unactivated Pro setup key.
function Get-WindowsLicenseStateText([int]$Status) {
    switch($Status){
        0 {'Chưa có giấy phép kích hoạt'}
        1 {'Đã kích hoạt'}
        2 {'Chưa kích hoạt (ân hạn ban đầu / OOBGrace)'}
        3 {'Chưa kích hoạt (ân hạn OOTGrace)'}
        4 {'Ân hạn Non-Genuine'}
        5 {'Chưa kích hoạt (Notification)'}
        6 {'Chưa kích hoạt (ân hạn mở rộng / ExtendedGrace)'}
        default {'Chưa xác định trạng thái kích hoạt'}
    }
}
function Test-WindowsProSetupKey {
    # Compare in memory only. Never return/log the registry value: it may be a private key.
    $value=Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name BackupProductKeyDefault -ErrorAction SilentlyContinue
    return ([string]$value -ieq 'VK7JG-NPHTM-C97JM-9MPGT-3V66T')
}
function Get-WindowsSetupKeyInventory {
    $products=@(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop)
    $active=@($products|Where-Object {$_.LicenseStatus -eq 1}).Count -gt 0
    $verified=Test-WindowsProSetupKey
    $items=@(foreach($p in $products){
        $tail=[string]$p.PartialProductKey
        if($tail.Length -gt 5){$tail=$tail.Substring($tail.Length-5)}
        $channel=[string]$p.ProductKeyChannel
        if(-not $channel){$channel=[string]$p.Description}
        $eligible=$false
        if($active){$reason='Windows đang kích hoạt: giữ nguyên key.'}
        elseif($tail -cne '3V66T'){$reason='Không phải key cài đặt chung Pro được hỗ trợ: giữ nguyên.'}
        elseif($p.Name -notmatch '\bProfessional\b' -or $channel -notmatch 'RETAIL' -or $channel -match 'OEM|VOLUME|EVAL'){$reason='Không khớp giấy phép Windows Pro Retail: giữ nguyên.'}
        elseif($null -eq $p.LicenseStatus -or [int]$p.LicenseStatus -notin 0,2,3,5,6){$reason='Chưa đủ điều kiện xác minh trạng thái: giữ nguyên.'}
        elseif(-not $verified){$reason='Đuôi key khớp nhưng chưa xác minh được key chung từ hệ thống: giữ nguyên.'}
        elseif([string]$p.ID -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){$reason='Không xác định được ID giấy phép: giữ nguyên.'}
        else{$eligible=$true;$reason='Key cài đặt chung Pro, chưa kích hoạt: có thể dọn.'}
        [pscustomobject]@{Id=[string]$p.ID;Name=[string]$p.Name;KeyTail=$tail;Status=[int]$p.LicenseStatus;State=(Get-WindowsLicenseStateText ([int]$p.LicenseStatus));Channel=$channel;Eligible=$eligible;Reason=$reason}
    })
    if(@($items|Where-Object Eligible).Count -gt 1){foreach($item in $items){if($item.Eligible){$item.Eligible=$false;$item.Reason='Có nhiều bản ghi key chung, chưa xác định duy nhất: giữ nguyên.'}}}
    [pscustomobject]@{Items=$items;VerifiedSetupKey=[bool]$verified}
}
function Write-WindowsSetupReceipt($Receipt,[string]$Path) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force -ErrorAction Stop|Out-Null
    [IO.File]::WriteAllText($Path,($Receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($true))
}
function Remove-WindowsSetupLicense([string]$Id) {
    if($Id -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){throw 'ID giấy phép không hợp lệ.'}
    $folder=Join-Path $env:SystemRoot 'System32'
    if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){$folder=Join-Path $env:SystemRoot 'Sysnative'}
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=Join-Path $folder 'cscript.exe'
    $start.Arguments='//nologo "'+(Join-Path $folder 'slmgr.vbs')+'" /upk '+$Id
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($start)
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    try{if(-not $process.WaitForExit(30000)){try{$process.Kill();[void]$process.WaitForExit(1000)}catch{};throw 'Windows chưa phản hồi thao tác dọn key.'};if($process.ExitCode -ne 0){throw ('Không dọn được key Windows (mã '+$process.ExitCode+').')}}finally{$process.Dispose()}
}
function Install-WindowsProSetupKey {
    # Only used for rollback of this public setup key; never activates Windows.
    $service=Get-CimInstance SoftwareLicensingService -ErrorAction Stop
    $result=Invoke-CimMethod -InputObject $service -MethodName InstallProductKey -Arguments @{ProductKey='VK7JG-NPHTM-C97JM-9MPGT-3V66T'} -ErrorAction Stop
    if($null -ne $result.ReturnValue -and $result.ReturnValue -ne 0){throw 'Không khôi phục được key cài đặt chung Windows.'}
}
function Restore-WindowsSetupKeyCleanup([string]$ReceiptPath) {
    $receipt=[IO.File]::ReadAllText($ReceiptPath)|ConvertFrom-Json
    if($receipt.Schema -ne 1 -or $receipt.Product -cne 'TechMaster.WindowsSetupKey' -or $receipt.KeyTail -cne '3V66T' -or $receipt.State -notin 'prepared','removed','restored') {throw 'Biên nhận khôi phục key Windows không hợp lệ.'}
    if(@((Get-WindowsSetupKeyInventory).Items).Count){return [pscustomobject]@{Restored=$false;Message='Windows đã có key. Giữ nguyên, không ghi đè key hiện tại.'}}
    Install-WindowsProSetupKey
    $after=Get-WindowsSetupKeyInventory
    if(-not @($after.Items|Where-Object {$_.KeyTail -ceq '3V66T'}).Count){throw 'Chưa xác minh được việc khôi phục key chung Windows.'}
    $receipt.State='restored';Write-WindowsSetupReceipt $receipt $ReceiptPath
    return [pscustomobject]@{Restored=$true;Message='Đã khôi phục key cài đặt chung Pro; chưa kích hoạt bản quyền.'}
}
function Invoke-WindowsSetupKeyCleanup {
    param([string]$ReceiptPath,$Inventory=$null)
    $mutex=[Threading.Mutex]::new($false,'Global\TechMaster.WindowsSetupKey');$owned=$false
    try{
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Cửa sổ khác đang xử lý key cài đặt chung Windows.'}
        $fresh=Get-WindowsSetupKeyInventory
        $signature={param($i) @($i.Items|Sort-Object Id|ForEach-Object {$_.Id+'|'+$_.KeyTail+'|'+$_.Status+'|'+$_.Channel+'|'+$_.Eligible}) -join "`n"}
        if($Inventory -and (& $signature $Inventory) -cne (& $signature $fresh)){throw 'Trạng thái key Windows đã thay đổi. Bấm Kiểm tra lại trước khi dọn.'}
        $candidates=@($fresh.Items|Where-Object Eligible)
        if(-not $candidates.Count){return [pscustomobject]@{Changed=$false;ReceiptPath='';Message='Không có key chung Windows chưa kích hoạt đủ điều kiện để dọn. Các key hiện tại được giữ nguyên.'}}
        if(-not $ReceiptPath){$ReceiptPath=Join-Path $env:LOCALAPPDATA ('TechMaster Deploy/Windows Key Backups/'+[guid]::NewGuid().ToString('N')+'.json')}
        $receipt=[pscustomobject]@{Schema=1;Product='TechMaster.WindowsSetupKey';KeyTail='3V66T';State='prepared';Created=[DateTime]::UtcNow.ToString('o');Ids=@($candidates|ForEach-Object Id)}
        Write-WindowsSetupReceipt $receipt $ReceiptPath
        try{
            foreach($item in $candidates){
                $check=Get-WindowsSetupKeyInventory
                if(-not @($check.Items|Where-Object {$_.Id -ceq $item.Id -and $_.Eligible}).Count){throw 'Key Windows đã thay đổi trước khi dọn. Giữ nguyên key hiện tại.'}
                Remove-WindowsSetupLicense $item.Id
                $removed=$false
                for($attempt=0;$attempt -lt 5;$attempt++){
                    $after=Get-WindowsSetupKeyInventory
                    if(-not @($after.Items|Where-Object {$_.Id -ceq $item.Id}).Count){$removed=$true;break}
                    Start-Sleep -Milliseconds 400
                }
                if(-not $removed){throw 'Windows vẫn báo còn key sau thao tác dọn. Chưa xác nhận hoàn tất.'}
            }
            $receipt.State='removed';Write-WindowsSetupReceipt $receipt $ReceiptPath
        }catch{
            $original=$_.Exception.Message
            try{$null=Restore-WindowsSetupKeyCleanup $ReceiptPath}catch{throw ($original+' Khôi phục chưa hoàn tất; xem biên nhận: '+$ReceiptPath)}
            throw $original
        }
        return [pscustomobject]@{Changed=$true;ReceiptPath=$ReceiptPath;Message='Đã dọn key cài đặt chung Pro chưa kích hoạt. Nhập key bản quyền riêng của máy khách trong Windows Settings.'}
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Get-WindowsSetupActivationNotice($Inventory) {
    if(@($Inventory.Items|Where-Object {$_.Status -eq 1}).Count){return $null}
    if(@($Inventory.Items|Where-Object {$_.KeyTail -cne '3V66T'}).Count){return $null}
    if(@($Inventory.Items|Where-Object {$_.KeyTail -ceq '3V66T'}).Count){
        return 'Windows đang báo đuôi key …3V66T, thường là key cài đặt chung Pro. Chưa xác nhận được kích hoạt online. Installation ID vẫn có thể được tạo cho key chung; mã này chưa xác nhận quyền sử dụng. Nhập key bản quyền của máy khách tại Settings → System → Activation → Change product key trước khi dùng QR / portal.'
    }
    return $null
}
