# FixClone – Chuẩn bị máy gốc, Sysprep và xử lý máy sau khi clone

Bộ công cụ triển khai Windows hàng loạt bằng clone ổ (disk to disk):

1. **Máy gốc:** chuẩn bị thiết lập dùng chung, kiểm tra lỗi, chạy `sysprep` (máy tự tắt).
2. **Clone** ổ sang các máy.
3. **Máy clone:** bỏ qua OOBE, tự tạo user, tự đổi tên máy, reset ID trùng, cài lại phần mềm.

> Clone **không nhân bản bản quyền**. Mỗi máy cần một license Windows/Office riêng
> (xem mục [Bản quyền](#bản-quyền)).

---

## Danh sách file

| File | Chạy ở | Chức năng |
|---|---|---|
| `Run-Sysprep.bat` | Máy gốc | **File chính.** Gọi Prepare-Master → kiểm tra lỗi → sysprep → tắt máy |
| `Prepare-Master.ps1` | Máy gốc | Chuyển thiết lập của user thành thiết lập toàn máy (xem bên dưới) |
| `Fix-SysprepErrors.bat` / `.ps1` | Máy gốc | Kiểm tra và sửa lỗi *"Sysprep was not able to validate…"* |
| `unattend.xml` | Sysprep | Bỏ qua OOBE, tạo user `admin`, tự chạy Fix-CloneDuplicate lần đăng nhập đầu |
| `Fix-CloneDuplicate.bat` / `.ps1` | Máy clone | Đổi tên máy, reset ID trùng, cài lại phần mềm (tự chạy) |
| `New-Unattend.ps1` | Máy gốc | Tạo cấu hình Sysprep theo vùng / ngôn ngữ hiện tại của máy gốc |
| `Fix-DinhDang.bat` / `.ps1` | Máy clone | Ngày dd/MM/yyyy, dấu thập phân `,` và dấu hàng nghìn `.` |
| `Fix-BanPhim.bat` / `.ps1` | Máy clone | Tuỳ chọn chỉ dùng bàn phím US với EVKey, có sao lưu và khôi phục |
| `Reinstall\` | Máy clone | Bỏ file cài `.exe` / `.msi` vào đây để tự cài lại sau khi clone |

Giữ nguyên cả thư mục TechMaster-Deploy, gồm App và Office. Run-Sysprep tự chép thành phần cần thiết vào C:\FixClone cho lần đăng nhập đầu.

---

## Quy trình

### Bước 1 – Máy gốc

1. Cài Windows theo ngôn ngữ mong muốn, driver, phần mềm. Đăng nhập user sẽ làm mẫu và thiết lập:
   Chrome mặc định, Word (font, lề, style…), EVKey.
2. **Đóng Word**, **rút mạng**.
3. Chạy `Run-Sysprep.bat`:
   - Copy script vào `C:\FixClone`, tạo `unattend.xml` trong thư mục Sysprep theo vùng / ngôn ngữ của máy gốc
   - Chạy `Prepare-Master.ps1` → xem kết quả, sửa các dòng `[!]` nếu có
   - Chạy `Fix-SysprepErrors.ps1 -PreCheck` → còn vấn đề thì **dừng**, không chạy sysprep
   - Kiểm tra lựa chọn dọn key thử / chuẩn bị UltraViewer; đóng các ứng dụng Office
   - Bấm **Chuẩn bị và tắt máy** → dọn key tạm đã nhận diện, giữ dịch vụ UltraViewer tắt → Sysprep → **máy tự tắt**
4. **Không bật lại máy gốc.** Tháo ổ hoặc boot USB để clone ngay.

### Bước 2 – Clone ổ sang các máy

### Bước 3 – Máy clone (tự động lần bật đầu)

1. Bỏ qua OOBE (giữ vùng / ngôn ngữ máy gốc, bàn phím US, múi giờ UTC+7)
2. Tạo user `admin` (mật khẩu trống), tự đăng nhập 1 lần
3. Tắt AutoLogon, xoá `unattend.xml`
4. Chạy `Fix-CloneDuplicate.ps1 -Auto` rồi restart

---

## Prepare-Master.ps1 – thiết lập dùng chung

| # | Nội dung | Cách làm |
|---|---|---|
| 1 | Ứng dụng mặc định (Chrome) | `DISM /Export-` + `/Import-DefaultAppAssociations` |
| 2 | Shortcut Word, Excel ra Desktop | Copy vào `C:\Users\Public\Desktop` |
| 3 | EVKey tự chạy cho mọi user | `HKLM\...\Run`; nằm trong thư mục user thì chuyển sang `C:\Program Files\EVKey` |
| 4 | Thiết lập Word | `Normal.dotm`, `Word.officeUI`, Word Options → Default profile |
| 5 | Menu chuột phải kiểu Windows 10 | CLSID `{86ca1aa0-…}` cho user hiện tại + Default profile |
| 6 | Ngày / dấu số | Ngày dd/MM/yyyy, thập phân `,`, hàng nghìn `.`; giữ vùng, ngôn ngữ và bàn phím |

## Fix-CloneDuplicate.ps1 – xử lý trên máy clone

| # | Nội dung |
|---|---|
| 1 | **Đổi tên máy:** `PC-` + 6 ký tự cuối Serial BIOS. Serial rác (*System Serial Number*, *Default string*…) thì dùng **6 ký tự cuối MAC**. Tên đã có máy khác dùng trong LAN thì thêm `-2`, `-3`… |
| 2 | Tạo mới `MachineGuid` |
| 3 | Reset Windows Update Client ID (`SusClientId`) |
| 4 | Reset ID AnyDesk |
| 5 | Reset ID TeamViewer (vẫn trùng thì cài lại TeamViewer) |
| 6 | IP tĩnh → DHCP (chỉ khi có `-ResetIP`) |
| 7 | KMS rearm (chỉ khi có `-RearmKMS` và máy dùng KMS) |
| 8 | Cài lại phần mềm trong `Reinstall\` |
| 9 | Máy ASUS: bật lại service ASUS (quạt, cert, update) |
| 10 | Ngày ngắn và dấu số (gọi `Fix-DinhDang.ps1`) |
| 11 | Dọn key tạm và hoàn tất ID UltraViewer theo lựa chọn đã lưu trước tạo ảnh |
| – | **Không** đổi Machine SID (sysprep đã làm) |

Log lưu tại `C:\FixClone\Logs\<tên máy>_<thời gian>.log`.

### Thư mục `Reinstall\`

- `.exe` chạy với `/S` (WinRAR, NSIS…)
- Cần tham số khác thì tạo file cùng tên đuôi `.args`, ví dụ `setup.exe` + `setup.args` chứa `/VERYSILENT /NORESTART`
- `.msi` chạy `msiexec /i … /qn /norestart`

---

## Fix-SysprepErrors – lỗi sysprep thường gặp

| Lỗi trong `setupact.log` | Script xử lý |
|---|---|
| `SYSPRP Package … was installed for a user, but not provisioned for all users` | Gỡ package (đã gặp: `ArmouryCrate`, `WinRAR.ShellExtension`, `Microsoft.Edge.GameAssist`, `Microsoft.WidgetsPlatformRuntime`) |
| BitLocker / Device Encryption đang bật | Hỏi tắt (`manage-bde -off C:`) |
| Armoury Crate tự cài lại | Máy ASUS: tạm tắt service ASUS |
| `sysprep.exe` còn treo | Đóng tiến trình |

Mỗi package được gỡ với **timeout 3 phút**. Quá thời gian thì restart máy rồi chạy lại.

---

## Fix-DinhDang – chỉnh định dạng trên máy đã clone

Đăng nhập đúng user cần sửa và mở trực tiếp `Fix-DinhDang.bat`. Khi mở bằng thông tin đăng nhập của tài khoản khác, script sẽ ghi định dạng cho tài khoản đó.

| Mục | Giá trị |
|---|---|
| Decimal symbol (thập phân) | `,` |
| Digit grouping symbol (hàng nghìn) | `.` |
| Short date (ngày ngắn) | `dd/MM/yyyy` |
| Date separator | `/` |

Giữ nguyên ngày dài, giờ, tiền tệ, list separator, đơn vị đo, vùng, ngôn ngữ và bàn phím. Không cần chọn Việt Nam trong Settings của Windows.

Máy clone tự áp dụng định dạng cho `admin` và cập nhật Default profile cho tài khoản được tạo sau đó. Với tài khoản đã có hồ sơ, mở script trong phiên của tài khoản đó. Để cập nhật Default profile bằng tay, mở PowerShell bằng quyền Administrator trong thư mục `FixClone` và chạy:
`powershell -ExecutionPolicy Bypass -File Fix-DinhDang.ps1 -AllNewUsers`

---

## Lưu ý

- User `admin` có **mật khẩu trống**: không truy cập được qua mạng (file share, Remote Desktop).
- Gỡ `WinRAR.ShellExtension` chỉ mất WinRAR ở menu chuột phải kiểu Windows 11. Đã dùng menu kiểu Windows 10 thì không ảnh hưởng.
- Gỡ `WidgetsPlatformRuntime` có thể làm Widgets tạm không hiện, Store sẽ tự cài lại.

## Bản quyền

- **Windows:** mỗi máy cần 1 license riêng (OEM có sẵn trong BIOS, OEM System Builder, hoặc Retail).
  Máy ráp không có key trong BIOS. Clone cùng một key sang nhiều máy sẽ báo `0xC004C008`.
- **Volume License (MAK)** cho Windows desktop chỉ là bản nâng cấp, mỗi máy vẫn cần license gốc.
- Kích hoạt từng máy: dùng bộ công cụ **Kich-Hoat** (`Kich-Hoat-Windows.bat`, `Kich-Hoat-Office.bat`).

## Bàn phím và định dạng số

`Fix-DinhDang.ps1` chỉ ghi `sDecimal`, `sThousand`, `sShortDate` và `sDate`, không gọi Set-Culture hoặc thay LocaleName, không cài hay đổi bàn phím. Chế độ AllNewUsers cũng chỉ ghi bốn giá trị này vào hồ sơ mặc định.

Khi dùng EVKey, mở **Tuỳ chỉnh Windows → Bàn phím / EVKey → Chỉ dùng US** để chỉ giữ kiểu nhập US trong các ngôn ngữ hiện có. Công cụ hiển thị user sẽ thay đổi, hỏi xác nhận, lưu sao lưu rồi đọc lại để kiểm tra. Không gỡ gói ngôn ngữ, không đổi thứ tự ngôn ngữ hiển thị hoặc tắt EVKey. Nếu cần, bấm **Khôi phục**. Đăng xuất / đăng nhập lại nếu Windows còn hiện danh sách cũ.

Chạy dưới đúng user khách hàng; nếu app được nâng quyền bằng tài khoản khác, mở `Fix-BanPhim.bat` trực tiếp tại user khách hàng. Công cụ từ chối ghi khi tài khoản đang chạy không khớp desktop đăng nhập. Sao lưu nằm trong Local AppData của user đó, không đi kèm bộ cài.

Windows + Shift + S: khi hộp chọn hiện **Screen Snipping** và **Snipping Tool**, chọn **Screen Snipping** (dòng trên) rồi **Always**. Nếu đã chọn app khác, vào Ứng dụng mặc định, tìm giao thức `ms-screenclip` và đổi lại. Cửa sổ kiểm tra trước Sysprep có nút mở lựa chọn / Settings, nhắc kiểm tra và xuất ProgId đã chọn sang `DefaultApps.xml` cho user mới bằng DISM. Không chép hash UserChoice hoặc gỡ Snipping Tool. Cần kiểm tra lại trên máy clone thực tế vì Windows quản lý đăng ký ứng dụng theo từng user.

Trước Sysprep, cửa sổ này cũng kiểm tra shortcut Word / Excel ở Desktop cá nhân và Public Desktop theo đích thực tế. Nút **Sao lưu và dọn icon trùng** giữ một icon dùng chung, sao lưu rồi dọn các icon cùng đích; giữ shortcut có tham số riêng, tài liệu, Normal.dotm và Word Options. Chế độ chuẩn bị không tạo thêm icon Public khi nó sẽ trùng icon cá nhân chưa được dọn. Máy đã clone có thể mở lại từ **Sau khi clone → Kiểm tra Desktop và phím chụp**.

## UltraViewer và Office trước khi tạo ảnh

Bản 6.6.133 đã được thử trên hai máy clone: UID / PreferID trùng dù MAC, tên máy và MachineGuid khác. Người dùng xác nhận reset đúng hai trường này tạo ID mới, kết nối được và giữ ổn sau khởi động lại.

Cửa sổ chuẩn bị Sysprep có hai tuỳ chọn mặc định bật:

- **Office:** lưu và kiểm tra Normal.dotm, Word.officeUI, Word Options vào Default profile trước. Sau xác nhận cuối, chỉ dọn key có tên Office 2021/2024 Grace / Trial chưa kích hoạt. Giữ Retail kể cả chưa kích hoạt, Visio / Project, license đã kích hoạt và trường hợp không chắc chắn. Không gỡ Office hoặc xoá thiết lập ứng dụng. Nút **Xem / chọn key Office** cho phép chủ động chọn thêm; mặc định không tích key nào trong bảng.
- **UltraViewer:** sao lưu UID / PreferID và trạng thái dịch vụ, dừng rồi để dịch vụ Disabled trên ảnh gốc. Không khởi động UltraViewer hoặc bật lại máy gốc sau khi chuẩn bị; nếu dịch vụ chạy lại, ảnh có thể mang ID mới được cấp trên máy gốc. Khi Sysprep lỗi, công cụ khôi phục hai trường và trạng thái dịch vụ từ sao lưu.

Lần đăng nhập đầu sau clone kiểm tra lại key tạm, bỏ định danh mang từ ảnh rồi khôi phục kiểu khởi động dịch vụ. Nếu UltraViewer chưa cấp ID, kết quả là **đang chờ**, không báo thành công. Mở UltraViewer, đợi kết nối rồi vào **Reset ID UltraViewer → Kiểm tra ID mới**; thao tác kiểm tra không xoá lại ID. Marker hoàn tất ngăn reset lại mỗi lần chạy công cụ / khởi động. Muốn tạo ảnh mới từ máy đã clone, chạy lại toàn bộ bước chuẩn bị Sysprep.

Máy clone cũ chưa qua bước chuẩn bị mới sẽ không tự reset UltraViewer hoặc tự xoá key. Dùng **Clone hàng loạt → Sau khi clone → Reset ID UltraViewer → Sao lưu và reset** trên từng máy; thao tác ngắt phiên UltraViewer nên phải chạy tại máy hoặc qua remote khác. Chỉ hỗ trợ tự động bản 6.6.133; giữ toàn bộ LastHR_*, MAC và MachineGuid trong thao tác UltraViewer. Công cụ xử lý trùng lặp Windows riêng vẫn có lựa chọn đổi MachineGuid như trước.

Sao lưu UltraViewer ở `%ProgramData%\TechMaster Deploy\UltraViewer Backups`, chỉ Administrator / SYSTEM đọc. Có nút chọn identity.json để khôi phục; từ chối khôi phục định danh của máy gốc lên phần cứng máy clone khác. Marker ở `C:\FixClone\UltraViewer-Clone.json`, lựa chọn ở `C:\FixClone\CloneOptions.json`. Giữ các tệp này để kiểm tra / hoàn tác. Công cụ chẩn đoán chỉ đọc và vẫn dùng được.
