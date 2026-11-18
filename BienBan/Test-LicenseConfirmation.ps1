$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LicenseConfirmation.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function Get-CimInstance {
    param($ClassName,$Filter)
    switch($ClassName){
        Win32_ComputerSystem {[pscustomobject]@{Manufacturer='TEST';Model='Model <script>'}}
        Win32_BIOS {[pscustomobject]@{SerialNumber='SN-TEST'}}
        SoftwareLicensingProduct {
            if($script:queryFailure){throw 'fixture query failed'}
            if($Filter -match '55c92734'){[pscustomobject]@{Name='Windows 11 Pro';PartialProductKey='ABCDE-SECRET-12345';LicenseStatus=$script:windowsState}}
            else{[pscustomobject]@{Name='Office Home & Business 2024';PartialProductKey='VWXYZ';LicenseStatus=2}}
        }
    }
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-confirmation-'+[guid]::NewGuid().ToString('N'))
try{
    $script:windowsState=1;$script:queryFailure=$false;$snapshot=Get-DeployConfirmationSnapshot
    Assert ($snapshot.Products.Count -eq 2 -and $snapshot.Products[0].KeyTail -eq '12345') 'Snapshot excludes all but the last five key characters'
    Assert ($snapshot.Products[1].Status -match 'dùng thử' -and -not $snapshot.Products[0].Selected) 'Trial state is preserved and no product is preselected'
    $supplier=[pscustomobject]@{Company='Đơn vị <script> & {{CUSTOMER}}';Address='Địa chỉ mẫu';Phone='000';Technician='KTV'}
    $customer=[pscustomobject]@{Name='Khách <script>alert(1)</script>';Address='Địa chỉ khách';TaxCode='TAX-TEST'}
    $retail=Export-DeployLicenseConfirmation -Template Retail -Supplier $supplier -Customer $customer -Snapshot $snapshot -Products @($snapshot.Products[0]) -Reference 'HĐ-PRIVATE' -OutputDirectory $temp
    $html=[IO.File]::ReadAllText($retail)
    Assert ($html -match 'KHÁCH HÀNG CÁ NHÂN' -and $html -notmatch 'đã cấp và bàn giao hóa đơn|HĐ-PRIVATE|TAX-TEST') 'Retail template does not claim an invoice or leak company-only fields'
    Assert ($html -match 'Windows 11 Pro' -and $html -notmatch 'Office Home') 'Only the selected delivered product appears'
    Assert ($html -notmatch 'ABCDE-SECRET' -and $html -match '\*\*\*\*\*-12345') 'Full key is never included in the exported document'
    Assert ($html -match '&lt;script&gt;' -and $html -notmatch '<script>') 'Customer, machine and supplier text are HTML escaped'
    Assert ($html -match '\{\{CUSTOMER\}\}') 'Placeholder-like user input remains literal rather than being expanded'
    $company=Export-DeployLicenseConfirmation -Template Company -Supplier $supplier -Customer $customer -Snapshot $snapshot -Products $snapshot.Products -OutputDirectory $temp
    $html=[IO.File]::ReadAllText($company)
    Assert ($html -match 'KHÁCH HÀNG CÔNG TY' -and $html -match 'đã cấp và bàn giao hóa đơn / chứng từ') 'Company template refers to the evidence already issued'
    Assert ($html -notmatch 'Hóa đơn / chứng từ tham chiếu' -and $html -match 'TAX-TEST') 'An unknown invoice number can be omitted without inventing a reference'
    Assert ([Net.WebUtility]::HtmlDecode($html) -match 'Chưa kích hoạt \(dùng thử\)' -and $html -notmatch 'Tất cả.*Đã kích hoạt') 'Company confirmation does not turn a trial into an activated product'
    Assert ($html -match 'Đại diện ký' -and $html -match 'hồ sơ mua bán kèm theo' -and $html -match 'In / Lưu PDF') 'Document has supplier/customer signature areas and a printable handover format'
    $html=New-DeployLicenseConfirmationHtml -Template Company -Supplier $supplier -Customer $customer -Snapshot $snapshot -Products @($snapshot.Products[0]) -Reference 'HD<123>'
    Assert ($html -match 'HD&lt;123&gt;') 'Optional invoice reference is escaped'
    $blocked=$false;try{Export-DeployLicenseConfirmation -Template Retail -Supplier $supplier -Customer $customer -Snapshot $snapshot -Products @() -OutputDirectory $temp|Out-Null}catch{$blocked=$true}
    Assert ($blocked -and @(Get-ChildItem $temp -File).Count -eq 2) 'No file is written without an explicit delivered product selection'
    $blocked=$false;try{New-DeployLicenseConfirmationHtml -Template Retail -Supplier $supplier -Customer ([pscustomobject]@{Name=''}) -Snapshot $snapshot -Products $snapshot.Products|Out-Null}catch{$blocked=$true}
    Assert $blocked 'An unnamed customer cannot be issued a confirmation'
    $script:windowsState=2;$grace=Get-DeployConfirmationSnapshot
    Assert ($grace.Products[0].Status -match 'OOBGrace' -and $grace.Products[0].Status -notmatch 'dùng thử') 'Windows confirmation identifies grace without inventing a trial key'
    $script:queryFailure=$true;$unknown=Get-DeployConfirmationSnapshot
    Assert ($unknown.Products.Count -eq 2 -and $unknown.Products[0].Status -match 'Chưa đọc') 'Query failures remain unknown rather than being called licensed'
    Assert ($retail -ne $company) 'The two templates generate separate uniquely named files'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Host "PASS: $checks confirmation assertions; two templates, evidence, escaped inputs, key masking, explicit selection and unknown activation."
