# Tiến độ TechMaster Deploy

Cập nhật ngày 16/11/2026.

| Hạng mục | Đã kiểm tra | Còn cần thử trên máy thật |
| --- | --- | --- |
| Launcher và giao diện | Build `TechMaster Deploy.exe`. Kiểm tra bố cục 7 tab ở mức mô phỏng 100%, 125% và 150%. | Mở bản ZIP đã giải nén trên máy triển khai. |
| Sysprep và định dạng vùng | Mô phỏng ghi `dd/MM/yyyy`, `HH:mm` cho tài khoản hiện tại và hồ sơ mặc định, gồm các trường hợp ghi lỗi. | Sysprep, bung ảnh và kiểm tra định dạng sau khi đăng nhập bằng `admin` và một tài khoản mới. |
| Office | Mô phỏng tiến trình, kết quả thành công hoặc lỗi, nhật ký và việc chạy nền. | Tải bộ cài về kho rồi cài thử trên một máy. |
| Cài Windows | Mô phỏng gắn và dùng lại ISO, xác minh chữ ký Microsoft và dọn ổ gắn khi lỗi. | Mở Windows Setup từ một ISO chính thức và kiểm tra các lựa chọn giữ dữ liệu. |
| Tạo USB và dọn `Windows.old` | Mô phỏng tải Media Creation Tool, chặn chữ ký không hợp lệ và mở đúng trang Lưu trữ khi có `Windows.old`. | Tạo USB thử và kiểm tra có khởi động được. Kiểm tra mục xóa bản Windows trước trên máy vừa nâng cấp. |
| Cài ứng dụng cơ bản | Dùng WinGet mô phỏng để kiểm tra Chrome, 7-Zip, VLC, SumatraPDF, Notepad++, Zalo, WinRAR và EVKey, gồm bỏ qua app đã có, báo lỗi từng app, yêu cầu khởi động lại và nhật ký. | Cài thử một app trên máy có WinGet, rồi chạy lại để xác nhận lượt sau được bỏ qua. |

## Build

Chạy `App/Build-Launcher.ps1` trên Windows để tạo `TechMaster Deploy.exe`. Hướng dẫn thao tác nằm trong [README](README.md).
