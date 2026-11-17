# Tiến độ TechMaster Deploy

Cập nhật ngày 17/11/2026.

Phiên bản **1.1.1.0** chuyển sang đọc trực tiếp repo dangvien-dev/TechMaster-Deploy/main. Không cần Release hoặc feed ở repo khác. Đã qua 27 kiểm tra repo (GitHub mô phỏng, hash Git blob chuẩn, tải tệp đổi, giao dịch tệp thật, giữ dữ liệu và quay lại) và 59 kiểm tra ZIP / giao dịch / khởi chạy updater. API GitHub, DPAPI và giao diện Windows còn cần kiểm tra thực tế. Bản cục bộ ghi cả commit nền và dấu dirty để không nhầm với bản đã công bố.

Lịch sử: phiên bản **1.1.0.0** thêm cập nhật ngay trong app, công cụ nâng cấp một lần cho bản cũ, kiểm tra gói bằng SHA256, chỉ thay tệp chương trình có thay đổi, sao lưu / quay lại và giữ dữ liệu người dùng. 63 kiểm tra updater đã qua với ZIP và giao dịch tệp thật trong thư mục thử; giao diện, đóng / mở lại app và nâng cấp trên Windows PowerShell 5.1 còn cần thử thực tế. Luồng Release này được thay bằng cập nhật repo ở 1.1.1.0.

Console: đã dùng chung thiết lập UTF-8 / Consolas cho gỡ và cài Office, kích hoạt, xuất biên bản, FixClone và tạo shortcut. Đã biên dịch phần Win32 bằng cả PowerShell và trình biên dịch C# .NET Framework tương thích; 106 kiểm tra hồi quy vẫn qua. Hiển thị thực tế trên Windows PowerShell 5.1 / Windows Terminal còn cần thử trên các máy bị ô vuông.

| Hạng mục | Đã kiểm tra | Còn cần thử trên máy thật |
| --- | --- | --- |
| Launcher và giao diện | Build `TechMaster Deploy.exe`. Kiểm tra bố cục 7 tab ở mức mô phỏng 100%, 125% và 150%. | Mở bản ZIP đã giải nén trên máy triển khai. |
| Sysprep và định dạng vùng | Mô phỏng ghi `dd/MM/yyyy`, `HH:mm` cho tài khoản hiện tại và hồ sơ mặc định, gồm các trường hợp ghi lỗi. | Sysprep, bung ảnh và kiểm tra định dạng sau khi đăng nhập bằng `admin` và một tài khoản mới. |
| Office | Mô phỏng tiến trình, kết quả thành công hoặc lỗi, nhật ký và việc chạy nền. | Tải bộ cài về kho rồi cài thử trên một máy. |
| Gỡ / dọn Office | 52 kiểm tra mô phỏng (gồm chọn từng key, giữ Retail khi xoá Grace, không chọn thì không xoá, chặn gỡ khi còn key muốn giữ, lỗi CIM không trả ReturnValue trên Retail / Grace): chọn đúng Office 2021/2024, giữ key Windows và các sản phẩm ngoài phạm vi, lỗi CIM / ODT, xác minh sau thao tác, chặn Office đang mở và ODT không có chữ ký hợp lệ. Đã thử menu huỷ và khoá chéo tiến trình cài / dọn. | Thử bằng Windows PowerShell 5.1 trên máy thử có Office 2021/2024; xác nhận gỡ thực tế, dọn key / cấu hình KMS, giữ sản phẩm khác và nhật ký. Không kiểm tra gỡ thật trong môi trường Linux. |
| Thông báo kích hoạt online / CID | 26 kiểm tra mô phỏng: CIM không trả mã, mã 0 nhưng chưa active, mã lỗi thật, lỗi CIM, trạng thái cập nhật chậm và đọc đúng license. Không còn suy ra thất bại từ `ReturnValue` trống; báo thành công theo trạng thái đã xác minh. | Kiểm tra lại thông báo trên Windows PowerShell 5.1 sau khi nạp CID thật. Bản sửa chưa được chạy kích hoạt thật trong môi trường Linux. |
| Tổng kết biên bản bản quyền | 28 kiểm tra xuất HTML thật với CIM mô phỏng: một Windows và một Office active, thiếu Office, có Grace chưa active, Windows chưa active, thiếu dữ liệu và lỗi đọc CIM. Chuẩn hoá danh sách tại nơi gọi để tránh `.Count` của đối tượng CIM đơn; tách thiếu thông tin khỏi chưa kích hoạt. | Xuất lại biên bản trên máy Windows PowerShell 5.1 để xác nhận trường hợp thực tế. File HTML đã xuất trước đó không tự cập nhật. |
| Cài Windows | Mô phỏng gắn và dùng lại ISO, xác minh chữ ký Microsoft và dọn ổ gắn khi lỗi. | Mở Windows Setup từ một ISO chính thức và kiểm tra các lựa chọn giữ dữ liệu. |
| Tạo USB và dọn `Windows.old` | Mô phỏng tải Media Creation Tool, chặn chữ ký không hợp lệ và mở đúng trang Lưu trữ khi có `Windows.old`. | Tạo USB thử và kiểm tra có khởi động được. Kiểm tra mục xóa bản Windows trước trên máy vừa nâng cấp. |
| Cài ứng dụng cơ bản | Dùng WinGet mô phỏng để kiểm tra Chrome, 7-Zip, VLC, SumatraPDF, Foxit PDF Reader, ONLYOFFICE Desktop Editors, LibreOffice, Notepad++, Zalo, WinRAR và EVKey, gồm bỏ qua app đã có, báo lỗi từng app, yêu cầu khởi động lại và nhật ký. | Cài thử một app trên máy có WinGet, rồi chạy lại để xác nhận lượt sau được bỏ qua. |

## Build

Chạy `App/Build-Launcher.ps1` trên Windows để tạo `TechMaster Deploy.exe`. Hướng dẫn thao tác nằm trong [README](README.md).
