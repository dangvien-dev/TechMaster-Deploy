# TechMaster Deploy

Bộ công cụ triển khai Windows và Office.

| Tab | Công cụ | Thư mục |
|---|---|---|
| **Máy gốc (Sysprep)** | Kiểm tra / sửa lỗi Sysprep, chuẩn bị máy gốc và chạy Sysprep, thư mục `Reinstall` | `FixClone\` |
| **Sau khi clone** | Xử lý trùng lặp (tên máy, MachineGuid, AnyDesk, TeamViewer…), chỉnh định dạng ngày giờ / số | `FixClone\` |
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

## Tải / cài Office (Office Deployment Tool)

- Theo dõi giai đoạn, thời gian và dung lượng trong kho ngay trên tab Office. Sau khi chạy xong, nút **Xem nhật ký** mở kết quả. Tải và cài từ tab Office chạy nền. Mọi trạng thái và kết quả hiển thị ngay trên tab.

- `setup.exe` (ODT) tự tải từ `officecdn.microsoft.com` lần đầu, **kiểm tra chữ ký số Microsoft** trước khi chạy; chữ ký không hợp lệ thì xoá và dừng.
- Sản phẩm: Home & Business 2024 / 2021 (bán lẻ), Microsoft 365 Apps business / enterprise, LTSC Professional Plus / Standard 2024, Professional Plus 2021 (Volume).
- Mặc định: tiếng Việt + tiếng Anh, 64-bit, không cài Teams, OneDrive, Skype (Lync), Groove, Bing.
- **Tải về kho** một lần (3–5 GB) → chép `KhoOffice\` ra USB / NAS → **Cài từ kho** trên các máy khác, không cần mạng.
- Ô **Key** tuỳ chọn: có key thì ODT cài kèm key và tự kích hoạt; file cấu hình có key bị xoá sau khi chạy.
- Tool **chỉ tải / cài**, không kích hoạt. Bản Volume (LTSC) cần key Volume / KMS của tổ chức; Microsoft 365 kích hoạt bằng tài khoản.

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
