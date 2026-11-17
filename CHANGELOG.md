# Có gì mới trong TechMaster Deploy?

## 2.1.2.0 — 17/11/2026

- QR trên máy tính mở trang điện thoại có Installation ID, nút sao chép, link portal Microsoft và ô gửi Confirmation ID; không cần tự nhập link portal.

- Bỏ ô và dòng Số hoá đơn / nguồn mua key khỏi giao diện, lời nhắc và biên bản xuất mới; giữ thông tin đơn vị, khách hàng, kỹ thuật viên và trạng thái kích hoạt.

- Sửa nét viền cong bị mất ở các ô bo góc. Chỉ cắt phần nền bên trong, vẽ đường viền phía trên để giữ nét liền ở trạng thái thường và khi focus.

## 2.1.1.0 — 17/11/2026

- Bo góc các ô nhập, chọn sản phẩm, khung logo, bảng kết quả và thanh tiến trình; giữ điều khiển Windows gốc cho nhập chữ, chọn mục, cuộn và hoạt ảnh.
- Giữ chữ trong nút Cập nhật / Làm mới ở giữa; viền focus vẽ riêng, không đẩy chữ hoặc làm thiếu chỗ trong nút.
- Khi cập nhật, nút Cập nhật vẫn gọi lại cửa sổ đang chạy, kể cả bị thu nhỏ. Thanh trạng thái chính hiện tiến trình tải; đóng cửa sổ chính vẫn cho phép trình cập nhật tiếp tục độc lập.
- Hiện tên tệp đang tải / kiểm tra trước mỗi lần chờ mạng. Các bản cũ dùng giao diện updater cũ cho đến khi hoàn tất nâng cấp; mở lại từ bản mới để nhận hộp thoại WPF và icon TechMaster.

## 2.1.0.0 — 17/11/2026

- Tích hợp sao lưu / reset / kiểm tra / khôi phục ID UltraViewer 6.6.133. Chỉ xử lý UID và PreferID; giữ LastHR và thông tin phần cứng.
- Chuẩn bị Sysprep dừng, tắt tự khởi động UltraViewer sau khi bỏ định danh máy gốc; sau clone khôi phục dịch vụ và cấp ID riêng một lần. Nếu Sysprep lỗi, khôi phục định danh và dịch vụ máy gốc.
- Lưu và kiểm tra Normal.dotm, ribbon, Word Options trước khi dọn key. Tự động chỉ dọn key Office 2021/2024 có tên Grace/Trial và chưa kích hoạt; giữ Retail, key chưa xác định, Visio / Project và thiết lập ứng dụng. Kiểm tra lại theo lựa chọn đã lưu sau clone.
- Gỡ / dọn Office dùng bảng tích chọn từng key, mặc định không chọn gì. Các bước xác nhận chuyển sang nút bấm, gồm Sysprep, bàn phím và kích hoạt; không cần gõ XOA OFFICE / YES.
- Dùng hộp thoại WPF đồng bộ, nút tiếng Việt; cập nhật xong chỉ còn một nút Đóng và hiển thị phiên bản mới.
- Đặt icon và AppUserModelID TechMaster cho cửa sổ WPF để tách nhóm taskbar khỏi PowerShell.
- Chỉnh ngày ngắn thành dd/MM/yyyy cùng hai dấu số; giữ vùng, ngôn ngữ, bàn phím và các định dạng khác.

## 2.0.0.0 — 17/11/2026

- Chuyển toàn bộ cửa sổ chính sang WPF: thanh điều hướng 8 mục, bố cục co giãn, cuộn nội dung và giữ hai nút đầu trang thẳng hàng.
- Cập nhật bằng cửa sổ WPF: kiểm tra, tải, xem tiến trình, xác nhận cài và khôi phục bằng nút bấm. Giữ cơ chế kiểm tra tệp, sao lưu và dữ liệu.
- Đọc bản quyền, xuất biên bản và kiểm tra ISO chạy nền để cửa sổ tiếp tục phản hồi.
- Thêm chẩn đoán UltraViewer sau clone: bản cài, tiến trình, card mạng, MAC đặt thủ công, tên trường cấu hình và SHA256 trường định danh để so sánh; không xuất mật khẩu / giá trị gốc hoặc tự thay ID khi chưa xác định nguyên nhân.
- Nhắc chọn Screen Snipping / Always và kiểm tra icon Desktop trước Sysprep; đưa lựa chọn ms-screenclip đã chọn vào cấu hình ứng dụng mặc định cho user mới.
- Sao lưu và dọn shortcut Word / Excel cùng đích giữa Desktop cá nhân và Public Desktop, giữ Word Options, Normal.dotm, tài liệu và shortcut có tham số riêng.

## 1.1.3.0 — 17/11/2026

- Tải bản cập nhật công khai trực tiếp, tránh phụ thuộc giới hạn API khi nhiều máy dùng chung mạng.
- Vẫn chỉ tải tệp thay đổi, kiểm tra nội dung, sao lưu và giữ cấu hình / dữ liệu.
- Thêm công cụ sửa cập nhật một lần cho các bản cũ đang gặp lỗi kết nối.

## 1.1.2.0 — 17/11/2026

- Sửa lỗi không đóng được app khi xác nhận cập nhật; chỉ thay tệp sau khi app đã thoát hẳn.
- Tinh gọn phần cập nhật, bỏ thông tin kỹ thuật khỏi màn hình sử dụng. Căn nút Cập nhật ngang hàng với Làm mới.
- Thêm nút mở portal Microsoft ngay trên trang QR; đóng riêng cửa sổ QR sau khi nhận mã xác nhận khi dùng Edge hoặc Chrome.
- Chỉnh định dạng chỉ đổi dấu thập phân thành `,` và dấu hàng nghìn thành `.`; giữ nguyên mọi thiết lập khác.
- Cấu hình clone lấy vùng và ngôn ngữ hiện tại của máy gốc, không ép sang Việt Nam.
- Thêm Bàn phím US cho EVKey: tránh chuyển nhầm sang bộ gõ Windows, giữ ngôn ngữ hiển thị, có sao lưu và khôi phục.

## 1.1.1.0 — 17/11/2026

- Kiểm tra và tải phiên bản mới ngay trong ứng dụng, không cần giải nén thủ công.
- Chỉ tải thành phần thay đổi, giữ cấu hình và dữ liệu đã có.
- Tiếp tục hỗ trợ cài bản cập nhật từ tệp khi cần dùng offline.

## 1.1.0.0 — 17/11/2026

- Thêm lịch sử cập nhật, sao lưu và quay lại bản trước.
- Chọn từng key Office cần xoá để giữ key Retail đang dùng.
- Sửa thông báo sau khi nạp mã xác nhận và dòng tổng kết biên bản bản quyền.
- Cải thiện font tiếng Việt trong console và tăng chữ biên bản thêm một mức.
