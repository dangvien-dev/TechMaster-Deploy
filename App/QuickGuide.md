# Hướng dẫn nhanh TechMaster Deploy

## Bắt đầu
- Giữ nguyên cả thư mục TechMaster-Deploy, mở TechMaster Deploy.exe và chấp nhận yêu cầu quản trị.
- Chọn nhóm tính năng ở menu bên trái. Nút Làm mới đọc lại trạng thái Windows / Office.
- Với máy gốc, chuẩn bị cấu hình trước Sysprep. Với máy khách đã clone, dùng Sau khi clone để kiểm tra và xử lý.

## Máy gốc / Sysprep
- Cài phần mềm, đặt font, khổ giấy và lề Word theo nhu cầu rồi đóng các ứng dụng Office.
- Bấm Chuẩn bị và Sysprep. Kiểm tra Screen Snipping / Always và sao lưu, dọn icon Word / Excel trùng.
- Chọn dọn key cài đặt chung Windows để kiểm tra key Pro …3V66T chưa kích hoạt, có đối chiếu key từ hệ thống. Windows đang kích hoạt, key khác và trường hợp không xác minh được đều được giữ. Nếu Sysprep lỗi, key chung có thể được khôi phục theo biên nhận.
- Giữ lựa chọn dọn key Grace / Trial nếu cần; key Retail và thiết lập Word được giữ. Xem danh sách trước khi tự chọn thêm key cần xoá.
- Chuẩn bị UltraViewer 6.6.133 sẽ ngắt kết nối ở bước cuối; thao tác tại máy hoặc dùng kênh hỗ trợ khác. Nếu Sysprep lỗi, công cụ khôi phục định danh máy gốc.
- Sau khi Sysprep tắt máy, dùng USB để clone ổ. Không bật lại máy gốc trước khi tạo ảnh.

## Sau khi clone
- Ảnh được chuẩn bị bằng công cụ mới sẽ tự chạy xử lý lần đăng nhập đầu. Có thể mở Xử lý trùng lặp để xem và chọn lại các thao tác khi cần.
- Chỉnh ngày / số đặt ngày ngắn dd/MM/yyyy, thập phân dấu phẩy và phân nhóm dấu chấm; giữ vùng và bàn phím.
- Bàn phím / EVKey cho phép chỉ dùng kiểu nhập US, có sao lưu và khôi phục.
- Reset ID UltraViewer có sao lưu. Chỉ reset khi cần, sau đó mở UltraViewer và Kiểm tra ID mới; thao tác này ngắt kết nối hỗ trợ.
- Kiểm tra Desktop và phím chụp để giữ một icon Word / Excel dùng chung và chọn Screen Snipping cho Windows + Shift + S.

## Kích hoạt
- Khi có khách theo dõi, có thể nhập key trực tiếp trong Windows Settings → System → Activation hoặc Word → File → Account.
- Trong TechMaster, chọn Windows hoặc Office để kiểm tra và kích hoạt bằng key hợp lệ. Nếu online chưa thành công, công cụ hướng dẫn dùng portal Microsoft.
- Quét QR 1 bằng điện thoại cùng Wi-Fi/LAN, bấm Sao chép Installation ID rồi Mở portal Microsoft. Lấy Confirmation ID 48 số trên portal.
- Quay lại trang điện thoại hoặc quét QR 2, dán mã rồi bấm Gửi về máy tính. Cửa sổ QR trên máy tính sẽ đóng sau khi nhận mã.
- Key cài đặt chung Windows mở cửa sổ kiểm tra / dọn riêng; lựa chọn dọn trong Sysprep mặc định tắt, chỉ bật sau khi đã kiểm tra; chỉ dọn key Pro …3V66T chưa kích hoạt đã xác minh. Có biên nhận và nút Hoàn tác; không ghi đè key mới đã nhập.
- Trước khi lấy Installation ID, đối chiếu 5 ký tự cuối key trong hộp xác nhận. App ưu tiên key riêng, đọc lại IID và kiểm tra lần nữa trước khi nạp CID. Thay key hoặc IID sẽ dừng mã cũ; chạy lại để lấy QR mới. Key chung chỉ được thử online để nhận bản quyền số, không dùng để lấy QR offline.
- Office chưa nhập key hoặc chỉ có SKU Grace / Trial sẽ hiện hướng dẫn nhập key trong Word hoặc đăng nhập Microsoft 365.
- Kiểm tra lại màn hình Activation hoặc Product Activated của Microsoft trước khi bàn giao. Trạng thái kích hoạt không tự chứng minh nguồn gốc giấy phép.

## Biên bản bản quyền
- Bản chia sẻ mới để trống thông tin đơn vị và không kèm logo công ty. Xoá thông tin đơn vị / logo giúp dọn cấu hình đang lưu trước khi chuyển cho bên khác; biên bản đã xuất vẫn được giữ.
- Nhập hoặc sửa thông tin đơn vị / kỹ thuật viên rồi bấm Lưu thông tin để dùng cho lần sau; trường xoá trắng cũng được lưu. Tên khách hàng dùng cho biên bản đang lập.
- Chọn logo được lưu ngay. Xoá logo chỉ xoá ảnh logo đang lưu, giữ thông tin đơn vị và biên bản đã xuất.
- Bấm Xuất biên bản. Trang HTML mở trong trình duyệt; chọn In / Lưu PDF để giao cho khách.
- Biên bản phản ánh trạng thái kiểm tra tại thời điểm xuất, chỉ hiện 5 ký tự cuối key. Sau khi kích hoạt hoặc cập nhật mẫu, hãy xuất lại biên bản.
- Xác nhận cho khách lẻ và Xác nhận cho công ty là hai mẫu riêng về việc cung cấp / bàn giao phần mềm để đơn vị cung cấp ký. Nhập khách hàng, chọn đúng phần mềm đã bàn giao rồi xuất HTML và In / Lưu PDF.
- Mẫu công ty dùng kèm hóa đơn / chứng từ đã cấp; mã số thuế và số chứng từ đều tuỳ chọn khi kỹ thuật viên không có thông tin. Xác nhận chỉ ghi 5 ký tự cuối key, không lưu dữ liệu khách vào cấu hình dùng chung.

## Tải / cài Office
- Chọn đúng sản phẩm, ngôn ngữ và 32 / 64-bit. Có thể bỏ trống key để nhập sau trong Word.
- Tải về kho một lần rồi dùng Cài từ kho cho các máy khác, hoặc chọn Cài trực tiếp khi có mạng.
- Gỡ / dọn Office có bảng chọn từng key. Mặc định không chọn gì; key không chọn được giữ lại. Lưu tài liệu và đóng Office trước khi xác nhận xoá / gỡ.
- Nếu cần giữ Retail, không tích key Retail. Chọn key dùng thử chỉ chọn Grace / Trial được nhận diện rõ.

## Cài Windows
- Trang tải Microsoft mở nơi tải ISO chính thức. Chọn ISO để công cụ kiểm tra và mở Windows Setup.
- Tạo USB Windows mở Media Creation Tool để bạn chọn USB. Dữ liệu trên USB được chọn sẽ bị xoá.
- Chỉ dọn Windows.old sau khi đã kiểm tra máy và dữ liệu; xoá thư mục này sẽ bỏ khả năng quay lại bản Windows cũ.

## Cài ứng dụng
- Quản lý ứng dụng cho phép thêm / sửa / xoá mục bổ sung: nhập ID WinGet hoặc chọn bộ cài EXE / MSI và tham số tuỳ chọn. Chỉ lưu ở tài khoản Windows trên máy này, không đồng bộ hoặc đẩy lên repo.
- Tích các ứng dụng cần cài rồi bấm Cài ứng dụng đã chọn. Giữ app mở trong lúc các mục được xử lý lần lượt.
- UltraViewer dùng bộ cài tiếng Việt 6.6.133 chính thức; có kiểm tra chữ ký và phiên bản. Bản đã cài hoặc đang chạy được giữ để tránh ngắt hỗ trợ.
- Các ứng dụng khác dùng WinGet. Nếu thiếu WinGet, mở Hướng dẫn WinGet để cài App Installer.
- Bảng Kết quả và nút Xem nhật ký giúp xác định ứng dụng đã cài, đã có sẵn hoặc đang gặp lỗi.

- Với WinRAR, sau cài hoặc khi WinGet báo đã có, app mở WinRAR lần đầu để hoàn tất thiết lập theo tài khoản. Hoàn tất thông báo trong WinRAR nếu có, rồi thử lại menu chuột phải trên tệp / thư mục. App không tự khẳng định menu đã xuất hiện chỉ vì mở ứng dụng thành công.
- Nếu menu WinRAR vẫn thiếu: mở WinRAR bằng quyền Administrator → Options → Settings → Integration, bật Integrate WinRAR into shell và chọn các mục trong Context menu items. App giữ nguyên WinRAR đang chạy và không ép cài lại phần mềm đã có.
- Foxit Reader bản mới không kèm máy in ảo Foxit PDF Printer như bản Reader cũ. App kiểm tra riêng các hàng đợi máy in PDF sau cài Reader và ghi tên / driver / cổng in vào nhật ký; báo đã cài Reader không có nghĩa đã cài máy in PDF. Microsoft Print to PDF là tính năng riêng của Windows; Foxit PDF Printer cần bộ Foxit có thành phần tạo PDF tương ứng.

## Cập nhật / khôi phục
- Chấm đỏ trên nút Cập nhật báo có bản mới. App đọc số phiên bản trong nền khi mở và định kỳ, không tự tải hoặc chen thông báo. Nếu mạng lỗi sẽ thử lại sau 1 phút; bấm Làm mới để yêu cầu kiểm tra ngay.
- Bấm Kiểm tra cập nhật, Tải bản cập nhật rồi Cài đặt bản cập nhật. Nút Cập nhật trên đầu app gọi lại cửa sổ đang bị khuất.
- Khi hiện Hoàn tất, đọc kết quả rồi bấm Đóng và mở ứng dụng. Nút X chỉ đóng updater; app không tự mở chen lên.
- Cài từ tệp dùng gói ZIP khi cần cập nhật offline. Lịch sử cập nhật cho biết các lần cập nhật trên máy này.
- Khôi phục bản trước dùng bản sao lưu trong .updates. Giữ thư mục này nếu còn muốn quay lại; cấu hình, logo, biên bản, kho Office, ODT, nhật ký và Reinstall được giữ.
- Có gì mới hiển thị nội dung từng phiên bản ngay trong app.

## Liên hệ / góp ý
- Zalo: 0976852096. Email: vienkendo@gmail.com. Dùng liên kết ở cuối cửa sổ để mở hoặc bấm Sao chép liên hệ.
- Khi góp ý / báo lỗi, ghi phiên bản app, phiên bản Windows và bước vừa thao tác; kèm ảnh hoặc nhật ký nếu có.
- Che key đầy đủ và thông tin riêng tư của khách trước khi gửi ảnh / nhật ký. Không cần gửi mật khẩu máy khách.

## Fix Driver
- Dùng chung cho mọi máy / mainboard, không cần profile. Quét, Catalog, cài CAB / INF và kho USB / NAS hoạt động độc lập với profile; chỉ áp gợi ý và tinh chỉnh riêng nếu nhận diện khớp.
- Mở Fix Driver ở menu bên trái. Quét liệt kê toàn bộ thiết bị có mã lỗi, toàn bộ Hardware ID và InstanceId. Chọn thiết bị rồi mở từng link Catalog hoặc Copy Hardware ID.
- Tải CAB bằng trình duyệt từ nguồn chính thức, chọn Chọn CAB và cài. Hoặc giải nén trước và chọn thư mục INF. Xác nhận bằng nút bấm; log ghi đầy đủ kết quả expand / pnputil. Sau cài tự dò phần cứng và đợi 3 giây rồi quét lại; nếu có thiết bị con mới, tiếp tục tải gói phù hợp.
- Cài từ kho USB / NAS tìm INF chứa Hardware ID khớp, ưu tiên thứ tự và phiên bản trong profile, tối đa 4 vòng. Không đưa driver vào thư mục chương trình để phát hành. Nút dừng chỉ dừng giữa các gói; không ngắt cài đang chạy.
- Profile SingPC chỉ khớp Manufacturer SingPC, Model I5-12450H, BIOS 5.32. Cài Serial IO trước OED, rồi thiết bị con SST; giữ nhánh SST 10.29.0.x khớp BUS. Không ép hdaudbus lên SST BUS.
- Disable chỉ bật cho thiết bị lỗi có Hardware ID được khai báo và khớp profile. Chọn thiết bị, xem cảnh báo mất tính năng, xác nhận riêng. Thiết bị chỉ có tên BT LE Sideband / Detection Verification chưa có ID được xác minh nên không có nút disable theo tên.
- Chỉnh nguồn là bước tuỳ chọn: chọn từng mục, xem và xác nhận. Chỉ thay power scheme nguồn AC; USB/HID dùng WMI nếu hỗ trợ. Lỗi hoặc trường hợp không hỗ trợ được ghi rõ, không tính là thành công.
- Xuất báo cáo HTML để xem thông tin máy, trước / sau, lệnh đã chạy và các thiết bị còn lỗi kèm link. Dữ liệu nằm trong %LOCALAPPDATA%\TechMaster Deploy\DriverFix. Profile JSON nằm ở Profiles; sửa / thêm rồi mở lại module để nạp.
- Test trên máy lỗi: ghi nhận danh sách trước, cài một gói đúng ID, kiểm tra Device Manager và thiết bị con sau quét, xuất báo cáo, kiểm tra âm thanh / USB và khởi động lại chủ động nếu pnputil yêu cầu. Hướng dẫn đầy đủ ở FixClone/DriverFix.md.
