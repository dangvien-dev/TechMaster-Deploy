. (Join-Path $PSScriptRoot 'DriverFix.Core.ps1')
function ConvertTo-DriverFixHtml($Value){[Net.WebUtility]::HtmlEncode([string]$Value)}
function ConvertTo-DriverFixDeviceHtml([object[]]$Devices) {
    if(-not $Devices.Count){return '<p>Không có.</p>'}
    $rows=foreach($d in $Devices){
        $ids=@($d.HardwareIds|ForEach-Object {ConvertTo-DriverFixHtml $_})-join '<br>'
        $links=@(Get-DriverFixCatalogLinks $d.HardwareIds|ForEach-Object {'<a href="'+(ConvertTo-DriverFixHtml $_.Url)+'">'+(ConvertTo-DriverFixHtml $_.Query)+'</a>'})-join '<br>'
        '<tr><td>'+(ConvertTo-DriverFixHtml $d.Name)+'</td><td>'+[int]$d.ErrorCode+' — '+(ConvertTo-DriverFixHtml $d.Description)+'</td><td class="id">'+$ids+'<br><small>InstanceId: '+(ConvertTo-DriverFixHtml $d.InstanceId)+'</small></td><td>'+$links+'</td></tr>'
    }
    return '<table><thead><tr><th>Thiết bị</th><th>Trạng thái</th><th>Hardware ID / InstanceId</th><th>Microsoft Update Catalog</th></tr></thead><tbody>'+($rows -join '')+'</tbody></table>'
}
function Export-DriverFixReport($Session) {
    $dir=Join-Path $Session.Home 'Reports';New-Item -ItemType Directory -Path $dir -Force|Out-Null
    $name=([string]$Session.Machine.ComputerName -replace '[^A-Za-z0-9_.-]','_')+'_'+(Get-Date -Format 'yyyyMMdd-HHmm')
    $path=Join-Path $dir ($name+'.html');$n=1
    while(Test-Path -LiteralPath $path){$path=Join-Path $dir ($name+'_'+$n+'.html');$n++}
    $machine=$Session.Machine;$delta=Compare-DriverFixSnapshot $Session.Before $Session.Current
    $info=foreach($field in 'ComputerName','Manufacturer','Model','CPU','Board','BiosVendor','Bios','RamGB','OS'){'<tr><th>'+ $field +'</th><td>'+(ConvertTo-DriverFixHtml $machine.$field)+'</td></tr>'}
    $actions=foreach($a in $Session.Actions){'<tr><td>'+(ConvertTo-DriverFixHtml $a.Kind)+'</td><td class="id">'+(ConvertTo-DriverFixHtml ($a.DeviceId+' '+$a.Source))+'</td><td>'+(ConvertTo-DriverFixHtml ($a.Success.ToString()+' / Exit '+$a.ExitCode+' / Reboot '+$a.RebootRequired))+'</td><td>'+(ConvertTo-DriverFixHtml $a.Message)+'</td></tr>'}
    $html=@'
<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Fix Driver — báo cáo</title>
<style>body{font:15px Segoe UI,Arial,sans-serif;color:#10223f;background:#f3f6fb;margin:24px}main{background:white;padding:28px;border-radius:14px;max-width:1400px;margin:auto}h1,h2{color:#10223f}table{border-collapse:collapse;width:100%;margin:14px 0 26px;table-layout:fixed}td,th{padding:10px;text-align:left;vertical-align:top;border:1px solid #dce4ee;overflow-wrap:anywhere}th{background:#e8eff8}.id{font:12px Consolas,monospace}a{color:#006bb6}pre{white-space:pre-wrap;overflow-wrap:anywhere}small{color:#526880}@media print{body{margin:0;background:white}main{padding:0}thead{display:table-header-group}}</style><main><h1>Fix Driver — báo cáo xử lý</h1>
'@
    $html+='<p>Quét đầu: '+(ConvertTo-DriverFixHtml $Session.Before.Time)+' · Quét cuối: '+(ConvertTo-DriverFixHtml $Session.Current.Time)+'</p><table>'+($info -join '')+'</table>'
    $html+='<p>Đã xác nhận hoạt động (Code 0): '+$delta.Resolved.Count+' · Không còn xuất hiện: '+$delta.Disappeared.Count+' · Đang disable (Code 22): '+$delta.Disabled.Count+' · Thiết bị lỗi mới: '+$delta.NewProblems.Count+'</p>'
    $html+='<p>pnputil thành công có thể chỉ thêm gói vào Driver Store. Danh sách Code 0 bên dưới mới xác nhận thiết bị hoạt động. Thiết bị biến mất hoặc disable không được tính là sửa xong.</p>'
    $html+='<h2>Trước xử lý</h2>'+(ConvertTo-DriverFixDeviceHtml @($Session.Before.Problems))
    $html+='<h2>Các lệnh cài / disable / chỉnh nguồn đã thực hiện</h2><table><tr><th>Thao tác</th><th>Thiết bị / nguồn</th><th>Kết quả lệnh</th><th>Ghi chú</th></tr>'+($actions -join '')+'</table>'
    $html+='<h2>Đã chuyển sang Code 0</h2>'+(ConvertTo-DriverFixDeviceHtml @($Session.Current.All|Where-Object {$_.InstanceId -in @($delta.Resolved|ForEach-Object InstanceId)}))
    $html+='<h2>Không còn xuất hiện — cần kiểm tra lại</h2>'+(ConvertTo-DriverFixDeviceHtml @($delta.Disappeared))
    $html+='<h2>Sau xử lý — còn lỗi / đã disable</h2>'+(ConvertTo-DriverFixDeviceHtml @($Session.Current.Problems))
    $html+='<h2>Profile và thứ tự đề xuất</h2><pre>'+(ConvertTo-DriverFixHtml (Get-DriverFixProfileText $Session.Profile))+'</pre><p>Nhật ký chi tiết cục bộ: <span class="id">'+(ConvertTo-DriverFixHtml $Session.LogPath)+'</span></p></main></html>'
    [IO.File]::WriteAllText($path,$html,[Text.UTF8Encoding]::new($false))
    Write-DriverFixLog $Session 'report' @{path=$path}
    return $path
}
