<#
  Chạy trên MÁY GỐC, bằng user đã thiết lập sẵn (Chrome mặc định...), TRƯỚC sysprep.
  Run-Sysprep.bat tự gọi script này.
  Chuyển các thiết lập theo user thành thiết lập toàn máy để user mới trên máy clone nhận được:
    1. Ứng dụng mặc định (Chrome...) -> DISM Import-DefaultAppAssociations
    2. Shortcut Word, Excel ra Public Desktop (mọi user đều thấy)
    3. EVKey tự khởi động cho mọi user (HKLM\...\Run)
    4. Thiết lập Word (Normal.dotm, ribbon, Options) -> Default profile
    5. Menu chuột phải kiểu Windows 10 (user hiện tại + Default profile)
    6. Chỉ dấu số: thập phân ",", phân nhóm "."; giữ nguyên vùng và ngôn ngữ
#>
$ErrorActionPreference = 'Continue'
$consoleInit = Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Console.ps1'
if (Test-Path -LiteralPath $consoleInit -PathType Leaf) {
    . $consoleInit
    Initialize-TechMasterConsole
}
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }

. (Join-Path $PSScriptRoot 'Master.Preflight.Core.ps1')

$work = 'C:\FixClone'
if (-not (Test-Path $work)) { New-Item -ItemType Directory $work | Out-Null }

# ---------- 1. Ứng dụng mặc định ----------
Write-Host "`n=== 1. UNG DUNG MAC DINH ===" -ForegroundColor Cyan
$xml = Join-Path $work 'DefaultApps.xml'
& dism.exe /Online /Export-DefaultAppAssociations:"$xml" | Out-Null
if (Test-Path $xml) {
    $chrome = Select-String -Path $xml -Pattern 'ChromeHTML' -Quiet
    if (-not $chrome) {
        Write-Warn "File xuất ra KHÔNG có ChromeHTML -> user hiện tại chưa đặt Chrome làm mặc định."
        Write-Warn "Đặt Chrome mặc định (Settings > Apps > Default apps > Chrome > Set default) rồi chạy lại."
    }
    if (Add-ScreenClipDefault $xml) { Write-Ok 'Đã thêm lựa chọn ms-screenclip vào cấu hình cho user mới (không chép UserChoice hash).' }
    else { Write-Warn 'Chưa có mặc định ms-screenclip. Chọn Screen Snipping và Always rồi chạy lại trước khi Sysprep.' }
    & dism.exe /Online /Import-DefaultAppAssociations:"$xml" | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Đã import $xml (áp dụng cho user tạo mới)" }
    else { Write-Warn "DISM import lỗi, ExitCode $LASTEXITCODE" }
} else {
    Write-Warn "Không xuất được DefaultApps.xml"
}

# ---------- 2. Shortcut Word, Excel ra Public Desktop ----------
Write-Host "`n=== 2. SHORTCUT DESKTOP ===" -ForegroundColor Cyan
try {
    $plans = @(Get-OfficeShortcutPlan)
    # Creating a shared icon is safe only if no personal icon would duplicate it.
    $newOnly = @($plans | Where-Object { $_.Create -and @($_.Remove).Count -eq 0 })
    if ($newOnly.Count) { Invoke-OfficeShortcutPlan $newOnly (Join-Path $work 'Desktop Backups') }
    $pending = @($plans | Where-Object { @($_.Remove).Count -gt 0 })
    if ($pending.Count) { Write-Warn 'Còn icon Word / Excel trùng. Dùng Sao lưu và dọn icon trùng trong cửa sổ kiểm tra; chưa tạo thêm icon cho các mục này.' }
    else { Write-Ok 'Mỗi ứng dụng dùng một shortcut Desktop; thiết lập Word được giữ riêng ở bước 4.' }
} catch { Write-Warn ('Chưa kiểm tra được shortcut: ' + $_.Exception.Message) }

# ---------- 3. EVKey tự khởi động ----------
Write-Host "`n=== 3. EVKEY TU KHOI DONG ===" -ForegroundColor Cyan
$roots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", 'C:\', "$env:ProgramData", "$env:LOCALAPPDATA", "$env:APPDATA",
           "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents", "$env:USERPROFILE\Downloads") | Where-Object { $_ -and (Test-Path $_) }
$evk = $null
foreach ($r in $roots) {
    $depth = if ($r -eq 'C:\') { 2 } else { 3 }
    $evk = Get-ChildItem $r -Recurse -Depth $depth -Include 'EVKey64.exe', 'EVKey32.exe', 'EVKey.exe' -File -ErrorAction SilentlyContinue |
           Sort-Object { $_.Name -ne 'EVKey64.exe' } | Select-Object -First 1
    if ($evk) { break }
}
if (-not $evk) {
    Write-Warn "Không tìm thấy EVKey. Bỏ thư mục EVKey vào C:\Program Files\EVKey rồi chạy lại."
} else {
    $userPath = "$env:USERPROFILE"
    if ($evk.FullName -like "$userPath*") {
        # Nằm trong profile user -> máy clone không có, chuyển ra Program Files
        $dest = "$env:ProgramFiles\EVKey"
        Copy-Item $evk.DirectoryName -Destination $dest -Recurse -Force
        $evkPath = Join-Path $dest $evk.Name
        Write-Ok "EVKey nằm trong thư mục user -> đã copy sang $dest"
    } else { $evkPath = $evk.FullName }
    # Xoá autostart theo user (nếu có) để tránh chạy 2 lần trên máy gốc
    Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
        Get-Member -MemberType NoteProperty | Where-Object Name -match 'EVKey' |
        ForEach-Object { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $_.Name -ErrorAction SilentlyContinue }
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'EVKey' -Value "`"$evkPath`""
    Write-Ok "EVKey tự chạy cho mọi user: $evkPath"
}
# ---------- 4. Thiết lập Word -> Default profile ----------
Write-Host "`n=== 4. THIET LAP WORD ===" -ForegroundColor Cyan
if (Get-Process WINWORD -ErrorAction SilentlyContinue) {
    Write-Warn "Word đang mở -> đóng Word rồi chạy lại (Normal.dotm đang bị khoá)."
} else {
    $def = 'C:\Users\Default\AppData'
    # 4a. Normal.dotm: font, cỡ chữ, lề, style, khổ giấy mặc định
    $files = @(
        @{ Src = "$env:APPDATA\Microsoft\Templates\Normal.dotm";            Dst = "$def\Roaming\Microsoft\Templates" },
        # 4b. Ribbon + Quick Access Toolbar tuỳ chỉnh
        @{ Src = "$env:LOCALAPPDATA\Microsoft\Office\Word.officeUI";        Dst = "$def\Local\Microsoft\Office" }
    )
    foreach ($f in $files) {
        if (Test-Path $f.Src) {
            New-Item -ItemType Directory -Path $f.Dst -Force | Out-Null
            Copy-Item $f.Src -Destination $f.Dst -Force
            Write-Ok "$(Split-Path $f.Src -Leaf) -> $($f.Dst)"
        } else { Write-Warn "Không có $($f.Src) (chưa tuỳ chỉnh thì bỏ qua)" }
    }
    # 4c. File > Options (đơn vị cm, định dạng lưu, autosave...) trong registry HKCU
    $key = 'HKCU\Software\Microsoft\Office\16.0\Word\Options'
    $exp = Join-Path $work 'WordOptions_export.reg'
    $imp = Join-Path $work 'WordOptions_default.reg'
    & reg.exe export $key $exp /y 2>$null | Out-Null
    if (-not (Test-Path $exp)) {
        Write-Warn "Không đọc được $key (Office không phải bản 2016/2019/2021/365?)"
    } else {
        (Get-Content $exp) -replace '^\[HKEY_CURRENT_USER', '[HKEY_USERS\FixCloneDefault' |
            Set-Content $imp -Encoding Unicode
        & reg.exe load 'HKU\FixCloneDefault' 'C:\Users\Default\NTUSER.DAT' | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn "Không load được NTUSER.DAT của Default profile" }
        else {
            & reg.exe import $imp 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "Đã chép Word Options vào Default profile" }
            else { Write-Warn "reg import lỗi, ExitCode $LASTEXITCODE" }
            [gc]::Collect(); Start-Sleep -Seconds 1
            & reg.exe unload 'HKU\FixCloneDefault' | Out-Null
        }
    }
}
# ---------- 5. Menu chuột phải kiểu Windows 10 ----------
Write-Host "`n=== 5. MENU CHUOT PHAI KIEU WIN 10 ===" -ForegroundColor Cyan
$clsid = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
# User hiện tại
& reg.exe add "HKCU\$clsid" /ve /f 2>&1 | Out-Null   # /ve không kèm /d = giá trị Default rỗng
if ($LASTEXITCODE -eq 0) { Write-Ok "User hiện tại" } else { Write-Warn "Không ghi được HKCU" }
# Default profile -> mọi user mới trên máy clone
& reg.exe load 'HKU\FixCloneDefault' 'C:\Users\Default\NTUSER.DAT' | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warn "Không load được NTUSER.DAT của Default profile" }
else {
    & reg.exe add "HKU\FixCloneDefault\$clsid" /ve /f 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Default profile (user mới)" } else { Write-Warn "Không ghi được Default profile" }
    [gc]::Collect(); Start-Sleep -Seconds 1
    & reg.exe unload 'HKU\FixCloneDefault' | Out-Null
}
# ---------- 6. Dấu số cho user hiện tại và Default profile ----------
& (Join-Path $PSScriptRoot 'Fix-DinhDang.ps1') -AllNewUsers
