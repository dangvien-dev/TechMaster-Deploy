# Có gì mới trong TechMaster Deploy?

## 2.2.5.0 — 21/11/2026

- Thông báo có khung màu và biểu tượng dùng chung: xanh lam cho thông tin / đang xử lý, vàng cho bước chờ kiểm tra, xanh lá cho thao tác đã xác nhận và đỏ cho lỗi. Áp dụng ở UltraViewer, key Windows / Office, hộp thoại và các cửa sổ tác vụ. Thông báo dài có thể cuộn, thông báo trống tự ẩn.
- Sau reset UltraViewer hiển thị vàng và làm nổi nút Kiểm tra ID mới; chỉ hiển thị xanh lá khi kiểm tra xác nhận thành công. Bản sao lưu có khung riêng dễ nhận biết.
- Thêm Đơn vị / công ty khách hàng và Địa chỉ khách hàng ở Biên bản. Đưa sang HTML và điền sẵn trong mẫu xác nhận bàn giao, phân biệt với thông tin bên cung cấp. Dữ liệu khách không ghi vào cấu hình thông tin đơn vị dùng chung.
- Thêm hai nút đổi menu chuột phải kiểu Windows 10 / khôi phục Windows 11 trong Sau khi clone. Lưu trạng thái trước thay đổi theo tài khoản hiện tại; hỏi riêng trước khi khởi động lại Explorer.
- Dọn Windows.old mở Disk Cleanup với quyền quản trị, hướng dẫn chọn Dọn tệp hệ thống và kiểm tra lại thư mục sau khi đóng công cụ. Không báo đã dọn khi thư mục vẫn còn.
- Giữ dữ liệu khách hàng chứa ký tự HTML hoặc giống placeholder dưới dạng văn bản; hướng dẫn portal yêu cầu nhập số máy cài thực tế theo giấy phép.

## 2.2.4.0 — 21/11/2026

- Đồng bộ giao diện bảng: tiêu đề nền xanh nhạt, dòng cao thoáng hơn, nền xen kẽ và màu chọn dễ đọc; viền focus không làm dịch nội dung. Áp cùng kiểu bảng cho key Office, kết quả cài ứng dụng, lịch sử cập nhật và Fix Driver.
- Bảng key Office có cột tiếng Việt, ô chọn dễ bấm, 5 ký tự cuối dùng chữ đều và tên giấy phép tự xuống dòng / xem đầy đủ qua tooltip. Giữ cách chọn key và xác nhận xoá.

## 2.2.3.0 — 21/11/2026

- Đưa Key dùng tạm Office… vào mục Kích hoạt, cạnh Kích hoạt Office và Mở portal, tương tự phần key Windows. Cửa sổ từ nút này chỉ kiểm tra / chọn / xoá key, không có nút gỡ bộ Office.
- Giữ thao tác Gỡ Office… ở mục Tải / cài Office. Mặc định không chọn key để xoá; nút Chọn key dùng thử đánh dấu Grace / Trial đã nhận diện, xoá vẫn cần kiểm tra và xác nhận.

## 2.2.2.0 — 21/11/2026

- Sau khi cài WinRAR hoặc khi WinGet báo đã có, mở WinRAR lần đầu để hoàn tất thiết lập theo tài khoản và kiểm tra lại menu chuột phải. Giữ WinRAR đang chạy, không ép cài lại hoặc tự sửa registry Explorer. Ghi kết quả mở ứng dụng vào nhật ký.
- Sau cài Foxit Reader, kiểm tra riêng các hàng đợi máy in PDF và ghi tên / driver / cổng in. Phân biệt đã cài Reader với có máy in PDF; lỗi đọc danh sách máy in không bị báo nhầm là thiếu máy in.
- Giữ kết quả chẩn đoán đã xử lý trong worker, ví dụ không đọc được danh sách máy in, thay vì đổi thành lỗi cài đặt chung khi không có bản ghi lỗi chưa xử lý.
- Bổ sung hướng dẫn: Foxit Reader bản mới không kèm máy in ảo như Reader cũ; Microsoft Print to PDF là tính năng riêng của Windows. Bước kiểm tra không tự cài thêm máy in hoặc driver.

## 2.2.1.0 — 21/11/2026

- Rà soát bo góc các cửa sổ phụ: nút trong Định danh UltraViewer, Bàn phím, Chuẩn bị Sysprep, Chẩn đoán và Gỡ / dọn Office dùng template chung khi chưa có style riêng.
- Bo thêm ô nhập, ô mật khẩu, danh sách, bảng và thanh tiến trình còn vuông trong Cập nhật, Chẩn đoán, Quản lý ứng dụng, Gỡ Office và Fix Driver. Giữ control gốc để nhập liệu, chọn, cuộn và chạy tác vụ như trước.
- Giữ nét viền bo góc ở lớp trên, đồng bộ ẩn / hiện khung với control và giữ viền focus của nút không làm dịch chữ.

## 2.2.0.0 — 20/11/2026

- Thêm Fix Driver dùng chung cho mọi máy / mainboard: quét thiết bị có mã lỗi, hiện đầy đủ Hardware ID / InstanceId và tạo link Microsoft Update Catalog đã URL-encode để kỹ thuật viên tự tải driver.
- Cài từ CAB / thư mục INF đã chọn, dò phần cứng rồi quét lại; kho driver USB / NAS đối chiếu ID từ cụ thể đến chung, cài tối đa 4 vòng để xử lý driver cha / con. Không tải tự động, không đóng gói driver vào app.
- Profile JSON cục bộ chỉ bổ sung khuyến nghị theo model khi nhận diện khớp. Có mẫu SingPC I5-12450H BIOS 5.32 với Serial IO, SST OED / thiết bị con nhánh 10.29.0.x; không áp cấu hình này lên máy khác.
- Disable thiết bị con và chỉnh nguồn là tuỳ chọn riêng, xem và xác nhận bằng nút bấm; kiểm tra Admin, ghi log, đọc lại trạng thái. Giữ bảo vệ bus cha, không tự restart hoặc thay BIOS.
- Xuất HTML có thông tin máy, trước / sau, lệnh đã chạy, thiết bị còn lỗi và link. Tách Code 0, thiết bị biến mất và Code 22; không báo hết lỗi chỉ vì pnputil trả thành công. Dữ liệu driver/profile/log của kỹ thuật viên lưu local.

## 2.1.12.0 — 18/11/2026

- Căn Hướng dẫn nhanh và Liên hệ / góp ý cùng lề trái, cỡ chữ và chiều rộng trong thanh bên. Bỏ nền chọn cố định của Hướng dẫn nhanh; hai mục có cùng kiểu rê chuột / bàn phím.
- Tách vùng menu cuộn và vùng trợ giúp cuối thanh bên, giữ chân trang trong đúng khung khi cửa sổ thấp hoặc tăng tỷ lệ hiển thị. Thanh cuộn menu gọn và cùng nền tối, tránh cảm giác chân trang nhô ra.

## 2.1.11.0 — 18/11/2026

- Thêm kiểm tra / dọn riêng key cài đặt chung Windows Pro …3V66T: chỉ dọn khi chưa kích hoạt, khớp SKU / kênh và xác minh đầy đủ từ hệ thống. Giữ giấy phép đang kích hoạt và key khác; có biên nhận, hoàn tác và khôi phục khi Sysprep lỗi. Thêm lựa chọn mặc định tắt vào chuẩn bị Sysprep; chỉ xử lý sau clone khi đã bật và lưu lựa chọn.
- Phân biệt ân hạn Windows với giấy phép dùng thử. Key chung vẫn có thể có Installation ID, nhưng không được dùng để lấy QR / nạp CID offline; vẫn cho phép thử online để nhận bản quyền số.
- Khi có bản ghi key chung và key riêng, ưu tiên key riêng. Đọc mới và xác nhận 5 ký tự cuối trước QR; đối chiếu lại đúng sản phẩm / key / IID trước khi nạp CID, dừng nếu có thay đổi.
- Office thiếu key hoặc chỉ có SKU Grace / Trial hiện hướng dẫn bằng hộp thoại, thay vì chỉ ghi lỗi rồi đóng cửa sổ lệnh.

## 2.1.10.0 — 18/11/2026

- Thêm nút Lưu thông tin tại Biên bản bản quyền: lưu riêng thông tin đơn vị / kỹ thuật viên sau khi sửa hoặc xoá trắng, không cần xuất biên bản.
- Thêm nút Xoá logo riêng, giữ thông tin đơn vị và các biên bản đã xuất; xoá xong cập nhật ngay ô xem trước.

## 2.1.9.0 — 18/11/2026

- Sửa logo SVG đè lên header khi cuộn: xem trước bằng ảnh WPF để được cắt theo vùng cuộn. Giữ nguyên tệp logo gốc khi xuất biên bản và xác nhận.

## 2.1.8.0 — 18/11/2026

- Tinh chỉnh chấm báo cập nhật: thu nhỏ, đặt cạnh chữ bên trong nút và căn giữa theo chiều dọc. Chấm và chữ cùng đổi trạng thái với nút, không còn nhô khỏi góc.

## 2.1.7.0 — 18/11/2026

- Thêm hai mẫu xác nhận cung cấp / bàn giao bản quyền riêng cho khách lẻ và khách công ty đã được cấp hóa đơn / chứng từ. Chọn từng phần mềm, dùng thông tin đơn vị / logo đang lưu, xuất HTML để xem, in hoặc lưu PDF; key chỉ hiện 5 ký tự cuối.
- Mẫu công ty có mã số thuế và tham chiếu hóa đơn tuỳ chọn; không yêu cầu kỹ thuật viên biết số chứng từ. Thông tin khách chỉ ghi vào file xuất, không đưa vào cấu hình dùng chung.
- Kiểm tra chấm đỏ bằng số phiên bản công khai trước, tránh phụ thuộc Git refs / API khi có bản mới. Mạng lỗi thử lại sau 1 phút, giữ thông báo đã biết và cho phép Làm mới yêu cầu kiểm tra ngay.

## 2.1.6.0 — 18/11/2026

- Đổi icon sang biểu tượng chữ T và mũi tên triển khai, nền navy với màu cyan / mint. Đồng bộ launcher, taskbar và cửa sổ cập nhật; hỗ trợ kích thước 16–256 px.

## 2.1.5.0 — 17/11/2026

- Sửa lỗi mở Có gì mới, Hướng dẫn nhanh và Liên hệ khi vừa chạy app: cửa sổ thông tin tự nạp hàm đọc phiên bản, không phụ thuộc việc đã mở updater.

## 2.1.4.0 — 17/11/2026

- Sửa phóng to cửa sổ còn hở cạnh phải / dưới: chỉ co kích thước lúc mở ban đầu, để Windows xử lý chế độ phóng to theo màn hình.

- Tương thích khi nâng từ updater cũ: nếu app bị gọi lên sớm, cửa sổ chính chờ updater đóng rồi mới hiện để không che kết quả.

## 2.1.3.0 — 17/11/2026

- Bản chia sẻ để trống thông tin đơn vị và không kèm logo công ty; thêm nút xoá thông tin đơn vị / logo đang lưu.

- Quản lý ứng dụng bổ sung bằng ID WinGet hoặc tệp EXE / MSI; cấu hình chỉ lưu local theo tài khoản Windows, giữ khi cập nhật và không đưa lên repo.

- Thêm chấm đỏ ở nút Cập nhật khi phát hiện bản mới bằng kiểm tra nền; không tự tải hoặc bật popup.

- Có gì mới hiển thị theo phiên bản trong cửa sổ WPF; thêm Hướng dẫn nhanh theo từng tính năng và Liên hệ / góp ý qua Zalo 0976852096, email vienkendo@gmail.com.

- Giữ nền xanh của menu khi khoá thao tác để cập nhật; tránh khối trắng làm menu trông như nổi lên.

- Thêm UltraViewer trong Cài ứng dụng, dùng bộ cài tiếng Việt 6.6.133 chính thức thay vì bản WinGet cũ; kiểm tra chữ ký / phiên bản, giữ bản đã cài hoặc đang chạy.

- Cập nhật / khôi phục xong giữ màn hình Hoàn tất. Chỉ mở app khi bấm Đóng và mở ứng dụng, sau khi cửa sổ updater đã đóng; nút X chỉ đóng updater. Không tự mở app khi lỗi.

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
