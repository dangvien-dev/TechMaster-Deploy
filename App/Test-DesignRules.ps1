# Checks the design rules in DESIGN.md on every WPF window of the app, laid out at 100 % and 150 % scale.
# Rules: (1) every CheckBox has a rounded box, (2) single-line inputs in rounded frames share one height,
# (3) inputs on the same row are top-aligned, (4) a button on an input's row has the input's height and top.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
$root=Split-Path -Parent $PSScriptRoot
$files=@(foreach($folder in 'App','FixClone','Office','KichHoat','BienBan'){
    Get-ChildItem -LiteralPath (Join-Path $root $folder) -Filter '*.xml' -ErrorAction SilentlyContinue | Where-Object {
        $head=[IO.File]::ReadAllText($_.FullName);$head.TrimStart([char]0xFEFF).TrimStart().StartsWith('<Window')
    }
})
Assert ($files.Count -ge 15) "All app windows are found ($($files.Count))"
function Get-DeployLogicalItems($start) {
    $queue=New-Object Collections.Queue;$queue.Enqueue($start)
    while($queue.Count){
        $item=$queue.Dequeue();$item
        foreach($child in [Windows.LogicalTreeHelper]::GetChildren($item)){if($child -is [Windows.DependencyObject]){$queue.Enqueue($child)}}
    }
}
function Get-DeployInputFrame($field) {
    $node=$field
    for($i=0;$i -lt 5 -and $node;$i++){
        $node=[Windows.LogicalTreeHelper]::GetParent($node)
        if($node -is [Windows.Controls.Border] -and $node.Tag -ceq 'RoundedClip'){return $node}
    }
    return $null
}
function Get-DeployRowKey($element) {
    # The Grid cell that holds the element: same Grid and row means the same visual row.
    $node=$element
    while($node){
        $parent=[Windows.LogicalTreeHelper]::GetParent($node)
        if($parent -is [Windows.Controls.Grid] -and $parent.ColumnDefinitions.Count -gt 1){return ([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($parent)).ToString()+':'+[Windows.Controls.Grid]::GetRow($node)}
        if($parent -isnot [Windows.Controls.StackPanel] -and $parent -isnot [Windows.Controls.Border]){return ''}
        $node=$parent
    }
    return ''
}
foreach($file in $files){
    $window=Import-DeployWindow $file.FullName
    try{
        $items=@(Get-DeployLogicalItems $window)
        foreach($box in @($items | Where-Object {$_ -is [Windows.Controls.CheckBox]})){
            [void]$box.ApplyTemplate()
            $frame=$box.Template.FindName('Box',$box)
            Assert ($frame -is [Windows.Controls.Border] -and $frame.CornerRadius.TopLeft -gt 0) "$($file.Name): CheckBox '$($box.Name)' has a rounded box"
        }
        $inputs=@($items | Where-Object {($_ -is [Windows.Controls.TextBox] -or $_ -is [Windows.Controls.PasswordBox] -or $_ -is [Windows.Controls.ComboBox]) -and (Test-DeploySingleLineInput $_)})
        $frames=@($inputs | ForEach-Object {Get-DeployInputFrame $_} | Where-Object {$_})
        foreach($frame in $frames){Assert ($frame.Height -eq $script:DeployInputHeight) "$($file.Name): input frame height is $($script:DeployInputHeight)"}
        $tabs=@($items | Where-Object {$_ -is [Windows.Controls.TabControl]})
        $pages=if($tabs.Count){@(0..($tabs[0].Items.Count-1))}else{@(0)}
        foreach($page in $pages){
            if($tabs.Count){$tabs[0].SelectedIndex=$page}
            foreach($scale in 1.0,1.5){
                $size=[Windows.Size]::new((1366/$scale),(900/$scale))
                $window.Content.Measure($size);$window.Content.Arrange([Windows.Rect]::new($size));$window.UpdateLayout()
                $shown=@($frames | Where-Object {$_.ActualHeight -gt 0})
                $rows=@{}
                foreach($frame in $shown){
                    $top=$frame.TranslatePoint([Windows.Point]::new(0,0),$window.Content).Y
                    $key=Get-DeployRowKey $frame
                    if($key){if(-not $rows.ContainsKey($key)){$rows[$key]=New-Object Collections.ArrayList};[void]$rows[$key].Add([pscustomobject]@{Top=$top;Height=$frame.ActualHeight})}
                    $parent=[Windows.LogicalTreeHelper]::GetParent($frame)
                    if($parent -is [Windows.Controls.Grid]){
                        foreach($button in @($parent.Children | Where-Object {$_ -is [Windows.Controls.Button] -and $_.ActualHeight -gt 0 -and [Windows.Controls.Grid]::GetRow($_) -eq [Windows.Controls.Grid]::GetRow($frame)})){
                            $buttonTop=$button.TranslatePoint([Windows.Point]::new(0,0),$window.Content).Y
                            Assert ([Math]::Abs($button.ActualHeight-$frame.ActualHeight) -lt 0.6 -and [Math]::Abs($buttonTop-$top) -lt 0.6) "$($file.Name): button '$($button.Content)' matches the height and top of the input on its row at $scale (button $($button.ActualHeight) @ $buttonTop, input $($frame.ActualHeight) @ $top)"
                        }
                    }
                }
                foreach($key in $rows.Keys){
                    $row=@($rows[$key])
                    if($row.Count -lt 2){continue}
                    $tops=@($row | ForEach-Object {$_.Top});$heights=@($row | ForEach-Object {$_.Height})
                    $spread=([double]($tops | Measure-Object -Maximum).Maximum)-([double]($tops | Measure-Object -Minimum).Minimum)
                    $heightSpread=([double]($heights | Measure-Object -Maximum).Maximum)-([double]($heights | Measure-Object -Minimum).Minimum)
                    Assert ($spread -lt 0.6 -and $heightSpread -lt 0.6) "$($file.Name): inputs on one row share top and height at $scale (tops $($tops -join ', '); heights $($heights -join ', '))"
                }
            }
        }
    }finally{$window.Close()}
}
Write-Host "PASS: $checks design rule assertions on $($files.Count) windows; rounded check boxes, input height, same-row alignment of inputs and buttons."
