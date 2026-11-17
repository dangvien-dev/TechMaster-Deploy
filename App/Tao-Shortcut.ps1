<#
  Tạo shortcut "TechMaster Deploy" có icon logo:
    - Ngoài Desktop của user hiện tại
    - Ngay trong thư mục TechMaster-Deploy (tiện khi chạy từ USB)
  Đồng thời đặt icon cho chính thư mục TechMaster-Deploy (desktop.ini, đường dẫn tương đối
  nên đổi ký tự ổ USB vẫn giữ icon).
  Shortcut dùng đường dẫn tuyệt đối: chép thư mục sang chỗ khác / USB đổi ký tự ổ thì chạy lại file này.
#>
. (Join-Path $PSScriptRoot 'Console.ps1')
Initialize-TechMasterConsole
$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root 'TechMaster Deploy.exe'
$ico  = Join-Path $PSScriptRoot 'TechMaster.ico'
if (-not (Test-Path $exe) -or -not (Test-Path $ico)) { Write-Host "Thiếu TechMaster Deploy.exe hoặc biểu tượng của ứng dụng." -ForegroundColor Red; exit 1 }

$sh = New-Object -ComObject WScript.Shell
foreach ($dir in @([Environment]::GetFolderPath('Desktop'), $root)) {
    $lnkPath = Join-Path $dir 'TechMaster Deploy.lnk'
    $lnk = $sh.CreateShortcut($lnkPath)
    $lnk.TargetPath       = $exe
    $lnk.WorkingDirectory = $root
    $lnk.IconLocation     = "$ico,0"
    $lnk.WindowStyle      = 1
    $lnk.Description      = 'TechMaster Deploy - Clone / Kích hoạt / Biên bản bản quyền'
    $lnk.Save()
    Write-Host "  [OK] $lnkPath" -ForegroundColor Green
}

# Icon cho thư mục (desktop.ini, đường dẫn tương đối)
$ini = Join-Path $root 'desktop.ini'
if (Test-Path $ini) { attrib -s -h "$ini" | Out-Null }
"[.ShellClassInfo]`r`nIconResource=App\TechMaster.ico,0`r`n" | Set-Content $ini -Encoding Unicode
attrib +s +h "$ini" | Out-Null
attrib +r "$root" | Out-Null      # Windows chỉ đọc desktop.ini khi thư mục có thuộc tính ReadOnly/System
Write-Host "  [OK] Icon thư mục (có thể cần F5 hoặc vài giây để Explorer cập nhật)" -ForegroundColor Green
