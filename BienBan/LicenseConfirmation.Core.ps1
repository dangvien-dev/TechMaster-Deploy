# Read-only data and printable supplier handover confirmations. No activation changes.
function Get-DeployConfirmationSnapshot {
    $machine=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $bios=Get-CimInstance Win32_BIOS -ErrorAction Stop
    $items=[Collections.Generic.List[object]]::new()
    foreach($group in @(@{Name='Windows';Id='55c92734-d682-4d71-983e-d6ec3f16059f'},@{Name='Microsoft Office';Id='0ff1ce15-a989-479d-af46-f275c6370663'})){
        try{
            $products=@(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='$($group.Id)' AND PartialProductKey IS NOT NULL" -ErrorAction Stop)
            foreach($p in $products){
                $tail=[string]$p.PartialProductKey
                if($tail.Length -gt 5){$tail=$tail.Substring($tail.Length-5)}
                $items.Add([pscustomobject]@{Name=[string]$p.Name;KeyTail=$tail;Status=$(switch([int]$p.LicenseStatus){1{'Đã kích hoạt'}2{'Chưa kích hoạt (dùng thử)'}3{'Hết hạn dùng thử'}4{'Không hợp lệ (Non-Genuine)'}default{'Chưa kích hoạt'}});Selected=$false})
            }
            if(-not $products.Count){$items.Add([pscustomobject]@{Name=$group.Name;KeyTail='';Status='Không đọc được giấy phép dùng key; kiểm tra sản phẩm thực tế';Selected=$false})}
        }catch{$items.Add([pscustomobject]@{Name=$group.Name;KeyTail='';Status='Chưa đọc được trạng thái kích hoạt';Selected=$false})}
    }
    [pscustomobject]@{Computer=$env:COMPUTERNAME;Model=([string]$machine.Manufacturer+' '+[string]$machine.Model).Trim();Serial=[string]$bios.SerialNumber;CheckedAt=(Get-Date);Products=$items.ToArray()}
}
function New-DeployLicenseConfirmationHtml {
    param([ValidateSet('Retail','Company')][string]$Template,$Supplier,$Customer,$Snapshot,[object[]]$Products,[string]$Reference='')
    if([string]::IsNullOrWhiteSpace([string]$Supplier.Company) -or [string]::IsNullOrWhiteSpace([string]$Customer.Name)){throw 'Nhập tên đơn vị cung cấp và khách hàng trước khi xuất xác nhận.'}
    if(-not $Products.Count){throw 'Chọn ít nhất một sản phẩm đã bàn giao.'}
    function Enc($value){[Net.WebUtility]::HtmlEncode([string]$value)}
    $kind=if($Template -eq 'Company'){'KHÁCH HÀNG CÔNG TY'}else{'KHÁCH HÀNG CÁ NHÂN'}
    $evidence=if($Template -eq 'Company'){'Đơn vị cung cấp đã cấp và bàn giao hóa đơn / chứng từ mua bán cho khách hàng. Xác nhận này được dùng kèm hồ sơ đó.'}else{'Xác nhận việc cung cấp và bàn giao phần mềm cho khách hàng cá nhân theo giao dịch mua bán giữa hai bên.'}
    $refRow=if($Template -eq 'Company' -and -not [string]::IsNullOrWhiteSpace($Reference)){'<tr><th>Hóa đơn / chứng từ tham chiếu</th><td>'+ (Enc $Reference)+'</td></tr>'}else{''}
    $taxRow=if($Template -eq 'Company' -and -not [string]::IsNullOrWhiteSpace([string]$Customer.TaxCode)){'<tr><th>Mã số thuế khách hàng</th><td>'+(Enc $Customer.TaxCode)+'</td></tr>'}else{''}
    $rows=foreach($p in $Products){
        if([string]::IsNullOrWhiteSpace([string]$p.Name)){throw 'Nhập tên đầy đủ của từng sản phẩm bàn giao.'}
        $tail=[string]$p.KeyTail;if($tail.Length -gt 5){$tail=$tail.Substring($tail.Length-5)}
        $key=if($tail){'*****-'+(Enc $tail)}else{'Không ghi nhận key trên máy'}
        '<tr><td>'+(Enc $p.Name)+'</td><td>1</td><td class="mono">'+$key+'</td><td>'+(Enc $p.Status)+'</td></tr>'
    }
    $logo=''
    if($Supplier.LogoPath -and (Test-Path -LiteralPath $Supplier.LogoPath -PathType Leaf)){
        $extension=[IO.Path]::GetExtension($Supplier.LogoPath).ToLowerInvariant()
        $mime=@{'.svg'='image/svg+xml';'.png'='image/png';'.jpg'='image/jpeg';'.jpeg'='image/jpeg'}[$extension]
        if($mime){$logo='<img alt="Logo đơn vị" style="max-width:90px;max-height:65px;margin-right:14px" src="data:'+$mime+';base64,'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($Supplier.LogoPath))+'">'}
    }
    $stamp=([datetime]$Snapshot.CheckedAt).ToString('HH:mm dd/MM/yyyy')
    $doc='XN-'+[datetime]::Now.ToString('yyyyMMdd-HHmmss')
    $html=@'
<!doctype html><html lang="vi"><head><meta charset="utf-8"><title>Xác nhận bàn giao bản quyền</title><style>
@page{size:A4;margin:14mm}*{box-sizing:border-box}body{font:14px "Segoe UI",Arial,sans-serif;color:#10223f;background:#f3f6fb;margin:0;line-height:1.5}.page{background:white;max-width:210mm;margin:18px auto;padding:16mm}.brand{border-bottom:2px solid #214674;padding-bottom:12px}.brand strong{font-size:17px}.muted{color:#526880;font-size:12px}h1{text-align:center;font-size:21px;margin:22px 0 4px}.subtitle{text-align:center;font-size:12px;color:#526880}h2{font-size:15px;border-left:4px solid #219ac0;padding-left:8px;margin:18px 0 8px}table{border-collapse:collapse;width:100%;table-layout:fixed}th,td{border:1px solid #c7d5e5;padding:7px 9px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#f3f6fb}table.info th{width:30%}.mono{font-family:Consolas,monospace}p{margin:8px 0}.sign{display:flex;justify-content:space-between;text-align:center;margin-top:25px;break-inside:avoid}.sign>div{width:46%}.space{height:85px}.bar{max-width:210mm;margin:16px auto;text-align:right}button{background:#214674;border:0;border-radius:8px;color:white;padding:10px 20px;font:inherit}.foot{margin-top:18px;border-top:1px solid #c7d5e5;padding-top:10px}@media print{body{background:white}.page{margin:0;padding:0;max-width:none}.bar{display:none}thead{display:table-header-group}tr{break-inside:avoid}}
</style></head><body><div class="bar"><button onclick="window.print()">In / Lưu PDF</button></div><main class="page">
<div class="brand" style="display:flex;align-items:center">{{LOGO}}<div><strong>{{SUPPLIER}}</strong><div>{{ADDRESS}}</div><div>Điện thoại: {{PHONE}}</div></div></div>
<h1>XÁC NHẬN CUNG CẤP VÀ BÀN GIAO<br>BẢN QUYỀN PHẦN MỀM</h1><div class="subtitle">{{KIND}} · Số: {{DOC}} · Ngày {{DATE}}</div>
<h2>1. Thông tin bàn giao</h2><table class="info"><tr><th>Khách hàng</th><td>{{CUSTOMER}}</td></tr><tr><th>Địa chỉ khách hàng</th><td>{{CUSTOMER_ADDRESS}}</td></tr>{{TAX}}{{REFERENCE}}<tr><th>Thiết bị</th><td>{{COMPUTER}} · {{MODEL}}<br>Serial: {{SERIAL}}</td></tr><tr><th>Kỹ thuật viên thực hiện</th><td>{{TECH}}</td></tr></table>
<h2>2. Phần mềm đã cung cấp và bàn giao</h2><table><thead><tr><th style="width:40%">Sản phẩm / phiên bản</th><th style="width:8%">SL</th><th style="width:23%">Key (5 ký tự cuối)</th><th>Trạng thái khi kiểm tra</th></tr></thead><tbody>{{PRODUCTS}}</tbody></table><div class="muted">Trạng thái do máy báo lúc {{CHECKED}}. Mỗi dòng tương ứng một giấy phép bàn giao cho thiết bị nêu trên.</div>
<h2>3. Xác nhận của đơn vị cung cấp</h2><p>Đơn vị cung cấp xác nhận đã cung cấp và bàn giao các sản phẩm phần mềm tại mục 2 cho khách hàng nêu trên; chịu trách nhiệm về thông tin cung cấp và hồ sơ mua bán thuộc phạm vi giao dịch của mình.</p><p>{{EVIDENCE}}</p><p>Khách hàng sử dụng phần mềm theo điều khoản giấy phép của nhà sản xuất. Tài liệu / thẻ key / thông tin tài khoản liên quan được bàn giao riêng theo hình thức cấp phép của từng sản phẩm.</p>
<div class="sign"><div><b>ĐƠN VỊ CUNG CẤP</b><div class="muted">Đại diện ký, ghi rõ họ tên; đóng dấu nếu có</div><div class="space"></div></div><div><b>KHÁCH HÀNG / ĐẠI DIỆN BÊN NHẬN</b><div class="muted">Ký, ghi rõ họ tên</div><div class="space"></div></div></div>
<p class="foot muted">Văn bản do đơn vị cung cấp lập và ký. Quyền sử dụng phần mềm căn cứ điều khoản giấy phép và hồ sơ mua bán kèm theo. Trạng thái kích hoạt là thông tin kỹ thuật tại thời điểm kiểm tra. Key đầy đủ không được ghi trong file này.</p></main></body></html>
'@
    $values=@{LOGO=$logo;SUPPLIER=(Enc $Supplier.Company);ADDRESS=(Enc $Supplier.Address);PHONE=(Enc $Supplier.Phone);TECH=(Enc $Supplier.Technician);KIND=$kind;DOC=$doc;DATE=([datetime]::Now.ToString('dd/MM/yyyy'));CUSTOMER=(Enc $Customer.Name);CUSTOMER_ADDRESS=(Enc $Customer.Address);TAX=$taxRow;REFERENCE=$refRow;COMPUTER=(Enc $Snapshot.Computer);MODEL=(Enc $Snapshot.Model);SERIAL=(Enc $Snapshot.Serial);PRODUCTS=($rows -join "`n");CHECKED=$stamp;EVIDENCE=$evidence}
    # One pass: input containing placeholder-like text must stay literal.
    $render=[Text.RegularExpressions.MatchEvaluator]{param($match)[string]$values[$match.Groups[1].Value]}
    return [regex]::Replace($html,'\{\{([A-Z_]+)\}\}',$render)
}
function Export-DeployLicenseConfirmation {
    param([ValidateSet('Retail','Company')][string]$Template,$Supplier,$Customer,$Snapshot,[object[]]$Products,[string]$Reference='',[string]$OutputDirectory)
    $html=New-DeployLicenseConfirmationHtml -Template $Template -Supplier $Supplier -Customer $Customer -Snapshot $Snapshot -Products $Products -Reference $Reference
    New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop|Out-Null
    $prefix=if($Template -eq 'Company'){'XacNhan-CongTy'}else{'XacNhan-KhachLe'}
    $path=Join-Path $OutputDirectory ($prefix+'-'+[datetime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.html')
    [IO.File]::WriteAllText($path,$html,[Text.UTF8Encoding]::new($true))
    return $path
}
