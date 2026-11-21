. (Join-Path (Split-Path -Parent $PSScriptRoot) 'BienBan/LicenseConfirmation.Core.ps1')
function New-DeployLicenseConfirmationWindow {
    param([ValidateSet('Retail','Company')][string]$Template,$Supplier,[string]$CustomerName,$Snapshot,[string]$OutputDirectory,$Owner=$null,[string]$CustomerCompany='',[string]$CustomerAddress='')
    $view=Import-DeployWindow (Join-Path $PSScriptRoot 'LicenseConfirmationWindow.xml')
    $view.FindName('Heading').Text=if($Template -eq 'Company'){'Xác nhận cho khách công ty'}else{'Xác nhận cho khách lẻ'}
    $view.FindName('Description').Text='Xác nhận cung cấp và bàn giao bản quyền phần mềm'
    $view.FindName('SupplierInfo').Text='Đơn vị cung cấp: '+$Supplier.Company
    $view.FindName('CustomerName').Text=$CustomerName
    $view.FindName('CustomerCompany').Text=$CustomerCompany
    $view.FindName('CustomerAddress').Text=$CustomerAddress
    $view.FindName('CompanyFields').Visibility=if($Template -eq 'Company'){'Visible'}else{'Collapsed'}
    $choices=@()
    foreach($product in $Snapshot.Products){
        $panel=[Windows.Controls.StackPanel]::new();$panel.Margin='0,0,0,14'
        $box=[Windows.Controls.CheckBox]::new();$box.Content='Bàn giao sản phẩm này';$box.IsChecked=$false
        $frame=[Windows.Controls.Border]::new();$frame.Style=$view.FindResource('RoundedInput');$frame.Tag='RoundedClip';$frame.Margin='0,4,0,6'
        $name=[Windows.Controls.TextBox]::new();$name.Text=$product.Name;$name.BorderThickness=0;$name.Margin=0;$frame.Child=$name;Initialize-DeployRoundedBorder $frame
        $status=[Windows.Controls.TextBlock]::new();$status.Text=$product.Status+$(if($product.KeyTail){' · *****-'+$product.KeyTail}else{''});$status.TextWrapping='Wrap';$status.Foreground='#526880'
        [void]$panel.Children.Add($box);[void]$panel.Children.Add($frame);[void]$panel.Children.Add($status);[void]$view.FindName('Products').Children.Add($panel)
        $choices+=@{Check=$box;Name=$name;Product=$product}
    }
    $view.Tag=@{Template=$Template;Supplier=$Supplier;Snapshot=$Snapshot;OutputDirectory=$OutputDirectory;Choices=$choices;Path=''}
    $view.FindName('Export').Add_Click({param($sender,$event)
        $dialog=[Windows.Window]::GetWindow($sender);$state=$dialog.Tag
        try{
            $products=@(foreach($choice in $state.Choices){if($choice.Check.IsChecked){[pscustomobject]@{Name=$choice.Name.Text.Trim();KeyTail=$choice.Product.KeyTail;Status=$choice.Product.Status}}})
            $customer=[pscustomobject]@{Name=$dialog.FindName('CustomerName').Text.Trim();Company=$dialog.FindName('CustomerCompany').Text.Trim();Address=$dialog.FindName('CustomerAddress').Text.Trim();TaxCode=$dialog.FindName('CustomerTaxCode').Text.Trim()}
            $ref=if($state.Template -eq 'Company'){$dialog.FindName('Reference').Text.Trim()}else{''}
            $path=Export-DeployLicenseConfirmation -Template $state.Template -Supplier $state.Supplier -Customer $customer -Snapshot $state.Snapshot -Products $products -Reference $ref -OutputDirectory $state.OutputDirectory
            $state.Path=$path
            $dialog.FindName('Validation').Foreground='#166534';Set-DeployNotice ($dialog.FindName('Validation')) 'Đã lưu file. Đang mở để xem / in.' 'Success'
            Start-Process -FilePath $path|Out-Null
            $dialog.Close()
        }catch{$dialog.FindName('Validation').Foreground='#B91C1C';Set-DeployNotice ($dialog.FindName('Validation')) $_.Exception.GetBaseException().Message 'Error'}
    })
    $view.FindName('Cancel').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    if($Owner -and $Owner.IsVisible){$view.Owner=$Owner}
    return $view
}
