# Lịch sử phiên bản TechMaster Deploy

## 1.1.1.0 — 17/11/2026

- Nút Cập nhật từ repo đọc trực tiếp `dangvien-dev/TechMaster-Deploy`, nhánh `main`; không cần GitHub Release hay tải ZIP bằng tay.
- Chốt từng lần cập nhật theo một commit; đối chiếu Git blob và chỉ tải tệp nguồn đã thay đổi. Launcher được dựng từ C# bằng .NET Framework có sẵn của Windows, không chạy script build tải từ mạng.
- Repo public không cần token. Tuỳ chọn repo riêng tư lưu token chỉ đọc bằng Windows DPAPI, ngoài thư mục app và gói cập nhật.
- Giữ cập nhật ZIP offline, bảo vệ cấu hình / logo / kho Office và quay lại bản trước.

## 1.1.0.0 — 17/11/2026

- Thêm tab Cập nhật: kiểm tra bản mới, cài ZIP, xem lịch sử, quay lại phiên bản trước.
- Kiểm tra SHA256, chỉ thay tệp chương trình đã thay đổi; giữ cấu hình, logo, biên bản, kho Office, ODT, nhật ký và Reinstall.
- Sao lưu trước khi cài; tự khôi phục tệp cũ nếu cập nhật lỗi. Chặn ghi đè tệp chương trình đã được sửa riêng.
- Giữ các thay đổi đã làm: chọn từng key Office để giữ Retail, kiểm tra trạng thái sau kích hoạt CID, sửa tổng kết biên bản, font console tiếng Việt và tăng chữ biên bản thêm 1 px.

Các ZIP thử trước 1.1.0.0 chưa có cơ chế đánh số và tự cập nhật.
