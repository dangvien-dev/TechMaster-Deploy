<#
.SYNOPSIS
    Tải / cài Microsoft Office bằng Office Deployment Tool (ODT) của Microsoft.

.DESCRIPTION
    - Tự tải setup.exe (ODT) từ officecdn.microsoft.com, KIỂM TRA CHỮ KÝ SỐ Microsoft trước khi dùng.
    - Sinh configuration.xml theo lựa chọn (sản phẩm, ngôn ngữ, 32/64-bit, app bỏ qua, key).
    - 3 chế độ:
        Download : tải bộ cài về kho (KhoOffice\...) để cài offline nhiều máy
        Install  : cài trực tiếp từ internet
        InstallKho : cài từ kho đã tải (không cần mạng)
    - Chỉ tải / cài. Kích hoạt cần key hợp lệ (dùng bộ KichHoat).

.EXAMPLE
    .\Office-ODT.ps1 -Mode Download -Product HomeBusiness2024Retail -Languages vi-vn,en-us
    .\Office-ODT.ps1 -Mode InstallKho -Product HomeBusiness2024Retail -Languages vi-vn,en-us
#>
param(
    [ValidateSet('Download', 'Install', 'InstallKho')][string]$Mode = 'Install',
    [string]$Product = 'HomeBusiness2024Retail',
    [string[]]$Languages = @('vi-vn', 'en-us'),
    [ValidateSet('64', '32')][string]$Arch = '64',
    [string[]]$Exclude = @('Groove', 'Lync', 'OneDrive', 'Teams', 'Bing'),
    [string]$PidKey = '',
    [switch]$RemoveMSI,
    [string]$KhoRoot = '',
    [string]$ProgressPath = ''
)
$ErrorActionPreference = 'Stop'

# Lucida Console and raster fonts can omit Vietnamese glyphs in the classic console.
if (-not [Console]::IsOutputRedirected) {
    try {
        if (-not ('TechMaster.OfficeConsole' -as [type])) {
            Add-Type -Namespace TechMaster -Name OfficeConsole -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
private struct ConsoleFont
{
    public uint Size;
    public uint Index;
    public short Width;
    public short Height;
    public uint Family;
    public uint Weight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string FaceName;
}

[DllImport("kernel32.dll")]
private static extern IntPtr GetStdHandle(int standardHandle);

[DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
private static extern bool GetCurrentConsoleFontEx(IntPtr output, bool maximum, ref ConsoleFont font);

[DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
private static extern bool SetCurrentConsoleFontEx(IntPtr output, bool maximum, ref ConsoleFont font);

public static void UseVietnameseFont()
{
    var output = GetStdHandle(-11);
    var font = new ConsoleFont { Size = (uint)Marshal.SizeOf(typeof(ConsoleFont)) };
    if (!GetCurrentConsoleFontEx(output, false, ref font))
        return;

    const uint TrueType = 0x04;
    if ((font.Family & TrueType) != 0 && font.FaceName != "Lucida Console")
        return;

    font.Index = 0;
    font.Width = 0;
    font.Family = 0x36; // Modern fixed-pitch TrueType font.
    font.FaceName = "Consolas";
    SetCurrentConsoleFontEx(output, false, ref font);
}
'@ -ErrorAction Stop
        }
        [TechMaster.OfficeConsole]::UseVietnameseFont()
    } catch {
        Write-Verbose "Không thể đổi font console: $($_.Exception.Message)"
    }
}

if ($ProgressPath -and [Console]::IsOutputRedirected) {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
}

function Write-OfficeProgress([string]$message) {
    if (-not $ProgressPath) { return }
    try { [IO.File]::WriteAllText($ProgressPath, $message) }
    catch [IO.IOException] { Write-Verbose $_.Exception.Message }
}

function Write-Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [LỖI] $t" -ForegroundColor Red }

# ---------- Danh mục sản phẩm (Product ID -> kênh cập nhật) ----------
# Nguồn: learn.microsoft.com "Product IDs supported by the Office Deployment Tool" và "Deploy Office LTSC 2024"
$Catalog = [ordered]@{
    'O365ProPlusRetail'      = @{ Name = 'Microsoft 365 Apps for enterprise';        Channel = 'Current' }
    'O365BusinessRetail'     = @{ Name = 'Microsoft 365 Apps for business';          Channel = 'Current' }
    'HomeBusiness2024Retail' = @{ Name = 'Office Home & Business 2024 (Retail)';     Channel = 'Current' }
    'HomeBusiness2021Retail' = @{ Name = 'Office Home & Business 2021 (Retail)';     Channel = 'Current' }
    'ProPlus2024Volume'      = @{ Name = 'Office LTSC Professional Plus 2024 (Volume)'; Channel = 'PerpetualVL2024' }
    'Standard2024Volume'     = @{ Name = 'Office LTSC Standard 2024 (Volume)';       Channel = 'PerpetualVL2024' }
    'ProPlus2021Volume'      = @{ Name = 'Office LTSC Professional Plus 2021 (Volume)'; Channel = 'PerpetualVL2021' }
}
$ValidApps = 'Access', 'Excel', 'Groove', 'Lync', 'OneDrive', 'OneNote', 'Outlook', 'OutlookForWindows', 'PowerPoint', 'Publisher', 'Teams', 'Word', 'Bing'

if (-not $Catalog.Contains($Product)) { Write-Err "Sản phẩm không hỗ trợ: $Product"; exit 1 }
# Gọi qua -File thì mảng đến dưới dạng chuỗi "a,b" -> tách lại
$Languages = @($Languages -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -match '^[a-z]{2}-[a-z]{2}$' })
if (-not $Languages) { Write-Err "Chưa chọn ngôn ngữ hợp lệ (vd vi-vn, en-us)"; exit 1 }
$Exclude = @($Exclude -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $ValidApps -contains $_ })   # 'none' = không bỏ app nào
$PidKey = $PidKey.Trim().ToUpper()
if ($PidKey -and $PidKey -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') { Write-Err "Key sai định dạng XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"; exit 1 }

# ---------- Quyền Admin (Install cần) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if ($Mode -ne 'Download' -and -not $isAdmin) { Write-Err "Cài Office cần quyền Administrator."; exit 2 }

$here = $PSScriptRoot
if (-not $KhoRoot) { $KhoRoot = Join-Path (Split-Path $here) 'KhoOffice' }
$odtDir = Join-Path $here 'ODT'
$setup  = Join-Path $odtDir 'setup.exe'
$langTag = ($Languages -join '_')
$khoDir = Join-Path $KhoRoot "$Product`_x$Arch`_$langTag"

Write-Step "OFFICE DEPLOYMENT TOOL - $Mode"
Write-Host "  Sản phẩm : $($Catalog[$Product].Name)  [$Product]"
Write-Host "  Kênh     : $($Catalog[$Product].Channel)"
Write-Host "  Ngôn ngữ : $($Languages -join ', ')     Kiến trúc: $Arch-bit"
Write-Host "  Bỏ qua   : $(if ($Exclude) { $Exclude -join ', ' } else { '(không)' })"
if ($Mode -ne 'Install') { Write-Host "  Kho      : $khoDir" }

# ---------- 1. setup.exe (ODT) + kiểm tra chữ ký ----------
Write-Step "1. OFFICE DEPLOYMENT TOOL (setup.exe)"
if (-not (Test-Path $setup)) {
    New-Item -ItemType Directory -Path $odtDir -Force | Out-Null
    Write-OfficeProgress 'Đang tải Office Deployment Tool…'
    Write-Host "  Đang tải setup.exe từ officecdn.microsoft.com ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing
    } catch { Write-Err "Không tải được setup.exe: $($_.Exception.Message)"; exit 1 }
}
Write-OfficeProgress 'Đang kiểm tra chữ ký của bộ cài…'
$sig = Get-AuthenticodeSignature $setup
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    Write-Err "setup.exe KHÔNG có chữ ký hợp lệ của Microsoft ($($sig.Status)). Đã xoá, không chạy."
    Remove-Item $setup -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Ok ("Chữ ký Microsoft hợp lệ, phiên bản {0}" -f (Get-Item $setup).VersionInfo.FileVersion)

# ---------- 2. Kiểm tra Office đang cài ----------
$c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
if ($c2r -and $Mode -ne 'Download') {
    Write-Warn "Máy đang có Office Click-to-Run: $($c2r.ProductReleaseIds) ($($c2r.Platform)), bản $($c2r.VersionToReport)"
    $want = if ($Arch -eq '64') { 'x64' } else { 'x86' }
    if ($c2r.Platform -and $c2r.Platform -ne $want) {
        Write-Err "Office đang cài là $($c2r.Platform), không cài lẫn 32/64-bit được. Gỡ bản cũ trước hoặc chọn đúng kiến trúc."
        exit 1
    }
}

# ---------- 3. Sinh configuration.xml ----------
Write-Step "2. TẠO configuration.xml"
$src = ''
if ($Mode -ne 'Install') {
    if ($Mode -eq 'InstallKho' -and -not (Test-Path (Join-Path $khoDir 'Office'))) {
        Write-Err "Chưa có kho cho cấu hình này: $khoDir  -> chạy chế độ Download trước."
        exit 1
    }
    New-Item -ItemType Directory -Path $khoDir -Force | Out-Null
    $escapedSource = [Security.SecurityElement]::Escape($khoDir)
    $src = " SourcePath=`"$escapedSource`""
}
$pidAttr = ''
if ($PidKey) { $pidAttr = " PIDKEY=`"$PidKey`"" }
$langXml = ($Languages | ForEach-Object { "      <Language ID=`"$_`" />" }) -join "`r`n"
$exclXml = ($Exclude   | ForEach-Object { "      <ExcludeApp ID=`"$_`" />" }) -join "`r`n"
$removeMsiXml = ''
$autoAct = ''
if ($PidKey) { $autoAct = '  <Property Name="AUTOACTIVATE" Value="1" />' }
if ($RemoveMSI -and $Mode -ne 'Download') { $removeMsiXml = '  <RemoveMSI />' }

$displayLevel = if ($ProgressPath) { 'None' } else { 'Full' }
$xml = @"
<Configuration>
  <Add OfficeClientEdition="$Arch" Channel="$($Catalog[$Product].Channel)"$src>
    <Product ID="$Product"$pidAttr>
$langXml
$exclXml
    </Product>
  </Add>
$removeMsiXml
$autoAct
  <Updates Enabled="TRUE" />
  <Display Level="$displayLevel" AcceptEULA="TRUE" />
</Configuration>
"@
$cfgFile = Join-Path $odtDir ("config_{0}_{1:yyyyMMdd_HHmmss}_{2}.xml" -f $Mode, (Get-Date), $PID)
try {
    [IO.File]::WriteAllText($cfgFile, $xml, (New-Object Text.UTF8Encoding $false))
    Write-Host ($xml -replace 'PIDKEY="[^"]+"', 'PIDKEY="*****"') -ForegroundColor DarkGray
    Write-Ok "Đã lưu: $cfgFile"

    # ---------- 4. Chạy ODT ----------
    if ($Mode -eq 'Download') { $odtArgs = "/download `"$cfgFile`""; $what = 'TẢI BỘ CÀI VỀ KHO' }
    else                      { $odtArgs = "/configure `"$cfgFile`""; $what = 'CÀI OFFICE' }
    Write-Step "3. $what"
    Write-Host "  Lệnh: `"$setup`" $odtArgs"
    if ($Mode -eq 'Download') { Write-Host "  Bộ cài khoảng 3-5 GB tuỳ số ngôn ngữ. Tiến độ (dung lượng đã tải) cập nhật mỗi 5 giây." }

    if ($Mode -eq 'Download') { Write-OfficeProgress 'Đang tải bộ cài Office…' }
    else { Write-OfficeProgress 'Đang cài Office…' }

    if ($ProgressPath) {
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $setup
        $start.Arguments = $odtArgs
        $start.WorkingDirectory = $odtDir
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($start)
    } else {
        $p = Start-Process -FilePath $setup -ArgumentList $odtArgs -WorkingDirectory $odtDir -PassThru
    }
    try { $null = $p.Handle } catch [InvalidOperationException] {}
    $t0 = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 5
        $el = [int]((Get-Date) - $t0).TotalSeconds
        if ($Mode -eq 'Download') {
            $mb = [math]::Round(((Get-ChildItem $khoDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB)
            Write-OfficeProgress ("Đang tải bộ cài Office · {0:N0} MB trong kho" -f $mb)
            Write-Host ("`r  Đã tải: {0,6} MB   ({1:mm\:ss})" -f $mb, [TimeSpan]::FromSeconds($el)) -NoNewline
        } else {
            if (-not $ProgressPath) { Write-Host ("`r  Đang cài... ({0:mm\:ss}) - xem cửa sổ cài đặt của Office" -f [TimeSpan]::FromSeconds($el)) -NoNewline }
        }
    }
    Write-Host ""
} finally {
    if ($PidKey -and (Test-Path -LiteralPath $cfgFile)) {
        try { Remove-Item -LiteralPath $cfgFile -Force -ErrorAction Stop }
        catch { Write-Warn "Không xoá được tệp cấu hình chứa key: $cfgFile" }
    }
}
if ($null -eq $p.ExitCode) {
    Write-Err "Không xác nhận được mã thoát của ODT. Kiểm tra nhật ký của Office trong %TEMP%."
    exit 1
}
if ($p.ExitCode -eq 0) {
    Write-Ok "$what xong (ExitCode 0)"
    if ($Mode -eq 'Download') { Write-Host "  Chép cả thư mục KhoOffice + Office\ ra USB/NAS để cài offline cho máy khác (chế độ InstallKho)." }
    elseif (-not $PidKey)     { Write-Host "  Office chưa có key -> nhập key trong Word (File > Account) hoặc dùng bộ KichHoat." }
} else {
    Write-Err "ODT trả về ExitCode $($p.ExitCode). Log của ODT: %TEMP% (file *.log mới nhất)."
    exit $p.ExitCode
}
