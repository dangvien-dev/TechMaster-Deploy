# Plain-text documentation rendered with WPF; Markdown is never executed as XAML or HTML.
# This component is also opened before the updater has ever been loaded.
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
function ConvertTo-DeployInfoText([string]$text){return ($text -replace '\[([^\]]+)\]\([^)]+\)','$1' -replace '`','' -replace '\*\*','').Trim()}
function Get-DeployInfoSections([string]$path,[switch]$ReleaseNotes) {
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    $sections=[Collections.Generic.List[object]]::new();$current=$null
    foreach($line in [IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)){
        if($line -match '^##\s+(.+)$'){
            $heading=$Matches[1].Trim();$label=$heading;$subtitle='Hướng dẫn sử dụng'
            if($ReleaseNotes -and $heading -match '^(\d+(?:\.\d+){1,3})\s*[—–-]\s*(.+)$'){
                $label=$Matches[1];$subtitle='Ngày cập nhật: '+$Matches[2];$heading='Phiên bản '+$label
            }
            $current=[pscustomobject]@{Label=$label;Heading=$heading;Subtitle=$subtitle;Notes=[Collections.Generic.List[string]]::new()}
            $sections.Add($current)
        }elseif($current -and $line -match '^\s*-\s+(.+)$'){
            $current.Notes.Add((ConvertTo-DeployInfoText $Matches[1]))
        }elseif($current -and $current.Notes.Count -gt 0 -and $line.Trim() -and $line -notmatch '^#'){
            $current.Notes[$current.Notes.Count-1]+=' '+(ConvertTo-DeployInfoText $line)
        }
    }
    return $sections.ToArray()
}
function Set-DeployInfoSelection($view,$item){
    if(-not $view -or -not $item){return}
    $view.FindName('ContentTitle').Text=$item.Heading
    $view.FindName('ContentSubtitle').Text=$item.Subtitle
    $view.FindName('Notes').ItemsSource=$item.Notes
    $view.FindName('ContentScroll').ScrollToTop()
}
function New-DeployInfoWindow {
    param([string]$Root,[ValidateSet('Changes','Guide')][string]$Kind='Guide',$Owner=$null,[string]$Section='')
    $window=Import-DeployWindow (Join-Path $PSScriptRoot 'InfoWindow.xml')
    $title=if($Kind -eq 'Changes'){'Có gì mới'}else{'Hướng dẫn nhanh'}
    $window.Title='TechMaster Deploy — '+$title;$window.FindName('Heading').Text=$title
    $window.FindName('VersionInfo').Text='TechMaster Deploy · Phiên bản '+(Get-DeployVersion $Root)
    $path=Join-Path $Root $(if($Kind -eq 'Changes'){'CHANGELOG.md'}else{'App/QuickGuide.md'})
    $items=@(Get-DeployInfoSections $path -ReleaseNotes:($Kind -eq 'Changes'))
    $list=$window.FindName('Sections');$list.ItemsSource=$items
    $list.Add_SelectionChanged({param($sender,$event)
        $view=[Windows.Window]::GetWindow($sender);$item=$sender.SelectedItem
        Set-DeployInfoSelection $view $item
    })
    if($items.Count){
        $index=0
        for($i=0;$i -lt $items.Count;$i++){if($items[$i].Label -eq $Section){$index=$i;break}}
        $list.SelectedIndex=$index
        Set-DeployInfoSelection $window $items[$index]
    }else{$window.FindName('ContentTitle').Text='Chưa có nội dung';$window.FindName('ContentSubtitle').Text='Giữ nguyên toàn bộ thư mục ứng dụng và thử lại sau khi cập nhật.'}
    foreach($name in 'ZaloLink','MailLink'){
        $window.FindName($name).Add_RequestNavigate({param($sender,$event)
            if($event.Uri.AbsoluteUri -in 'https://zalo.me/0976852096','mailto:vienkendo@gmail.com'){Start-Process -FilePath $event.Uri.AbsoluteUri|Out-Null}
            $event.Handled=$true
        })
    }
    $window.FindName('CopyContact').Add_Click({param($sender,$event)
        $view=[Windows.Window]::GetWindow($sender)
        try{[Windows.Clipboard]::SetText("Zalo: 0976852096`r`nEmail: vienkendo@gmail.com");$view.FindName('ContactStatus').Text='Đã sao chép thông tin liên hệ.'}
        catch{$view.FindName('ContactStatus').Text='Chưa sao chép được. Vui lòng thử lại.'}
    })
    $window.FindName('Close').Add_Click({param($sender,$event)[Windows.Window]::GetWindow($sender).Close()})
    if($Owner -and $Owner.IsVisible){$window.Owner=$Owner;$window.WindowStartupLocation='CenterOwner'}
    return $window
}
function Show-DeployChangeLog([string]$Root,$Owner=$null){$view=New-DeployInfoWindow $Root -Kind Changes -Owner $Owner;[void]$view.ShowDialog()}
function Show-DeployQuickGuide([string]$Root,$Owner=$null,[string]$Section=''){$view=New-DeployInfoWindow $Root -Kind Guide -Owner $Owner -Section $Section;[void]$view.ShowDialog()}
