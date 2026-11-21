# PDF printer queues are distinct from the Foxit Reader application itself.
function Get-DeployPdfPrinterInventory {
    try{
        $printers=@(Get-CimInstance Win32_Printer -OperationTimeoutSec 15 -ErrorAction Stop|Where-Object {$_.Name -match '(?i)pdf' -or $_.DriverName -match '(?i)pdf'}|Select-Object Name,DriverName,PortName,WorkOffline)
        [pscustomobject]@{Readable=$true;Printers=$printers;Error=''}
    }catch{[pscustomobject]@{Readable=$false;Printers=@();Error=$_.Exception.GetBaseException().Message}}
}
function Complete-DeployFoxitReader($Result,[string]$Details) {
    if($Result.Group -notin 'Installed','Skipped','Restart'){return [pscustomobject]@{Status=$Result.Status;Group=$Result.Group;Details=$Details}}
    $inventory=Get-DeployPdfPrinterInventory
    $note='Foxit Reader bản mới không kèm máy in ảo Foxit PDF Printer như Reader cũ. Cài / mở Reader không tự bổ sung driver máy in ảo. Nếu chỉ cần in ra PDF, có thể dùng Microsoft Print to PDF của Windows; nếu cần đúng Foxit PDF Printer, cần bộ sản phẩm Foxit có thành phần tạo PDF tương ứng.'
    if(-not $inventory.Readable){$status='Foxit Reader · chưa đọc được máy in PDF';$printerText=$inventory.Error}
    elseif($inventory.Printers.Count){
        $status='Foxit Reader · có máy in PDF trong Windows'
        $printerText=@($inventory.Printers|ForEach-Object {$_.Name+' | Driver: '+$_.DriverName+' | Port: '+$_.PortName+' | Offline: '+$_.WorkOffline}) -join "`r`n"
    }else{$status='Foxit Reader · chưa có máy in PDF';$printerText='Không tìm thấy hàng đợi máy in có tên hoặc driver PDF. Đây là kiểm tra hàng đợi, không phải xác nhận tính năng Windows đã bật / tắt.'}
    if($Result.Group -eq 'Restart'){$status+=' · cần khởi động lại'}
    [pscustomobject]@{Status=$status;Group=$Result.Group;Details=($Details+"`r`nKết quả cài Reader: "+$Result.Status+"`r`nMáy in PDF:`r`n"+$printerText+"`r`n"+$note+"`r`nCó hàng đợi chưa xác nhận được in thực tế thành công; hãy thử in một trang PDF.")}
}
