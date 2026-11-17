function Set-DeployCustomAppFields($window,$app=$null) {
    $window.Tag.Key=if($app){$app.Key}else{''}
    $window.FindName('AppName').Text=if($app){$app.Name}else{''}
    $window.FindName('PackageId').Text=if($app -and $app.Source -eq 'WinGet'){$app.Id}else{''}
    $window.FindName('InstallerPath').Text=if($app){$app.Path}else{''}
    $window.FindName('Arguments').Text=if($app){$app.Arguments}else{''}
    $window.FindName('Provider').SelectedIndex=if($app -and $app.Source -eq 'Local'){1}else{0}
    $window.FindName('Delete').IsEnabled=[bool]$app
}
function New-DeployCustomAppsWindow([string]$path,$builtIn,$Owner=$null) {
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'CustomAppsWindow.xml')
    $items=[Collections.ArrayList]::new();foreach($app in @(Get-DeployCustomApps $path)){[void]$items.Add($app)}
    $window.Tag=@{Path=$path;Items=$items;BuiltIn=$builtIn;Key='';Changed=$false}
    $window.FindName('Apps').ItemsSource=$items
    $window.FindName('Apps').Add_SelectionChanged({param($sender,$event) Set-DeployCustomAppFields ([Windows.Window]::GetWindow($sender)) $sender.SelectedItem})
    $window.FindName('Provider').Add_SelectionChanged({param($sender,$event)
        $view=[Windows.Window]::GetWindow($sender);if(-not $view){return}
        $local=$sender.SelectedItem.Tag -eq 'Local'
        $view.FindName('LocalFields').Visibility=if($local){'Visible'}else{'Collapsed'}
        $view.FindName('WingetFields').Visibility=if($local){'Collapsed'}else{'Visible'}
    })
    $window.FindName('New').Add_Click({param($sender,$event)$view=[Windows.Window]::GetWindow($sender);$view.FindName('Apps').SelectedIndex=-1;Set-DeployCustomAppFields $view})
    $window.FindName('Browse').Add_Click({param($sender,$event)
        $file=Select-DeployFile 'Chọn bộ cài' 'Bộ cài (*.exe;*.msi)|*.exe;*.msi'
        if($file){[Windows.Window]::GetWindow($sender).FindName('InstallerPath').Text=$file}
    })
    $window.FindName('Save').Add_Click({param($sender,$event)
        $view=[Windows.Window]::GetWindow($sender);$state=$view.Tag
        try{
            $item=New-DeployCustomApp -Name $view.FindName('AppName').Text -Source $view.FindName('Provider').SelectedItem.Tag -PackageId $view.FindName('PackageId').Text -Path $view.FindName('InstallerPath').Text -Arguments $view.FindName('Arguments').Text -Key $state.Key
            if($item.Source -eq 'Local' -and -not (Test-Path -LiteralPath $item.Path -PathType Leaf)){throw 'Chọn một bộ cài EXE / MSI đang có trên máy.'}
            if(@($state.BuiltIn|Where-Object {$_.Id -eq $item.Id -or $_.Name -eq $item.Name}).Count){throw 'Ứng dụng này đã có trong danh sách mặc định.'}
            if(@($state.Items|Where-Object {$_.Key -ne $item.Key -and ($_.Id -eq $item.Id -or $_.Name -eq $item.Name)}).Count){throw 'Tên hoặc ID ứng dụng đã có trong danh sách bổ sung.'}
            $next=@($state.Items|Where-Object Key -ne $item.Key)+@($item)
            Save-DeployCustomApps $state.Path $next
            $state.Items.Clear();foreach($record in $next){[void]$state.Items.Add($record)}
            $view.FindName('Apps').Items.Refresh();$view.FindName('Apps').SelectedItem=$item
            $state.Key=$item.Key;$state.Changed=$true;$view.FindName('Status').Text='Đã lưu trên máy này. Cập nhật app vẫn giữ danh sách bổ sung.'
        }catch{Show-DeployMessage $_.Exception.Message 'Chưa lưu được ứng dụng' 'Error'}
    })
    $window.FindName('Delete').Add_Click({param($sender,$event)
        $view=[Windows.Window]::GetWindow($sender);$state=$view.Tag
        if(-not $state.Key){return}
        if(-not (Confirm-Box 'Xoá mục khỏi danh sách bổ sung? Không gỡ ứng dụng hoặc xoá bộ cài.' 'Xoá mục ứng dụng' -ConfirmText 'Xoá mục' -Owner $view)){return}
        try{
            $next=@($state.Items|Where-Object Key -ne $state.Key);Save-DeployCustomApps $state.Path $next
            $state.Items.Clear();foreach($record in $next){[void]$state.Items.Add($record)}
            $view.FindName('Apps').Items.Refresh();Set-DeployCustomAppFields $view;$state.Changed=$true;$view.FindName('Status').Text='Đã xoá mục khỏi danh sách trên máy này.'
        }catch{Show-DeployMessage $_.Exception.Message 'Chưa xoá được mục' 'Error'}
    })
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    Set-DeployCustomAppFields $window
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployCustomApps([string]$path,$builtIn,$Owner=$null){$window=New-DeployCustomAppsWindow $path $builtIn $Owner;[void]$window.ShowDialog();return [bool]$window.Tag.Changed}
