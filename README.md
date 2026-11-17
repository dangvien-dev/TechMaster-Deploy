# TechMaster Deploy

Bộ công cụ triển khai Windows và Office.

| Tab | Công cụ | Thư mục |
|---|---|---|
| **Máy gốc (Sysprep)** | Kiểm tra / sửa lỗi Sysprep, chuẩn bị máy gốc và chạy Sysprep, thư mục `Reinstall` | `FixClone\` |
| **Sau khi clone** | Xử lý trùng lặp (tên máy, MachineGuid, AnyDesk, TeamViewer…), chỉnh dấu số, bàn phím US cho EVKey | `FixClone\` |
| **Kích hoạt bản quyền** | Kích hoạt Windows / Office (online → portal, QR, nhận Confirmation ID qua LAN), chạy TEST | `KichHoat\` |
| **Biên bản bản quyền** | Nhập thông tin đơn vị, khách hàng, số hóa đơn, chọn logo → xuất biên bản HTML (in / lưu PDF) | `BienBan\` |
| **Tải / cài Office** | Office Deployment Tool: tải bộ cài về kho (cài offline nhiều máy), cài từ kho, cài trực tiếp | `Office\`, kho ở `KhoOffice\` |
| **Cài Windows** | Mở trang tải của Microsoft và chạy Windows Setup từ ISO đã tải | ISO do người dùng chọn |

| **Cài ứng dụng** | Chọn và cài ứng dụng cơ bản qua WinGet | WinGet / App Installer |

## Cách dùng

1. Chép cả thư mục `TechMaster-Deploy` ra USB, giữ nguyên cấu trúc thư mục con.
2. Mở **`TechMaster Deploy.exe`** và chấp nhận yêu cầu Administrator. Muốn tạo shortcut Desktop, dùng File Explorer hoặc chạy `App\Tao-Shortcut.bat`.
3. Thanh trên cùng hiện tên máy và trạng thái bản quyền Windows / Office (bấm **Làm mới** để đọc lại).
4. Các nút ở tab 1–3 mở công cụ trong **cửa sổ console riêng**, vì các script có bước hỏi / xác nhận (Y/N, gõ YES…). Tab 4 xuất biên bản trực tiếp từ giao diện.

## Cập nhật phiên bản

Từ **v1.1.1.0**, tab **Cập nhật → Kiểm tra cập nhật** lấy mã trực tiếp từ **dangvien-dev/TechMaster-Deploy**, nhánh **main**. Không cần GitHub Release, manifest phát hành trên repo khác hoặc tải / giải nén ZIP bằng tay.

App kiểm tra commit mới, hiển thị phiên bản và nội dung thay đổi, chỉ lấy những tệp nguồn đã thay đổi, rồi sao lưu và hỏi xác nhận trước khi đóng / cập nhật / mở lại. Mỗi lần chỉ dùng tệp của cùng một commit; tệp tải về được đối chiếu Git blob và các bước thay tệp được kiểm tra SHA256. Launcher được biên dịch bằng .NET Framework sẵn có trên Windows, không thực thi script build tải từ repo.

Nguồn công khai không cần đăng nhập. Giao diện thường chỉ hiện phiên bản và các lựa chọn cập nhật / khôi phục. Cấu hình truy cập dành cho người quản lý được mô tả trong RELEASING.md.

**Lịch sử cập nhật**, **Có gì mới?** và **Khôi phục bản trước** vẫn dùng được. Cấu hình biên bản, logo, biên bản đã xuất, kho Office, ODT, nhật ký và Reinstall được giữ nguyên. Sao lưu nằm ở `.updates`; đừng xoá nếu còn muốn quay lại. Tệp chương trình sửa riêng không bị tự ghi đè.

**Bản cũ chưa hỗ trợ repo:** dùng công cụ `TechMaster Update.exe` mới để chọn thư mục app hiện tại và chọn **Yes** lấy trực tiếp từ repo. **No** cho phép chọn ZIP offline khi cần. Sau lần nâng cấp này chỉ dùng nút Kiểm tra cập nhật. Cập nhật ZIP vẫn có để chuyển bản offline.

Các thay đổi chỉ có trong workspace hoặc ZIP chưa tự xuất hiện trên GitHub. Người quản lý phải đẩy mã mới lên `main`; app không tự push hoặc thay đổi repo. Xem [RELEASING.md](RELEASING.md).

## Chữ tiếng Việt trong cửa sổ console

Các công cụ gỡ / cài Office, kích hoạt, biên bản và FixClone dùng chung khởi tạo UTF-8 và chọn font **Consolas** cho cửa sổ console Windows kiểu cũ. Giữ nguyên cả thư mục `App` khi giải nén bộ công cụ. Việc chọn font chỉ áp dụng cho console đang chạy, không sửa font mặc định trong Registry hay profile PowerShell.

Nếu máy vẫn hiện ô vuông, mở menu thanh tiêu đề PowerShell → **Properties → Font → Consolas**, rồi mở lại công cụ. Windows Terminal tự quản lý font: chọn Consolas hoặc một font hỗ trợ tiếng Việt trong Settings của Terminal. Đổi code page riêng lẻ không bổ sung được ký tự còn thiếu trong font.

## Cài Windows

1. Mở tab **Cài Windows**, bấm **Trang tải Microsoft** ở dòng Windows 11 hoặc Windows 10 để mở trang tải chính thức trong trình duyệt.
2. Sau khi tải ISO, bấm **Chọn ISO…**. Ứng dụng gắn ISO, kiểm tra chữ ký Microsoft của `setup.exe` và mở Windows Setup. Các lựa chọn giữ dữ liệu và bước xác nhận cài đặt nằm trong Windows Setup.
3. Để cài mới từ USB, bấm **Tạo USB Windows 11** hoặc **Tạo USB Windows 10**. TechMaster tải và kiểm tra chữ ký của Media Creation Tool, sau đó mở công cụ để bạn chọn USB trống từ 8 GB. Dữ liệu trên USB được chọn sẽ bị xóa.
4. Sau khi cài trực tiếp và kiểm tra dữ liệu, mở lại app, bấm **Dọn Windows.old**. Trong **Lưu trữ → Tệp tạm thời**, chọn **Bản cài đặt Windows trước đây** rồi xác nhận **Xóa tệp**. Xóa Windows.old sẽ bỏ khả năng quay lại bản Windows cũ.

## Biên bản bản quyền

- Thông tin đơn vị lưu ở `BienBan\BienBan-Config.json`, nhập một lần.
- Logo: file `BienBan\Logo.svg` (hoặc `.png` / `.jpg`). Đổi bằng nút **Chọn logo…**.
  WinForms không xem trước được SVG; logo SVG vẫn hiện đúng trong biên bản.
- Biên bản lưu ở `BienBan\BienBan\<Tên máy>_<ngày giờ>.html`, tự mở trong trình duyệt → nút **In / Lưu PDF**.
- Chỉ in 5 ký tự cuối key. Luôn có ghi chú "không phải chứng nhận do Microsoft cấp".
- Tổng kết lấy từ cùng danh sách license hiển thị trong bảng; thiếu dữ liệu / lỗi đọc được báo riêng, không tự kết luận là chưa kích hoạt. Sau khi cập nhật công cụ hoặc trạng thái license, cần **xuất lại biên bản**; HTML cũ không tự cập nhật.

## Tải / cài Office (Office Deployment Tool)

- Theo dõi giai đoạn, thời gian và dung lượng trong kho ngay trên tab Office. Sau khi chạy xong, nút **Xem nhật ký** mở kết quả. Tải và cài từ tab Office chạy nền. Mọi trạng thái và kết quả hiển thị ngay trên tab.

- `setup.exe` (ODT) tự tải từ `officecdn.microsoft.com` lần đầu, **kiểm tra chữ ký số Microsoft** trước khi chạy; chữ ký không hợp lệ thì xoá và dừng.
- Sản phẩm: Home & Business 2024 / 2021 (bán lẻ), Microsoft 365 Apps business / enterprise, LTSC Professional Plus / Standard 2024, Professional Plus 2021 (Volume).
- Mặc định: tiếng Việt + tiếng Anh, 64-bit, không cài Teams, OneDrive, Skype (Lync), Groove, Bing.
- **Tải về kho** một lần (3–5 GB) → chép `KhoOffice\` ra USB / NAS → **Cài từ kho** trên các máy khác, không cần mạng.
- Ô **Key** tuỳ chọn: có key thì ODT cài kèm key và tự kích hoạt; file cấu hình có key bị xoá sau khi chạy.
- Tool **chỉ tải / cài**, không kích hoạt. Bản Volume (LTSC) cần key Volume / KMS của tổ chức; Microsoft 365 kích hoạt bằng tài khoản.

## Gỡ / dọn Office

Trong tab **Tải / cài Office**, bấm **Gỡ / dọn Office…**. Công cụ mở cửa sổ riêng với ba lựa chọn:

1. **Kiểm tra**: liệt kê Product ID Click-to-Run và key Office đọc được từ SoftwareLicensingProduct; chỉ hiển thị 5 ký tự cuối.
2. **Chọn key Office cần xoá**: hiển thị danh sách có số thứ tự, loại license (Retail, Grace / dùng thử, KMS, MAK), tên và 5 ký tự cuối. Nhập số của từng key muốn xoá, ví dụ `1,3`. Mặc định không chọn gì; Enter sẽ huỷ thao tác xoá. Key không chọn được giữ nguyên, gồm key Retail bạn cần dùng. Không gỡ ứng dụng.
3. **Gỡ Office 2021/2024**: dùng ODT có chữ ký Microsoft để gỡ đúng các bộ Office 2021/2024 Click-to-Run nhận diện được, có bước chọn key. Nếu bạn giữ lại key của bộ Office trong phạm vi gỡ, công cụ dừng và hướng dẫn dùng lựa chọn 2 để tránh ảnh hưởng license cần giữ. Chỉ tiếp tục khi bạn chủ động chọn toàn bộ key trong phạm vi gỡ. Giữ các Product ID khác, gồm Microsoft 365, Visio / Project và Office đời cũ. Không hỗ trợ gỡ MSI hoặc sản phẩm không nhận diện được.

Trước thao tác thay đổi, công cụ hiện riêng danh sách **key sẽ xoá** và **key giữ lại**, rồi yêu cầu gõ **XOA OFFICE**. Sau thao tác, công cụ đọc lại để xác minh key đã chọn xoá không còn và các key chọn giữ vẫn khớp. Lưu tài liệu, đóng toàn bộ Office và giữ lại thông tin mua bản quyền trước khi tiếp tục. Nhật ký nằm trong `%LOCALAPPDATA%\TechMaster Deploy\Office Logs`; nút **Xem nhật ký** mở kết quả sau khi đóng công cụ. Lỗi xoá key sẽ chặn bước gỡ ứng dụng; thay đổi đã thực hiện trước lỗi không tự hoàn tác.

Công cụ gọi `ClearKeyManagementServiceMachine`, `ClearKeyManagementServicePort`, `UninstallProductKey` trên từng license có Application ID của Office, rồi đọc lại để kiểm tra. Không chạy `slmgr /upk`, không xoá key Windows hoặc kho token dùng chung. Cấu hình KMS dùng chung với Windows không bị thay đổi.

Một số provider CIM không trả `ReturnValue` khi thực hiện thành công. Khi gặp trường hợp này, công cụ đọc lại cấu hình KMS; sau bước xoá key luôn kiểm tra lại danh sách license. Mã lỗi khác 0, lỗi CIM hoặc trạng thái vẫn còn sẽ được báo lỗi, không coi là đã dọn xong.

KMS có thể thuộc bản quyền hợp lệ của tổ chức. Công cụ **không kết luận bản quyền lậu** từ trạng thái KMS và **không tự xoá phần mềm crack, dịch vụ, tác vụ, tài khoản hoặc token Microsoft 365**. Công cụ kích hoạt bên ngoài còn trên máy có thể tự nạp key lại; cần gỡ công cụ đó và quét bảo mật riêng trước khi cài bản quyền hợp lệ. Vì vậy không coi thao tác này là chứng nhận máy đã sạch mã độc hoặc đã khôi phục mọi tệp Office từng bị sửa.

Chạy trực tiếp bằng Windows PowerShell (vẫn yêu cầu xác nhận khi xoá):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Inspect
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Keys
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Remove
```

Kiểm thử mô phỏng, không thay đổi Office trên máy:

```powershell
powershell.exe -NoProfile -File Office\Test-OfficeCleanup.ps1
```

## Cài ứng dụng cơ bản

1. Mở tab **Cài ứng dụng**, chọn Chrome, 7-Zip, VLC, SumatraPDF, Foxit PDF Reader, ONLYOFFICE Desktop Editors, LibreOffice, Notepad++, Zalo, WinRAR hoặc EVKey rồi bấm **Cài ứng dụng đã chọn**.
2. Giữ TechMaster mở trong lúc WinGet tải và cài lần lượt. Tiến trình đếm số ứng dụng đã xử lý. WinGet bỏ qua phiên bản đã cài và tab hiển thị kết quả cho từng ứng dụng.
3. Bấm **Xem nhật ký** để xem thông báo WinGet. Nếu máy chưa có WinGet, bấm **Hướng dẫn WinGet** để cài hoặc cập nhật App Installer.

## Chi tiết từng bộ

- `FixClone\README.md`
- `KichHoat\README.md`

## Trạng thái kiểm tra

| Phần | Trạng thái |
|---|---|
| Script FixClone, Kich-Hoat (TEST qua LAN) | Đã chạy trên máy thật 2026-11-16 |
| Mẫu biên bản (bố cục, logo, 1 trang A4) | Đã xem trước bằng dữ liệu giả |
| Giao diện `TechMaster-Deploy.ps1` (WinForms) | Founder đã mở được (tab 1, tab 4); tab Office **chưa chạy** |
| `Office\Office-ODT.ps1` | XML cấu hình đã kiểm cú pháp; tải / cài thật **chưa chạy** |
| Đọc WMI trong biên bản trên máy thật | **Chưa chạy** |

Bản này là công cụ tạm dùng trước. Bản chính thức sẽ nằm trong TechMaster Pro theo SPEC-005 / 006 / 007 và issue #44.

## Build launcher từ mã nguồn

Trên Windows, chạy `powershell.exe -NoProfile -ExecutionPolicy Bypass -File App\Build-Launcher.ps1` trong thư mục dự án. File `TechMaster Deploy.exe` sẽ được tạo cạnh README.
