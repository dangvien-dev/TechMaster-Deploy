# HANDOFF — TechMaster Deploy

Cập nhật: 28/11/2026 · Phiên bản trên `main`: **2.2.26.0** · Đọc kèm `README.md` (tính năng), `RELEASING.md` (updater, ZIP), `PROGRESS.md` (nhật ký từng bản), `CHANGELOG.md` (hiển thị trong app).

Tệp này dành cho người / phiên làm việc tiếp theo. Nằm ngoài phạm vi tệp chương trình (`Assert-DeployPath`) nên **không** vào `update-source.json`, gói ZIP hay bản cập nhật.

## 1. Trạng thái hiện tại

- Bộ công cụ WPF cho kỹ thuật viên: cài Windows / phần mềm, kích hoạt + biên bản, tuỳ chỉnh Windows, máy in, chia sẻ LAN, clone hàng loạt (Sysprep), chẩn đoán / sửa lỗi, cập nhật.
- 2.2.26.0 đã thử trên máy thật (28/11/2026), đạt: dọn máy in (cửa sổ riêng) trên KY-THUAT; chạy TechMaster qua LAN; lệnh web trên Windows 10 cũ; tài khoản scan / share + chia sẻ thư mục + scan từ máy photocopy + kết nối không nhập lại mật khẩu; cập nhật từ bản cũ.
- Trang tải (repo `dangvien-dev/dangvien-dev.github.io`) đang công bố ZIP 2.2.26.0; `irm https://dangvien-dev.github.io/tm.txt | iex` cài bản đó.
- PR đang mở (28/11/2026, do phiên khác tạo, chưa merge):
  - dangvien-dev/TechMaster-Deploy#4 — Dọn Windows.old: xoá thư mục rỗng bằng `rd` (không `/s`), nhánh `claude/laughing-maxwell-bpzsor`.
  - dangvien-dev/TechMaster-Deploy#5 — Máy in: thêm theo IP và kết nối máy in chia sẻ không tắt bảo mật in, nhánh `claude/pensive-brown-f6hvog`.
  - **Cả hai cùng ghi 2.2.27.0.** Merge cái đầu xong, cái sau phải nhập `main`, đổi lên 2.2.28.0 (`version.txt`, mục `CHANGELOG.md` / `PROGRESS.md`) và tạo lại `update-source.json` trước khi merge.

## 2. Kiến trúc

- `TechMaster Deploy.exe` (từ `App/Launcher.cs`, `App/Launcher.manifest` = requireAdministrator) chạy `powershell.exe -STA -File App\TechMaster-Deploy.ps1`. Windows PowerShell 5.1 + WPF + .NET Framework có sẵn, không module ngoài.
- Giao diện: XAML trong `App/*Window.xml`, nạp bằng `Import-DeployWindow` (`App/Wpf.Runtime.ps1`). Việc nặng chạy runspace qua `Start-DeployWork` / `Receive-DeployWork`, cửa sổ hỏi kết quả bằng `New-DeployTimer` (DispatcherTimer). Thông báo: `Set-DeployNotice` (Info / Working / Attention / Success / Error). Xác nhận: `Confirm-Box`.
- Mẫu module: `X.Core.ps1` (logic, test được không cần UI) · `X.UI.ps1` (WPF) · `X.Native.cs` (Add-Type, **chỉ ASCII**) · `XWindow.xml` · `Test-X.ps1` (engine, mock) · `Test-XWpf.ps1` (cửa sổ thật, worker bị chặn).
- Cửa sổ chính `App/MainWindow.xml` + `App/TechMaster-Deploy.ps1`: mỗi mục menu là `ListBoxItem Tag="tabXxx"` trỏ tới `TabItem x:Name="tabXxx"`; tiêu đề nhóm dùng style `NavGroup` (không chọn được). Chuyển trang bằng `Select-DeployPage 'tabXxx'`; nút có `x:Name="go…"` + `Tag="tabXxx"` tự được gắn điều hướng. **Không** điều hướng theo số thứ tự.

| Menu | Trang (`Tag`) | Module chính |
|---|---|---|
| Tổng quan | `tabOverview` | `Overview.Core/UI.ps1`, nút chạy qua LAN / web |
| Cài Windows | `tabWindows` | `Deploy.Actions.ps1`, `Windows.Tools.ps1` |
| Phần mềm | `tabSoftware` | `Office/*`, `BasicApps.ps1`, `CustomApps.*` |
| Bản quyền & biên bản | `tabLicense` | `KichHoat/*`, `BienBan/*`, `LicenseConfirmation.UI.ps1` |
| Tuỳ chỉnh Windows | `tabCustomize` | `FixClone/Fix-DinhDang*`, `Fix-BanPhim*`, `Defaults.*` (chế độ `Apps`) |
| Máy in | `tabPrinter` | `Defaults.*` (chế độ `Printer` / `Cleanup`) |
| Mạng LAN & chia sẻ | `tabLan` | `LanAccounts.*`, `LanShare.*`, `LanConnect.*`, `NetworkRun.*`, `Network.Sync.ps1` |
| Clone hàng loạt | `tabClone` | `FixClone/*` (Sysprep, trùng lặp, UltraViewer, Master-Preflight) |
| Chẩn đoán & sửa lỗi | `tabDiagnostics` | `FixClone/DriverFix*`, `App/AV.*` |
| Cập nhật | `tabUpdate` | `Update.*`, `Update-App.ps1`, `Update-UI.ps1` |

- Cửa sổ Thiết lập mặc định (`Defaults.UI.ps1`) mở theo chế độ `Printer` / `Cleanup` / `Apps`, chỉ hiện thẻ của chế độ đó (góp ý của người dùng: gộp chung dễ nhầm).
- Dữ liệu người dùng nằm trong thư mục app (`BienBan/BienBan-Config.json`, logo, `KhoOffice/`, `FixClone/Reinstall/`, `.updates/`); nhật ký công cụ Windows ở `%LOCALAPPDATA%\TechMaster Deploy\Windows Tools`.

## 3. Quy ước bắt buộc và bẫy đã gặp

- `.ps1` có tiếng Việt phải **UTF-8 có BOM** (PowerShell 5.1). `.cs` cho `Add-Type` chỉ ASCII. `.bat` ASCII (repo dùng LF; tránh label / goto).
- Biến PowerShell **không phân biệt hoa thường**: `$grants=@()` xoá luôn tham số `$Grants` (lỗi thật ở 2.2.23). Đọc tham số vào biến khác tên trước.
- Ghép chuỗi khi gọi lệnh phải bọc ngoặc: `Confirm-Box ('a'+$x)`, không viết `Confirm-Box 'a'+$x`.
- Hàm trả `byte[]` qua pipeline bị “trải” thành `object[]`; truyền mảng byte bằng tham số.
- `Split-Path -Parent 'D:\'` ném lỗi; dùng `[IO.Path]::GetDirectoryName` và xử lý gốc ổ riêng.
- `-replace` không phân biệt hoa thường; cần chính xác thì `-creplace`.
- Test WPF: tạo `RoutedEventArgs` mới cho mỗi `RaiseEvent`.
- Bảo mật đã chốt: không bao giờ cấp Everyone / Guest; mật khẩu chỉ ở `SecureString`, không ghi log; code chạy quyền Admin không lấy từ thư mục người dùng ghi được; khoá thư mục phải **thay toàn bộ DACL** (`icacls /inheritance:r` giữ lại ACE tường minh của tài khoản khác — CI #72 đã bắt).
- Phạm vi tệp chương trình (`Assert-DeployPath` trong `App/Update.Core.ps1`): `App|Office|KichHoat|FixClone|BienBan/*.ps1|cs|ico|svg|html|bat|xml|manifest|md` (không thư mục con) + `README.md`, `PROGRESS.md`, `CHANGELOG.md`, `RELEASING.md`, `version.txt`, `TechMaster Deploy.exe`. Tệp mới ngoài phạm vi này không được updater cài.
- Mỗi bản: tăng `version.txt`, thêm mục `CHANGELOG.md` (`## x.y.z.w — dd/MM/yyyy`) và `PROGRESS.md`; sửa `App/QuickGuide.md` khi đổi thao tác (mục `##` theo đúng tên menu — `Test-Info.ps1` đối chiếu).
- Sau khi sửa **bất kỳ** tệp trong phạm vi trên: tạo lại `update-source.json` bằng `App/Build-UpdateIndex.ps1` (Windows). Không có PowerShell thì tạo lại đúng thuật toán: `git ls-files --cached --others --exclude-standard`, lọc theo phạm vi, bỏ `TechMaster Deploy.exe`, mỗi tệp `{path, mode:"100644", size, sha}` với `sha` = Git blob SHA1 của nội dung; `-Check` so theo từng đường dẫn nên định dạng JSON không quan trọng.

## 4. Kiểm thử

- Chỉ chạy được trên Windows: workflow **Windows WPF validation** (`.github/workflows/windows-smoke.yml`, `workflow_dispatch`, chọn nhánh). Gồm: cửa sổ WPF thật (`Test-Wpf.ps1` và các `Test-*Wpf.ps1`), engine (`Test-*.ps1` ở mọi thư mục), `Build-UpdateIndex -Check`, rồi build launcher, `TechMaster Update.exe` và ZIP (artifact `TechMaster-Deploy-WPF`).
- Test mới phải thêm vào workflow. Mock bằng cách định nghĩa hàm trùng tên cmdlet trong scope test (ví dụ `Get-SmbShare`, `New-LocalUser`); test chạy với quyền Admin của runner nên một số phần dùng NTFS / icacls thật trên thư mục tạm.
- Không có gì chạy thật Sysprep, kích hoạt, cài Office hay gỡ máy in trong CI; các phần đó cần máy thật (máy thử của người dùng: KY-THUAT).

## 5. Merge, phát hành, đăng trang tải

1. Làm trên nhánh `claude/…`, mở PR vào `main`, chạy workflow trên nhánh, CI xanh mới merge. Merge kiểu **rebase** (lịch sử `main` thẳng). Sau đó khởi động lại nhánh từ `main` mới.
2. App tự cập nhật từ `main` (Git smart HTTP + raw, đối chiếu `update-source.json`); cùng số phiên bản nhưng commit mới vẫn được nhận.
3. Gói ZIP để đăng: chạy workflow trên **`main`** (để `update-package.json` trong ZIP mang commit của `main`, `dirty=false`), tải artifact `TechMaster-Deploy-WPF`.
4. Repo `dangvien-dev.github.io`: thêm `downloads/TechMaster-Deploy-vX.zip` + `.sha256`, sửa `downloads/latest.json` (version, zip, sha256), `assets/tools.js` (version, updated, download, features, changelog), `downloads/techmaster-deploy.html` (phiên bản, link, SHA256). `node .github/scripts/check-data.js` phải hợp lệ; PR chạy workflow **Check web install** (cài thật bằng `tm.txt` trên Windows). Merge → workflow Deploy Pages.
5. `TechMaster-Update.exe` chỉ thay khi đầu vào của `App/Build-UpgradeHelper.ps1` đổi (`Update-App.ps1`, `Update.Core.ps1`, `Update.Engine.ps1`, `UpdaterWindow.xml`, `UpgradeHelper.cs`, `Wpf.Runtime.ps1`, `ConfirmWindow.xml`, `DesktopIdentity.cs`, `Launcher.manifest`, `TechMaster.ico`). Từ 2.2.19 tới 2.2.26 không đổi.
6. Phiên cloud: artifact tải từ `productionresultssaNN.blob.core.windows.net`, số `NN` đổi theo lần build; môi trường “TechMaster Deploy + Pages” phải cho phép đúng host đó.

## 6. Chạy TechMaster trên máy khác (2.2.24 → 2.2.26)

- Danh sách tệp: bản cài có `update-package.json` (SHA256 từng tệp, kể cả exe; bỏ qua mục `preserve`), checkout có `update-source.json` (size + blob hash). `Network.Sync.ps1` đọc `update-package.json` trước.
- LAN: `NetworkRun.Core.ps1` chia sẻ thư mục app thành `TechMaster$` chỉ đọc cho một tài khoản (đang dùng hoặc `share`). Máy kia chạy `App\Chay-Tu-Mang.bat` → `Network.Launch.ps1`: chép tệp khác vào thư mục tạm (không quyền Admin), rồi lệnh nhúng chạy quyền Admin khoá `C:\TechMaster-Deploy`, kiểm tra lại từng tệp và mở app. Bản có sẵn chỉ mở nguyên trạng khi thư mục đã khoá.
- Web: `tm.txt` (ASCII) ở repo trang tải: xin quyền Admin, đọc `downloads/latest.json`, tải ZIP vào bộ nhớ, kiểm tra SHA256, khoá thư mục, ghi tệp, mở app.

## 7. Việc còn mở / ý tưởng

- Chưa ký số exe → SmartScreen / Smart App Control có thể chặn (hướng dẫn trên trang tải).
- Tài khoản `print` mới chỉ được tạo; kết nối máy in chia sẻ / thêm theo IP đang làm ở PR #5 (chưa merge).
- Chạy qua LAN chỉ chép tệp chương trình; `KhoOffice`, `Reinstall` không có trên máy kia.
- Mỗi bản mới phải tự đăng lại lên trang tải (bước 5.3–5.4) thì lệnh web mới cài bản đó.
- Workflow còn cảnh báo Node.js 20 của `actions/checkout@v4`, `actions/upload-artifact@v4` (chưa ảnh hưởng).

## 8. Làm việc với người dùng

- Trả lời bằng tiếng Việt; thuật ngữ kỹ thuật, tên tệp, lệnh, Git giữ tiếng Anh.
- Người dùng thử trên máy thật và gửi ảnh chụp; ghi kết quả vào `PROGRESS.md`.
- Chỉ merge / đăng trang khi người dùng yêu cầu.
