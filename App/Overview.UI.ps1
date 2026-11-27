# Fills the Tổng quan page from Get-DeployOverviewSnapshot; the snapshot is kept on the copy button.
function Set-DeployOverviewView($Window,$Snapshot) {
    foreach($field in $script:DeployOverviewFields){$Window.FindName('ov'+$field.Name).Text=[string]$Snapshot.($field.Name)}
    $copy=$Window.FindName('btnOverviewCopy');$copy.Tag=$Snapshot;$copy.IsEnabled=$true
    $notes=@('Đã đọc lúc '+(Get-Date -Format 'HH:mm')+'.')
    $kind='Success'
    if([string]$Snapshot.WindowsLicense -like 'CHƯA*'){$notes+='Windows chưa kích hoạt: mở Bản quyền & biên bản.';$kind='Attention'}
    $unknown=@($script:DeployOverviewFields | Where-Object {[string]$Snapshot.($_.Name) -ceq $script:DeployOverviewUnknown} | ForEach-Object {$_.Label})
    if($unknown.Count){$notes+=('Chưa đọc được: '+($unknown -join ', ')+'.');$kind='Attention'}
    Set-DeployNotice ($Window.FindName('ovState')) ($notes -join ' ') $kind
}
function Set-DeployOverviewBusy($Window) {
    Set-DeployNotice ($Window.FindName('ovState')) 'Đang đọc thông tin máy và bản quyền…' 'Working'
}
