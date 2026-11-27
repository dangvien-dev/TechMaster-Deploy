# Hướng dẫn nhanh TechMaster Deploy

## Bắt đầu
- Khung thông báo xanh lam là thông tin / đang xử lý; vàng là bước cần kiểm tra tiếp; xanh lá là thao tác đã được xác nhận; đỏ là lỗi. Với UltraViewer, đã reset vẫn cần mở UltraViewer và bấm Kiểm tra ID mới để xác nhận.
- Giữ nguyên cả thư mục TechMaster-Deploy, mở TechMaster Deploy.exe và chấp nhận yêu cầu quản trị.
- Menu bên trái chia theo chức năng: Tổng quan; CÀI ĐẶT (Cài Windows, Phần mềm, Bản quyền & biên bản); CẤU HÌNH (Tuỳ chỉnh Windows, Máy in, Mạng LAN & chia sẻ); TRIỂN KHAI (Clone hàng loạt); HỖ TRỢ (Chẩn đoán & sửa lỗi, Cập nhật). Nút Làm mới đọc lại trạng thái Windows / Office.
- Làm lô máy: chuẩn bị máy gốc và Sysprep ở Clone hàng loạt → Trên máy gốc; với từng máy đã clone, dùng Clone hàng loạt → Sau khi clone rồi các mục Tuỳ chỉnh Windows / Máy in khi cần.

## Tổng quan
- App mở ở Tổng quan: tên máy, hãng / model / số serial, Windows (bản, build, 32 / 64-bit), CPU, RAM, ổ hệ thống (dung lượng trống, SSD / HDD), địa chỉ IP và trạng thái bản quyền Windows / Office (5 ký tự cuối key). Mục nào Windows không trả lời được ghi "không đọc được", các mục khác vẫn hiện.
- Đọc lại để cập nhật thông tin; Sao chép thông tin để dán vào phiếu / tin nhắn khi báo giá, bàn giao. Các ô Làm nhanh mở thẳng nhóm chức năng tương ứng.
- Chạy TechMaster trên máy khác (không cần USB): xem mục Chạy TechMaster trên máy khác.

## Cài Windows
- Trang tải Microsoft mở nơi tải ISO chính thức. Chọn ISO để công cụ kiểm tra và mở Windows Setup.
- Tạo USB Windows mở Media Creation Tool để bạn chọn USB. Dữ liệu trên USB được chọn sẽ bị xoá.
- Paint trên Microsoft Store: trong tab Cài Windows, bấm để mở trang Paint chính thức rồi chọn Get / Cài đặt trong Store. Nếu Store đã bị gỡ hoặc chặn bởi chính sách, cần khôi phục Store / dùng bản Windows đầy đủ trước; app không tự báo đã cài.
- Dọn Windows.old… kiểm tra thư mục trên ổ cài Windows rồi mở Disk Cleanup với quyền quản trị. Chọn Clean up system files / Dọn tệp hệ thống → Previous Windows installation(s); kiểm tra các mục khác như Downloads trước khi xoá. Chỉ dọn sau khi đã giữ dữ liệu cần thiết; xoá sẽ bỏ khả năng quay lại bản Windows cũ. Đóng công cụ để app kiểm tra Windows.old còn hay đã mất. Nếu công cụ không liệt kê bản cài trước, Windows chưa nhận diện thư mục theo mục dọn này.

## Phần mềm
- Chọn đúng sản phẩm, ngôn ngữ và 32 / 64-bit. Có thể bỏ trống key để nhập sau trong Word.
- Tải về kho một lần rồi dùng Cài từ kho cho các máy khác, hoặc chọn Cài trực tiếp khi có mạng.
- Gỡ Office… mở phần gỡ bộ Office có bảng chọn từng key. Mặc định không chọn gì; key không chọn được giữ lại. Lưu tài liệu và đóng Office trước khi xác nhận xoá / gỡ.
- Phần dọn key dùng tạm nằm ở Bản quyền & biên bản → Kích hoạt Office → Key dùng tạm Office…. Nếu cần giữ Retail, không tích key Retail. Chọn key dùng thử chỉ chọn Grace / Trial được nhận diện rõ.
- Quản lý ứng dụng cho phép thêm / sửa / xoá mục bổ sung: nhập ID WinGet hoặc chọn bộ cài EXE / MSI và tham số tuỳ chọn. Chỉ lưu ở tài khoản Windows trên máy này, không đồng bộ hoặc đẩy lên repo.
- Tích các ứng dụng cần cài rồi bấm Cài ứng dụng đã chọn. Giữ app mở trong lúc các mục được xử lý lần lượt.
- UltraViewer dùng bộ cài tiếng Việt 6.6.133 chính thức; có kiểm tra chữ ký và phiên bản. Bản đã cài hoặc đang chạy được giữ để tránh ngắt hỗ trợ.
- Các ứng dụng khác dùng WinGet. Nếu thiếu WinGet, mở Hướng dẫn WinGet để cài App Installer.
- Bảng Kết quả và nút Xem nhật ký giúp xác định ứng dụng đã cài, đã có sẵn hoặc đang gặp lỗi.
- Với WinRAR, sau cài hoặc khi WinGet báo đã có, app mở WinRAR lần đầu để hoàn tất thiết lập theo tài khoản. Hoàn tất thông báo trong WinRAR nếu có, rồi thử lại menu chuột phải trên tệp / thư mục. App không tự khẳng định menu đã xuất hiện chỉ vì mở ứng dụng thành công.
- Nếu menu WinRAR vẫn thiếu: mở WinRAR bằng quyền Administrator → Options → Settings → Integration, bật Integrate WinRAR into shell và chọn các mục trong Context menu items. App giữ nguyên WinRAR đang chạy và không ép cài lại phần mềm đã có.
- Foxit Reader bản mới không kèm máy in ảo Foxit PDF Printer như bản Reader cũ. App kiểm tra riêng các hàng đợi máy in PDF sau cài Reader và ghi tên / driver / cổng in vào nhật ký; báo đã cài Reader không có nghĩa đã cài máy in PDF. Microsoft Print to PDF là tính năng riêng của Windows; Foxit PDF Printer cần bộ Foxit có thành phần tạo PDF tương ứng.

## Bản quyền & biên bản
- Khi có khách theo dõi, có thể nhập key trực tiếp trong Windows Settings → System → Activation hoặc Word → File → Account.
- Trong TechMaster, chọn Windows hoặc Office để kiểm tra và kích hoạt bằng key hợp lệ. Nếu online chưa thành công, công cụ hướng dẫn dùng portal Microsoft.
- Quét QR 1 bằng điện thoại cùng Wi-Fi/LAN, bấm Sao chép Installation ID rồi Mở portal Microsoft. Lấy Confirmation ID 48 số trên portal.
- Quay lại trang điện thoại hoặc quét QR 2, dán mã rồi bấm Gửi về máy tính. Cửa sổ QR trên máy tính sẽ đóng sau khi nhận mã.
- Key cài đặt chung Windows mở cửa sổ kiểm tra / dọn riêng; lựa chọn dọn trong Sysprep mặc định tắt, chỉ bật sau khi đã kiểm tra; chỉ dọn key Pro …3V66T chưa kích hoạt đã xác minh. Có biên nhận và nút Hoàn tác; không ghi đè key mới đã nhập.
- Trước khi lấy Installation ID, đối chiếu 5 ký tự cuối key trong hộp xác nhận. App ưu tiên key riêng, đọc lại IID và kiểm tra lần nữa trước khi nạp CID. Thay key hoặc IID sẽ dừng mã cũ; chạy lại để lấy QR mới. Key chung chỉ được thử online để nhận bản quyền số, không dùng để lấy QR offline.
- Key dùng tạm Office nằm ở Bản quyền & biên bản → Kích hoạt Office, cạnh nút kích hoạt và portal. Mở để xem danh sách, bấm Chọn key dùng thử, kiểm tra các key được đánh dấu rồi Xoá key đã chọn. Mặc định không chọn key nào; key không chọn được giữ. Cửa sổ này chỉ xử lý key và không có nút gỡ bộ Office.
- Office chưa nhập key hoặc chỉ có SKU Grace / Trial sẽ hiện hướng dẫn nhập key trong Word hoặc đăng nhập Microsoft 365.
- Kiểm tra lại màn hình Activation hoặc Product Activated của Microsoft trước khi bàn giao. Trạng thái kích hoạt không tự chứng minh nguồn gốc giấy phép.
- Bản chia sẻ mới để trống thông tin đơn vị và không kèm logo công ty. Xoá thông tin đơn vị / logo giúp dọn cấu hình đang lưu trước khi chuyển cho bên khác; biên bản đã xuất vẫn được giữ.
- Nhập hoặc sửa thông tin đơn vị / kỹ thuật viên rồi bấm Lưu thông tin để dùng cho lần sau; trường xoá trắng cũng được lưu. Tên khách hàng dùng cho biên bản đang lập.
- Nhập riêng Khách hàng / người nhận, Đơn vị / công ty khách hàng và Địa chỉ khách hàng. Các trường khách được đưa vào biên bản và điền sẵn trong mẫu xác nhận; nút Lưu thông tin vẫn lưu thông tin bên cung cấp, không lưu hồ sơ khách vào cấu hình dùng chung.
- Chọn logo được lưu ngay. Xoá logo chỉ xoá ảnh logo đang lưu, giữ thông tin đơn vị và biên bản đã xuất.
- Bấm Xuất biên bản. Trang HTML mở trong trình duyệt; chọn In / Lưu PDF để giao cho khách.
- Biên bản phản ánh trạng thái kiểm tra tại thời điểm xuất, chỉ hiện 5 ký tự cuối key. Sau khi kích hoạt hoặc cập nhật mẫu, hãy xuất lại biên bản.
- Xác nhận cho khách lẻ và Xác nhận cho công ty là hai mẫu riêng về việc cung cấp / bàn giao phần mềm để đơn vị cung cấp ký. Nhập khách hàng, chọn đúng phần mềm đã bàn giao rồi xuất HTML và In / Lưu PDF.
- Mẫu công ty dùng kèm hóa đơn / chứng từ đã cấp; mã số thuế và số chứng từ đều tuỳ chọn khi kỹ thuật viên không có thông tin. Xác nhận chỉ ghi 5 ký tự cuối key, không lưu dữ liệu khách vào cấu hình dùng chung.

## Tuỳ chỉnh Windows
- Chỉnh ngày / số đặt ngày ngắn dd/MM/yyyy, thập phân dấu phẩy và phân nhóm dấu chấm; giữ vùng và bàn phím.
- Bàn phím / EVKey cho phép chỉ dùng kiểu nhập US, có sao lưu và khôi phục.
- Menu chuột phải có hai lựa chọn Kiểu Windows 10 và Khôi phục Windows 11. Cấu hình theo tài khoản đang chạy app; kiểm tra đúng tài khoản nếu mở bằng thông tin quản trị khác. App lưu trạng thái trước thay đổi, hỏi riêng trước khi khởi động lại Explorer; có thể chọn Để sau và đăng nhập lại. Các bản Windows mới có thể không áp dụng tuỳ chỉnh menu truyền thống.
- Menu truyền thống: nút Kiểu Windows 10 chỉ lưu cấu hình rồi yêu cầu khởi động lại Explorer để kiểm tra. Từ mốc build 26200.9974, Windows có thể bỏ qua key; cùng build vẫn có thể khác vì triển khai tính năng theo đợt. App vẫn ghi key và chỉ báo đã lưu cấu hình, không khẳng định menu đã đổi. Nếu chưa đổi, giữ Shift + chuột phải để mở menu đầy đủ; nếu Customize menu có Arrange primary actions inline thì bật thủ công. App chưa tự áp registry của toggle này. Khôi phục Windows 11 gỡ tuỳ chỉnh đã lưu.
- Trình duyệt / PDF mặc định: bấm Trình duyệt / PDF mặc định… (cửa sổ riêng, chỉ có trình duyệt và PDF), chọn ứng dụng đã cài → Chọn làm mặc định → xác nhận Set default trong Cài đặt Windows (PDF chọn .pdf) → quay lại Kiểm tra lại. Với trình duyệt, app kiểm tra cả HTTP và HTTPS. Windows 10 / bản cũ có thể mở trang chung; tìm ứng dụng trong Ứng dụng mặc định. Nếu thiếu app trong danh sách, cài app rồi kiểm tra lại; không tự cài thêm trình duyệt hoặc trình đọc PDF.

## Máy in
- Máy in mặc định / A4…: chọn một máy in, tích Đặt A4 / Đặt máy in mặc định rồi bấm Áp dụng máy in. Mặc định thuộc tài khoản đang chạy app; nếu nâng quyền bằng tài khoản quản trị khác thì thuộc tài khoản đó. Khi đặt mặc định, app tắt Windows tự chọn máy in dùng gần nhất. A4 là thiết lập của hàng đợi, có thể ảnh hưởng người cùng dùng máy in; tài liệu Word / Excel cũ có thể giữ khổ riêng.
- Dọn máy in không kết nối: bấm Dọn máy in không kết nối… (cửa sổ riêng, chỉ có phần gỡ máy in; áp dụng cho cả máy). Gỡ = xoá hàng đợi in và thiết bị như Remove device trong Devices and Printers; driver giữ nguyên, cắm lại máy in USB là Windows nhận lại. Danh sách gồm máy in USB / mạng Windows đang báo Offline (chọn sẵn máy in USB; máy in mạng, mặc định, đang chia sẻ phải tự tích) và thiết bị máy in còn sót không còn hàng đợi. Máy in USB đang tắt nguồn cũng báo Offline: bật máy rồi Kiểm tra lại trước khi gỡ. Bấm Gỡ máy in đã chọn và xác nhận; thẻ hiện tiến trình và kết quả từng máy. Nếu Windows chưa xoá xong (thường do cửa sổ Devices and Printers đang mở), app tự khởi động lại Print Spooler khi tuỳ chọn đang bật; tắt tuỳ chọn thì đóng cửa sổ đó rồi bấm Gỡ lại.
- Scan vào thư mục / chia sẻ máy in qua mạng: tạo tài khoản scan / print và chia sẻ thư mục ở Mạng LAN & chia sẻ.

## Mạng LAN & chia sẻ
- Tài khoản chia sẻ LAN: bấm Tài khoản chia sẻ LAN… trong Mạng LAN & chia sẻ. Nhập mật khẩu hai lần cho scan (máy photocopy scan vào thư mục), share (người dùng mở thư mục) hoặc print (máy in chia sẻ) rồi bấm Tạo / cập nhật. Tài khoản không đăng nhập tại máy hay Remote Desktop được và ẩn khỏi màn hình đăng nhập. Tài khoản cùng tên có sẵn không do app tạo sẽ không bị đổi.
- Chia sẻ thư mục (máy chia sẻ): bấm Chia sẻ thư mục…, Chọn thư mục…, kiểm tra tên chia sẻ, chọn Chỉ đọc / Đọc & ghi cho từng tài khoản rồi bấm Chia sẻ / cập nhật quyền. Giữ tích mở tường lửa (chỉ mạng nội bộ). Nếu mạng đang Public và đây là mạng của cơ quan, tích chuyển sang Private. Kết quả ghi đường dẫn \\TÊN-MÁY\Tên và \\IP\Tên để nhập vào máy photocopy / máy khác. Scan: cấp Đọc & ghi cho scan; người dùng chỉ xem thì cấp Chỉ đọc cho share.
- Kết nối thư mục chia sẻ (máy người dùng): mở app trên máy người dùng bằng chính tài khoản Windows của họ, bấm Kết nối thư mục chia sẻ…, nhập \\TÊN-MÁY\Tên, tài khoản (share) và mật khẩu một lần, bấm Kiểm tra & lưu. App thử đăng nhập, lưu vào Credential Manager và tạo lối tắt; người dùng mở lối tắt là vào. Đổi mật khẩu tài khoản trên máy chia sẻ thì làm lại bước này trên từng máy. Nếu máy người dùng dùng tài khoản thường (không quản trị), để người dùng tự mở \\TÊN-MÁY\Tên một lần và tích Ghi nhớ thông tin đăng nhập.

## Chạy TechMaster trên máy khác
- Qua mạng LAN (máy kia không cần Internet): trên máy đang chạy TechMaster, bấm Chia sẻ TechMaster qua LAN…, chọn tài khoản máy kia dùng (tài khoản đang dùng hoặc tài khoản LAN share) rồi Chia sẻ TechMaster. App chia sẻ thư mục chương trình thành \\TÊN-MÁY\TechMaster$ chỉ đọc, không cho Everyone / Guest, mở tường lửa chỉ trong LAN.
- Trên máy kia: mở File Explorer (hoặc Windows + R), dán \\TÊN-MÁY\TechMaster$\App\Chay-Tu-Mang.bat (hoặc \\IP\TechMaster$\App\Chay-Tu-Mang.bat), đăng nhập TÊN-MÁY\tài khoản và mật khẩu; chọn Run nếu Windows hỏi. App chép các tệp khác bản đang có vào thư mục tạm, kiểm tra từng tệp theo danh sách tệp của app (update-package.json của bản cài, hoặc update-source.json nếu chia sẻ từ mã nguồn), rồi hỏi quyền quản trị để cài vào C:\TechMaster-Deploy và mở.
- Thư mục C:\TechMaster-Deploy chỉ Administrators / SYSTEM sửa được; người dùng thường chỉ đọc và chạy. Lần sau chạy lại Chay-Tu-Mang.bat chỉ chép phần thay đổi. Máy kia có bản mới hơn thì app mở bản đó. Xoá thư mục khi không còn dùng; bấm Ngừng chia sẻ trên máy chia sẻ khi xong việc.
- Qua Internet: trên máy kia mở PowerShell (Windows + X → Terminal / Windows PowerShell), dán lệnh irm https://dangvien-dev.github.io/tm.txt | iex rồi Enter (nút Sao chép lệnh ở Tổng quan / Mạng LAN & chia sẻ). Lệnh hỏi quyền quản trị, tải gói chính thức trên trang dangvien-dev.github.io, kiểm tra SHA256, cài vào C:\TechMaster-Deploy rồi mở; nếu máy đã có bản cài ở đó thì mở luôn và cập nhật bằng nút Cập nhật trong app.
- Báo lỗi SSL / TLS trên Windows cũ: chạy [Net.ServicePointManager]::SecurityProtocol=3072; irm https://dangvien-dev.github.io/tm.txt | iex. Chỉ dán lệnh từ đúng địa chỉ trên.

## Clone hàng loạt
- Cài phần mềm, đặt font, khổ giấy và lề Word theo nhu cầu rồi đóng các ứng dụng Office.
- Bấm Chuẩn bị và Sysprep. Kiểm tra Screen Snipping / Always và sao lưu, dọn icon Word / Excel trùng.
- Chọn dọn key cài đặt chung Windows để kiểm tra key Pro …3V66T chưa kích hoạt, có đối chiếu key từ hệ thống. Windows đang kích hoạt, key khác và trường hợp không xác minh được đều được giữ. Nếu Sysprep lỗi, key chung có thể được khôi phục theo biên nhận.
- Giữ lựa chọn dọn key Grace / Trial nếu cần; key Retail và thiết lập Word được giữ. Xem danh sách trước khi tự chọn thêm key cần xoá.
- Chuẩn bị UltraViewer 6.6.133 sẽ ngắt kết nối ở bước cuối; thao tác tại máy hoặc dùng kênh hỗ trợ khác. Nếu Sysprep lỗi, công cụ khôi phục định danh máy gốc.
- Sau khi Sysprep tắt máy, dùng USB để clone ổ. Không bật lại máy gốc trước khi tạo ảnh.
- Ảnh được chuẩn bị bằng công cụ mới sẽ tự chạy xử lý lần đăng nhập đầu. Có thể mở Xử lý trùng lặp để xem và chọn lại các thao tác khi cần.
- Reset ID UltraViewer có sao lưu. Chỉ reset khi cần, sau đó mở UltraViewer và Kiểm tra ID mới; thao tác này ngắt kết nối hỗ trợ.
- Lịch sử reset UltraViewer tự đọc lại khi mở cửa sổ, kể cả bản sao lưu từ phiên bản cũ trên đúng máy. Xem thời gian reset / kiểm tra / khôi phục và đường dẫn sao lưu; không reset lại chỉ vì đã đóng app. Lịch sử nằm trong `%ProgramData%\TechMaster Deploy\UltraViewer Backups`, cùng bản sao lưu có giới hạn quyền truy cập. Sao chép app sang máy khác không mang theo lịch sử này.
- Kiểm tra Desktop và phím chụp để giữ một icon Word / Excel dùng chung và chọn Screen Snipping cho Windows + Shift + S.

## Chẩn đoán & sửa lỗi
- Dùng khi khách báo sự cố, trên bất kỳ máy nào; không phải bước bắt buộc sau khi clone. Tab gồm Fix Driver (thiết bị thiếu / lỗi driver) và Chẩn đoán báo virus.
- Chẩn đoán báo virus mặc định chạy nhẹ (chỉ .exe); tích Quét sâu khi máy rảnh. Nếu Defender đang quét, app hỏi trước; nên để lượt quét xong rồi mới chẩn đoán.
- Chẩn đoán báo virus: bấm nút rồi theo dõi thanh tiến trình và bước đang chạy ngay trong thẻ (thường 1–2 phút, phần chữ ký số Office / Zalo lâu nhất). Xong có thể mở lại bằng Xem kết quả gần nhất. Dùng khi Word, Zalo… bị AV báo virus và không mở được. Đọc phần KẾT LUẬN SƠ BỘ trước: NGHIÊM TRỌNG là dấu hiệu virus lây file .exe → rút mạng, quét offline, cài lại ứng dụng; KHẢ NĂNG CAO là công cụ kích hoạt bên ngoài bị chặn; CÓ THỂ BÁO NHẦM là phát hiện heuristic trên tệp có chữ ký hợp lệ. Kaspersky không ghi đủ tên mối đe dọa vào nhật ký Windows trên mọi bản; mở Báo cáo / Vùng cách ly của Kaspersky để lấy tên chính xác. Công cụ không khôi phục cách ly, không thêm ngoại lệ. Trong danh sách phát hiện: ĐÃ CHẠY nghĩa là mã độc đã thực thi (nên cài lại Windows và đổi mật khẩu từ máy khác); [CÒN TRÊN Ổ] là tệp vẫn còn, cần xoá và tải lại từ trang hãng; ĐANG ĐƯỢC CHO PHÉP phải bỏ trong Windows Security → Allowed threats. Dòng Theo ổ cho biết USB / ổ ngoài nào cần quét.
- Sửa lỗi…: hiện sau khi chẩn đoán. Mục khuyến nghị đã chọn sẵn; bấm Chạy mục đã chọn, xác nhận, theo dõi tiến độ và nhật ký trong cửa sổ. Tệp còn sót không bị xoá mà chuyển vào <ổ>\_CachLy_Virus kèm DanhSach.tsv; xoá thư mục này khi đã tải lại bộ cài sạch. Quét offline khởi động lại máy nên luôn hỏi riêng; không chạy khi đang điều khiển từ xa nếu không có cách kết nối lại. Xong thì bấm Chẩn đoán lại để xác nhận.

## Fix Driver
- Kết quả quét hiện tổng thiết bị, Code 0, lỗi và trạng thái chưa rõ. Danh sách trống kèm số đã đọc lớn hơn 0 / 0 lỗi nghĩa là Windows chưa báo thiết bị lỗi trong lần quét đó. Bật Hiện tất cả thiết bị để xem danh sách đã đọc và đối chiếu bằng Mở Device Manager. Nếu Windows không trả thiết bị nào, app báo lỗi đọc dữ liệu; mã ? chưa được tính là hoạt động. Module không tìm bản driver mới hơn cho thiết bị đang hoạt động.
- Dùng chung cho mọi máy / mainboard, không cần profile. Quét, Catalog, cài CAB / INF và kho USB / NAS hoạt động độc lập với profile; chỉ áp gợi ý và tinh chỉnh riêng nếu nhận diện khớp.
- Mở tab Chẩn đoán & sửa lỗi ở menu bên trái → Mở Fix Driver. Quét liệt kê toàn bộ thiết bị có mã lỗi, toàn bộ Hardware ID và InstanceId. Chọn thiết bị rồi mở từng link Catalog hoặc Copy Hardware ID. Với máy in / MFP của hãng có trong bảng (Canon, HP, Epson, Brother, Kyocera, Ricoh, Xerox, Lexmark, OKI), Catalog theo VID/PID thường trống nên app hiện nút Mở trang driver <hãng> và link tìm theo tên model; tải bộ cài đúng model và Windows, chạy khi máy in đang cắm rồi Quét lại.
- Tải CAB bằng trình duyệt từ nguồn chính thức, chọn Chọn CAB và cài. Hoặc giải nén trước và chọn thư mục INF. Xác nhận bằng nút bấm; log ghi đầy đủ kết quả expand / pnputil. Sau cài tự dò phần cứng và đợi 3 giây rồi quét lại; nếu có thiết bị con mới, tiếp tục tải gói phù hợp.
- Cài từ kho USB / NAS tìm INF chứa Hardware ID khớp, ưu tiên thứ tự và phiên bản trong profile, tối đa 4 vòng. Không đưa driver vào thư mục chương trình để phát hành. Nút dừng chỉ dừng giữa các gói; không ngắt cài đang chạy.
- Profile SingPC chỉ khớp Manufacturer SingPC, Model I5-12450H, BIOS 5.32. Cài Serial IO trước OED, rồi thiết bị con SST; giữ nhánh SST 10.29.0.x khớp BUS. Không ép hdaudbus lên SST BUS.
- Disable chỉ bật cho thiết bị lỗi có Hardware ID được khai báo và khớp profile. Chọn thiết bị, xem cảnh báo mất tính năng, xác nhận riêng. Thiết bị chỉ có tên BT LE Sideband / Detection Verification chưa có ID được xác minh nên không có nút disable theo tên.
- Chỉnh nguồn là bước tuỳ chọn: chọn từng mục, xem và xác nhận. Chỉ thay power scheme nguồn AC; USB/HID dùng WMI nếu hỗ trợ. Lỗi hoặc trường hợp không hỗ trợ được ghi rõ, không tính là thành công.
- Xuất báo cáo HTML để xem thông tin máy, trước / sau, lệnh đã chạy và các thiết bị còn lỗi kèm link. Dữ liệu nằm trong %LOCALAPPDATA%\TechMaster Deploy\DriverFix. Profile JSON nằm ở Profiles; sửa / thêm rồi mở lại module để nạp.
- Test trên máy lỗi: ghi nhận danh sách trước, cài một gói đúng ID, kiểm tra Device Manager và thiết bị con sau quét, xuất báo cáo, kiểm tra âm thanh / USB và khởi động lại chủ động nếu pnputil yêu cầu. Hướng dẫn đầy đủ ở FixClone/DriverFix.md.

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
