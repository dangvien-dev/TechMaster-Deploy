$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Info.UI.ps1')
. (Join-Path $PSScriptRoot 'Report.Identity.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-info-'+[guid]::NewGuid().ToString('N')+'.md')
try{
    [IO.File]::WriteAllText($temp,@'
# Test
## 2.0.0.0 — 17/11/2026
- **Nội dung** và `mã` [tài liệu](https://example.com).
  dòng tiếp theo
- <script>literal</script>
## 1.0.0.0 — 16/11/2026
- Bản cũ
'@,[Text.UTF8Encoding]::new($false))
    $releases=@(Get-DeployInfoSections $temp -ReleaseNotes)
    Assert ($releases.Count -eq 2 -and $releases[0].Label -eq '2.0.0.0' -and $releases[1].Label -eq '1.0.0.0') 'Release order and versions are preserved'
    Assert ($releases[0].Subtitle -match '17/11/2026') 'Date is shown separately from the version'
    Assert ($releases[0].Notes[0] -ceq 'Nội dung và mã tài liệu. dòng tiếp theo') 'Inline formatting and continuation lines become readable text'
    Assert ($releases[0].Notes[1] -ceq '<script>literal</script>') 'Markup remains literal text for the WPF Text binding'
    Assert (@(Get-DeployInfoSections ($temp+'.missing')).Count -eq 0) 'Missing documentation has an empty-state result'
    $guide=@(Get-DeployInfoSections (Join-Path $PSScriptRoot 'QuickGuide.md'))
    foreach($label in 'Máy gốc / Sysprep','Sau khi clone','Kích hoạt','Biên bản bản quyền','Tải / cài Office','Cài Windows','Cài ứng dụng','Cập nhật / khôi phục','Liên hệ / góp ý'){
        Assert (@($guide|Where-Object {$_.Label -eq $label -and $_.Notes.Count -gt 0}).Count -eq 1) "Guide covers $label"
    }
    $identityDir=$temp+'.identity';New-Item -ItemType Directory -Path $identityDir|Out-Null
    foreach($name in 'BienBan-Config.json','Logo.svg','Logo.png','customer-report.html','unrelated.log'){[IO.File]::WriteAllText((Join-Path $identityDir $name),'fixture')}
    Reset-DeployReportIdentity $identityDir
    Assert (-not (Test-Path (Join-Path $identityDir 'BienBan-Config.json')) -and -not (Test-Path (Join-Path $identityDir 'Logo.svg'))) 'Identity reset removes configuration and logo assets'
    Assert ((Test-Path (Join-Path $identityDir 'customer-report.html')) -and (Test-Path (Join-Path $identityDir 'unrelated.log'))) 'Identity reset retains existing reports and unrelated files'
}finally{if(Test-Path $temp){Remove-Item $temp -Force};if(Test-Path ($temp+'.identity')){Remove-Item ($temp+'.identity') -Recurse -Force}}
Write-Host "PASS: $checks documentation assertions; versions/dates, readable notes, literal text, empty state and feature coverage."
