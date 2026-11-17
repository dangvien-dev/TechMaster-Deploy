$runtime=@((Join-Path $PSScriptRoot 'App/Wpf.Runtime.ps1'),(Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Wpf.Runtime.ps1')) | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $runtime){throw 'Thiếu bộ giao diện App. Giữ nguyên toàn bộ thư mục TechMaster-Deploy khi chạy công cụ.'}
. $runtime
