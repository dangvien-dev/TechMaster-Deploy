# Có gì mới trong TechMaster Deploy?

## 2.2.25.0 — 27/11/2026

- Tách cửa sổ Thiết lập mặc định theo nút đã bấm, tránh nhầm chức năng khi gỡ máy in: **Máy in mặc định / A4…** chỉ có phần máy in mặc định và khổ giấy; **Dọn máy in không kết nối…** chỉ có danh sách gỡ máy in (ghi rõ thao tác áp dụng cho cả máy, driver được giữ); **Trình duyệt / PDF mặc định…** chỉ có trình duyệt, PDF và nút Ứng dụng mặc định trong Windows. Mỗi cửa sổ có tiêu đề riêng và chỉ báo “chưa đọc được” cho phần đang hiện.

## 2.2.24.0 — 27/11/2026

- Menu chia lại theo chức năng, có nhóm: **Tổng quan**; **CÀI ĐẶT** (Cài Windows, Phần mềm, Bản quyền & biên bản); **CẤU HÌNH** (Tuỳ chỉnh Windows, Máy in, Mạng LAN & chia sẻ); **TRIỂN KHAI** (Clone hàng loạt); **HỖ TRỢ** (Chẩn đoán & sửa lỗi, Cập nhật). Office và Cài ứng dụng gộp thành **Phần mềm**; Kích hoạt và Biên bản gộp thành **Bản quyền & biên bản**; Máy gốc / Sysprep và Sau khi clone gộp thành **Clone hàng loạt** (hai phần Trên máy gốc / Sau khi clone). Mọi nút cũ giữ nguyên chức năng.
- App mở ở trang **Tổng quan** mới: tên máy, hãng / model / số serial, Windows (bản, build, 32 / 64-bit), CPU, RAM, ổ hệ thống (dung lượng trống, SSD / HDD), địa chỉ IP, bản quyền Windows / Office kèm 5 ký tự cuối key. Mỗi mục đọc riêng: mục nào Windows không trả lời được ghi rõ, các mục khác vẫn hiện. Có **Sao chép thông tin**, các ô **Làm nhanh** mở thẳng từng nhóm chức năng, phiên bản và Có gì mới.
- **Trình duyệt / PDF mặc định…** (Tuỳ chỉnh Windows) và **Máy in mặc định / A4…** (Máy in) là hai nút riêng (2.2.25.0 tách thành cửa sổ riêng).
- Thêm **Chạy TechMaster trên máy khác, không cần USB** (Tổng quan và Mạng LAN & chia sẻ):
  - **Qua LAN:** **Chia sẻ TechMaster qua LAN…** chia sẻ thư mục chương trình thành `\\TÊN-MÁY\TechMaster$` (ẩn, **chỉ đọc**) cho một tài khoản (tài khoản đang dùng hoặc `share`), không Everyone / Guest; dùng chung luật tường lửa LAN và lựa chọn chuyển mạng Public → Private. Trên máy kia mở `\\TÊN-MÁY\TechMaster$\App\Chay-Tu-Mang.bat`: tệp được chép vào thư mục tạm và kiểm tra kích thước + Git blob hash theo `update-source.json`; bước cài với quyền quản trị là lệnh nhúng sẵn (không chạy script từ thư mục người dùng ghi được), khoá `C:\TechMaster-Deploy` (chủ sở hữu Administrators, chỉ Administrators / SYSTEM sửa, Users đọc và chạy), kiểm tra lại từng tệp và SHA256 của `TechMaster Deploy.exe` rồi mở app. Lần sau chỉ chép tệp thay đổi. Thư mục máy chia sẻ có tệp khác danh sách thì không chia sẻ; **Ngừng chia sẻ** gỡ cả quyền NTFS đã thêm.
  - **Qua Internet:** lệnh `irm https://dangvien-dev.github.io/tm.txt | iex` (nút **Sao chép lệnh**) xin quyền quản trị, tải gói ZIP đang công bố trên trang vào bộ nhớ, kiểm tra SHA256 theo `downloads/latest.json`, cài vào `C:\TechMaster-Deploy` đã khoá rồi mở.
  - Bản có sẵn trên máy chỉ được mở nguyên trạng khi nằm trong thư mục đã khoá; thư mục ai cũng ghi được thì cài lại từ tệp đã kiểm tra.
- Hướng dẫn nhanh sắp lại theo menu mới, thêm mục Tổng quan và Chạy TechMaster trên máy khác.

## 2.2.23.0 — 27/11/2026

- Thêm **Chia sẻ thư mục…** (máy chia sẻ): bấm **Chọn thư mục…**, đặt tên chia sẻ (gợi ý tên không dấu), phân quyền **Không / Chỉ đọc / Đọc & ghi** cho từng tài khoản scan / share / print. Quyền áp cho cả quyền chia sẻ lẫn NTFS (thư mục con dùng chung); chỉ đổi phần của ba tài khoản này, quyền khác trên máy giữ nguyên. Thư mục đã chia sẻ được nạp lại tên và quyền hiện tại để sửa.
- Mật khẩu vẫn bắt buộc: không bao giờ mở cho Everyone / Guest; danh sách trong thư mục chỉ hiện mục người đó có quyền. Không cho chia sẻ thư mục hệ thống (ổ cài Windows, Windows, Program Files, ProgramData, cả thư mục người dùng), ổ USB / mạng; chia sẻ cả ổ dữ liệu thì có cảnh báo.
- Tường lửa: luật riêng của TechMaster (TCP 139, 445; UDP 137, 138), chỉ mạng Private / Domain và chỉ máy cùng dải mạng; không đổi luật có sẵn của Windows. Mạng đang Public được báo rõ và chỉ chuyển sang Private khi bạn tích. Bật dịch vụ Server nếu đang tắt. Đọc lại chia sẻ, NTFS, tường lửa trước khi báo; kết quả có đường dẫn theo tên máy và IP.
- Thêm **Kết nối thư mục chia sẻ…** (máy người dùng): nhập `\\TÊN-MÁY\TênChiaSẻ`, tài khoản và mật khẩu **một lần**. App thử đăng nhập trước, đúng mới lưu vào Windows Credential Manager của tài khoản đang dùng máy (mật khẩu cũ chỉ bị thay khi mật khẩu mới đúng), tạo lối tắt trên Desktop và tuỳ chọn gán ổ đĩa (hiện sau khi đăng nhập lại). Người dùng mở là vào, không phải nhập mật khẩu. Có nút xoá mật khẩu đã lưu. Từ chối lưu khi app đang chạy bằng tài khoản quản trị khác với người đang dùng máy.

## 2.2.22.0 — 27/11/2026

- Thêm **Sau khi clone → Tài khoản chia sẻ LAN**: tạo tài khoản theo chức năng **scan** (máy photocopy / máy scan lưu vào thư mục chia sẻ), **share** (chia sẻ file), **print** (chia sẻ máy in); mật khẩu do kỹ thuật viên nhập hai lần, gõ mật khẩu là tự tích tài khoản đó.
- Tài khoản chỉ đăng nhập qua mạng LAN: chặn đăng nhập tại máy, Remote Desktop, tác vụ và dịch vụ; ẩn khỏi màn hình đăng nhập; mật khẩu không hết hạn, người dùng không tự đổi; thuộc nhóm Users (xác định theo SID nên đúng với Windows tiếng Việt), không bao giờ là quản trị. Cửa sổ hiện tên đăng nhập dùng trên máy khác / máy photocopy (ví dụ `TÊN-MÁY\scan`).
- Tài khoản cùng tên có sẵn mà không do TechMaster tạo, hoặc đang thuộc Administrators, không bị thay đổi. Tài khoản TechMaster đã tạo trước đó được đặt mật khẩu mới, bật lại và bổ sung phần còn thiếu.
- Mỗi thiết lập được đọc lại từ Windows trước khi báo thành công; tài khoản mới tạo mà không khoá được đăng nhập trực tiếp sẽ bị xoá lại. Mật khẩu không ghi vào nhật ký và bị xoá khỏi cửa sổ sau mỗi lần thực hiện. App không tạo thư mục chia sẻ, không đổi quyền chia sẻ hay tường lửa.

## 2.2.21.0 — 27/11/2026

- **Dọn máy in không kết nối giờ gỡ cả thiết bị**, giống **Remove device** trong Devices and Printers, và giữ nguyên driver. Bản 2.2.20.0 chỉ xoá hàng đợi in nên máy in đã rút vẫn hiện trong Devices and Printers: cửa sổ này liệt kê theo thiết bị (container PnP), mà máy in USB đã rút còn các mục thiết bị ẩn (hàng đợi, USBPRINT, USB). App xoá các mục ẩn cùng container sau khi xoá hàng đợi, con trước cha. Thiết bị đang kết nối (kể cả chỉ một phần), container của chính máy tính và thiết bị máy in khác còn dùng không bao giờ bị xoá.
- Liệt kê thêm **thiết bị máy in còn sót**: không còn hàng đợi nhưng vẫn hiện trong Devices and Printers (ví dụ sau lần gỡ bằng 2.2.20.0), chọn sẵn để gỡ.
- Sửa báo **thành công sai**: Windows chỉ *đánh dấu chờ xoá* hàng đợi khi còn lệnh in hoặc cửa sổ Devices and Printers đang mở. App huỷ lệnh in chờ trước khi xoá, chờ Windows xoá thật, và báo riêng “chưa xoá xong”. Tuỳ chọn (bật sẵn) tự khởi động lại dịch vụ Print Spooler để hoàn tất, sau đó mới xoá thiết bị. Hàng đợi đang chờ xoá vẫn hiện trong danh sách để gỡ lại.
- **Hiện tiến trình ngay trong thẻ**: thanh tiến trình, “Đang gỡ 3/25: tên máy in — bước”, kết quả từng máy (✓ đã gỡ / ! chưa trọn / – bỏ qua / ✗ lỗi). Trước đây trạng thái chỉ hiện ở đầu cửa sổ, bị cuộn khuất nên trông như không có gì xảy ra.
- Sau khi gỡ, app đọc lại danh sách thiết bị: còn mục ẩn thì báo “gỡ chưa trọn”, không báo thành công.

## 2.2.20.0 — 27/11/2026

- Thêm **Dọn máy in không kết nối** trong **Thiết lập mặc định** (mở nhanh bằng nút **Dọn máy in không kết nối…** ở thẻ Máy in và ứng dụng mặc định). Danh sách gồm máy in USB / mạng mà Windows đang báo Offline: máy in đã rút cáp, hàng đợi “(Copy n)” cũ, máy in mạng ở nơi khác. Đọc cả trạng thái spooler lẫn cờ Use Printer Offline (`Win32_Printer.WorkOffline`).
- Máy in USB được chọn sẵn; máy in mạng, máy in mặc định và máy in đang chia sẻ phải tự tích. Có **Chọn tất cả / Bỏ chọn**; dấu tích được giữ khi bấm Kiểm tra lại.
- Máy in ảo (Microsoft Print to PDF, XPS, OneNote, Fax, cổng `FILE:` / `PORTPROMPT:` / `nul:`) và máy in trên cổng không nhận diện được không bao giờ có trong danh sách.
- Trước khi gỡ, app hỏi xác nhận kèm danh sách và cảnh báo (máy in mặc định, đang chia sẻ, còn lệnh in chờ, máy in mạng). Lúc gỡ, app đọc lại spooler: máy in vừa cắm lại / đã biến mất được bỏ qua và báo riêng. Gỡ đúng đối tượng hàng đợi (không dùng tên có ký tự `[ ]`), đọc lại sau khi gỡ, ghi nhật ký `PrinterCleanup-*.jsonl`. Chỉ xoá hàng đợi; driver và cổng giữ nguyên.

## 2.2.19.0 — 26/11/2026

- Fix Driver: với **máy in / MFP** của hãng có trong bảng VID (Canon, HP, Epson, Brother, Kyocera, Ricoh, Xerox, Lexmark, OKI), thay hai link Catalog theo VID/PID (thường không có kết quả cho máy in) bằng nút **Mở trang driver <hãng>** và hai link: tìm driver theo tên model giới hạn trong trang hãng, và trang hỗ trợ của hãng. Kèm ghi chú: chọn đúng model / Windows, tải bộ cài đầy đủ, chạy khi máy in đang cắm rồi Quét lại.
- Nhận diện máy in theo class Printer, ID `USBPRINT\` / `WSDPRINT\` / USB class 07 (đọc thêm Compatible ID) hoặc tên model (ví dụ `MF240 Series UFRII LT` Code 28 không có class). Hãng bán cả thiết bị khác (Canon, HP, Epson, Kyocera, Ricoh) chỉ được gợi ý khi có dấu hiệu máy in, nên bàn phím HP, webcam Ricoh hay điện thoại Samsung vẫn dùng link Catalog. Hãng chưa có trong bảng cũng quay về Catalog.
- Chỉ mở link do chương trình tạo: Catalog, tìm kiếm Google và trang hỗ trợ trong bảng hãng, luôn HTTPS. Báo cáo HTML dùng cùng bộ link. Thêm hãng mới bằng một dòng trong `Get-DriverFixPrinterVendors` (`FixClone/DriverFix.Core.ps1`).

## 2.2.18.0 — 26/11/2026

- Sửa lỗi báo virus **không còn chọn sẵn “Quét toàn bộ ổ D: / USB”**. Mục này ghi dung lượng đã dùng của ổ và cảnh báo ổ HDD lớn có thể quét hàng giờ, máy chậm / đơ: chỉ chạy khi không dùng máy.
- Nhận biết mọi lượt quét Defender đang chạy, kể cả quét riêng một ổ (trước đây chỉ thấy quét nhanh / toàn bộ), qua nhật ký Defender (bắt đầu / xong / dừng / lỗi theo Scan ID). Lượt quét bị cắt do tắt máy đột ngột không bị coi là đang chạy. Chẩn đoán và Sửa lỗi đều hỏi trước khi chạy chồng lên lượt quét đó.

## 2.2.17.0 — 26/11/2026

- Chẩn đoán báo virus mặc định chạy **chế độ nhẹ**: chỉ kiểm tra chữ ký .exe, không đọc hàng trăm .dll (mỗi lần đọc Defender lại quét tệp đó). Tích **Quét sâu** để kiểm tra cả .dll khi máy rảnh.
- Luồng chẩn đoán chạy ở mức ưu tiên thấp để Explorer và màn hình vẫn phản hồi.
- Trước khi chạy, nếu Defender đang quét nhanh / quét toàn bộ, app hỏi “Vẫn chạy (chế độ nhẹ)” hoặc “Để sau” thay vì chồng thêm tải lên ổ đĩa.
- Chỉ kiểm tra tệp còn trên ổ ở ổ trong máy / USB đang cắm; không chạm ổ mạng hoặc ổ đã rút (có thể treo chờ). Truy vấn danh sách ổ có giới hạn 10 giây.

## 2.2.16.0 — 26/11/2026

- Sửa lỗi báo virus: khi Defender đang có lượt quét khác (quét toàn bộ mở tay, quét định kỳ), mục quét chờ tối đa 15 phút rồi tự chạy, cửa sổ ghi rõ đang chờ lượt nào (ví dụ “chờ quét toàn bộ (từ 08:44) chạy xong…”). Quá thời gian thì báo lượt quét nào còn chạy và hướng dẫn chạy lại, thay cho lỗi tiếng Anh “A scan is already in progress”. Lỗi quét khác vẫn báo ngay.

## 2.2.15.0 — 26/11/2026

- Mã trạng thái 5 trong lịch sử phát hiện ghi **Đã cho phép lúc phát hiện (5)** thay vì “đang được cho phép”. Cờ **ĐANG ĐƯỢC CHO PHÉP** chỉ hiện khi mã mối đe dọa còn trong danh sách cho phép của Defender; tệp từng được cho phép mà vẫn còn trên ổ có cờ **ĐÃ CHO PHÉP, TỆP VẪN CÒN**. Dòng chi tiết không còn mâu thuẫn với phần kết luận.

## 2.2.14.0 — 26/11/2026

- Thêm **Sửa lỗi…** sau khi chẩn đoán báo virus. Danh sách lập từ kết quả chẩn đoán, mục khuyến nghị chọn sẵn: cập nhật định nghĩa Defender, gỡ mã mối đe dọa đang “Cho phép”, gỡ ngoại lệ Defender phủ cả ổ / thư mục hệ thống, tắt AppInit_DLLs (sao lưu giá trị cũ vào ProgramData), cách ly tệp còn sót, quét nhanh, quét riêng từng ổ có phát hiện (D:, USB…), quét toàn bộ máy và quét offline Microsoft Defender.
- Không xoá tệp: tệp còn sót được chuyển vào `<ổ>\_CachLy_Virus\<ngày giờ>`, đổi đuôi `.virus`, kèm `DanhSach.tsv` ghi đường dẫn gốc và SHA256. Thao tác chạy theo thứ tự cố định, mỗi mục kiểm tra lại sau khi chạy (định nghĩa mới, mã / ngoại lệ đã gỡ, AppInit đã tắt, tệp đã rời chỗ cũ) và ghi nhật ký trong `%LOCALAPPDATA%\TechMaster Deploy\AV Repair Logs`.
- Quét toàn bộ và quét offline không bao giờ chọn sẵn; quét offline (khởi động lại máy) hỏi xác nhận riêng và luôn chạy sau cùng. Khi Defender không phải AV chính, không chọn sẵn mục nào và ghi rõ lý do.
- Kết luận chẩn đoán tách **ĐANG có** dấu hiệu virus lây file với **ĐÃ TỪNG** nhiễm trong 30 ngày; bản ghi “Cho phép” cũ của tệp đã được xử lý chỉ còn là lưu ý, không báo gấp. Thêm dòng **[ĐÃ XỬ LÝ]** khi không còn tệp nào từng bị phát hiện trên ổ.

## 2.2.13.0 — 26/11/2026

- Chẩn đoán báo virus hiện tiến độ ngay trong thẻ: thanh tiến trình, bước đang chạy (1/6 → 6/6), số tệp đã kiểm tra chữ ký (ví dụ 120 / 383) và thời gian đã chạy. Nút đổi thành “Đang chẩn đoán…” và bị khoá để tránh bấm hai lần.
- Khi xong, thẻ ghi giờ hoàn tất, thời gian chạy và mức kết luận (nghiêm trọng / cần kiểm tra / chưa thấy dấu hiệu) với màu tương ứng; có nút **Xem kết quả gần nhất** để mở lại mà không phải quét lại. Lỗi giữa chừng được báo trong thẻ và nút được mở lại.

## 2.2.12.0 — 26/11/2026

- Chẩn đoán báo virus nhận dạng thêm Floxif: `symsrv.dll` / `ffff.dll` trong `Common Files\System` (cả Program Files và Program Files (x86)) và `AppInit_DLLs` đang được nạp.
- Mỗi phát hiện của Defender hiện trạng thái xử lý theo mã Microsoft (đã diệt / cách ly / xoá, **đang được cho phép**, xử lý thất bại); mã không có trong tài liệu được ghi rõ, không đoán nghĩa.
- Đánh dấu **ĐÃ CHẠY** khi Defender ghi nhận mã độc đã thực thi, **[CÒN TRÊN Ổ]** cho tệp bị phát hiện vẫn còn, và cảnh báo khi một mã mối đe dọa đang được “Cho phép” (Defender bỏ qua mọi tệp cùng mã).
- Tệp Defender báo **đã diệt** mà còn trên ổ được ghi riêng **[CÒN TRÊN Ổ, ĐÃ DIỆT]**; danh sách mã đang cho phép rỗng không còn lỗi trên PowerShell 5.1.
- Danh sách phát hiện xếp mới nhất trước và có dòng tóm tắt theo ổ (ổ trong máy / USB / ổ mạng / đã rút) để nhận ra kho cài đặt hoặc USB bị lây. Kết luận sơ bộ có thêm hướng xử lý khi mã độc đã chạy (cài lại Windows, đổi mật khẩu từ máy sạch).

## 2.2.11.0 — 26/11/2026

- Cửa sổ kết quả chẩn đoán (báo virus, UltraViewer) có nút **Xuất file…** lưu kết quả ra .txt (UTF-8, mặc định trong Documents, tên gồm tên máy và thời điểm) rồi mở thư mục chứa tệp. Ba nút Xuất file / Sao chép / Đóng cùng chiều cao.
- Chẩn đoán báo virus chỉ quét chữ ký .exe / .dll. Trên Windows PowerShell 5.1, bộ lọc cũ bị bỏ qua nên liệt kê cả .ts / .json / .node của Zalo thành “UnknownError”.
- Ngoại lệ Defender trùng cả ổ đĩa (ví dụ D:\) hoặc thư mục hệ thống / người dùng / Temp được đưa lên kết luận **KIỂM TRA GẤP**, vì mọi tệp trong vùng đó không được quét.

## 2.2.10.0 — 26/11/2026

- Đổi tab **Fix Driver** thành **Chẩn đoán & sửa lỗi** để gom công cụ xử lý sự cố dùng trên mọi máy; Fix Driver giữ nguyên, là một mục trong tab. **Sau khi clone** chỉ còn các bước cơ bản cho máy mới clone.
- Thêm **Chẩn đoán & sửa lỗi → Chẩn đoán báo virus** cho trường hợp Word, Zalo hoặc ứng dụng khác bị Defender / Kaspersky báo virus và không mở được. Chỉ đọc: giải mã trạng thái AV trong Security Center (bật / tắt, định nghĩa cũ), tên mối đe dọa Defender 30 ngày, nhật ký cảnh báo Kaspersky nếu có, dấu hiệu virus lây file .exe (lệnh mở exefile bị thay, svchost.com / directx.sys trong Windows), chữ ký số Office / Zalo (HashMismatch là tệp bị sửa), phiên bản Office hết hỗ trợ, dấu vết công cụ kích hoạt bên ngoài và ngoại lệ Defender.
- Kết luận sơ bộ phân biệt nhiễm virus lây file, công cụ kích hoạt bị nhận là HackTool và phát hiện heuristic / máy học có thể báo nhầm. Không khôi phục vùng cách ly, không thêm ngoại lệ, không xoá tệp hoặc tác vụ.

## 2.2.9.0 — 23/11/2026

- Fix Driver hiện tổng số thiết bị đã đọc, số Windows báo Code 0, số có mã lỗi và số chưa đọc được trạng thái. Không còn dùng dòng “Đã xác nhận Code 0: 0” để hiển thị lần quét đầu khiến dễ nhầm chưa quét; số chuyển sang Code 0 chỉ tính các thiết bị đã có lỗi xác định đầu phiên.
- CIM không trả thiết bị sẽ báo chưa đọc được dữ liệu, không kết luận máy đủ driver. Giá trị ConfigManagerErrorCode thiếu / không hợp lệ hiện “?” và cảnh báo, không ép thành Code 0; thiết bị chưa rõ trạng thái không được disable theo profile. Đặt OperationTimeoutSec cho truy vấn PnP.
- Thêm Hiện tất cả thiết bị để đối chiếu danh sách và nút Mở Device Manager. Mặc định giữ danh sách cần kiểm tra; đây không phải tính năng tìm phiên bản driver mới hơn cho thiết bị đang hoạt động.
- Ghi log ngay khi bắt đầu phiên, kể cả lỗi khởi tạo; Mở nhật ký vẫn dùng được khi chưa tạo xong phiên. Báo cáo HTML có số thiết bị đọc được và phân biệt trạng thái chưa rõ với hoạt động.

## 2.2.8.0 — 21/11/2026

- Menu chuột phải đọc đầy đủ build và UBR. Từ mốc 26200.9974 trở lên vẫn lưu / kiểm tra key menu truyền thống, nhưng cảnh báo Windows có thể bỏ qua tuỳ chỉnh; không suy ra menu mới đã bật chỉ từ số build vì tính năng được triển khai dần. Nếu thiếu UBR ở build 26200, hiển thị chưa xác định và cảnh báo thận trọng.
- Giữ cảnh báo khi key đã tồn tại và sau khi yêu cầu khởi động lại Explorer. Phân biệt xác nhận cấu hình với xác nhận giao diện menu; log lưu build, UBR và trạng thái chưa xác minh hiển thị. Khôi phục menu Windows 11 vẫn hoạt động như trước.
- Hướng dẫn Shift + chuột phải để mở menu đầy đủ; nếu Customize menu có Arrange primary actions inline thì có thể bật thủ công. Chưa tự ghi registry của toggle khi chưa xác định / kiểm thử giá trị thực tế.

## 2.2.7.0 — 21/11/2026

- Thêm Sau khi clone → Thiết lập mặc định: chọn một máy in đã cài, đặt A4 và / hoặc đặt máy in mặc định cho tài khoản đang chạy app. Tắt Windows tự quản lý máy in khi chọn mặc định; ghi lại trạng thái trước / sau và đọc lại kết quả từ hệ thống. Báo riêng nếu driver chưa hỗ trợ / nhận A4 hoặc một phần thao tác thất bại.
- Chọn trình duyệt web và ứng dụng đọc PDF từ các đăng ký thực tế trên máy; mở trang Ứng dụng mặc định của Windows để người dùng xác nhận. Kiểm tra lại HTTP, HTTPS và .pdf; không sửa / sao chép UserChoice hash, không báo thành công chỉ vì đã mở Cài đặt.
- Cửa sổ WPF dùng khung và ô chọn bo góc, thông báo màu, tác vụ nền và nhật ký local. Hiện rõ tài khoản áp dụng; khổ A4 của hàng đợi và khổ giấy lưu riêng trong tài liệu có thể khác nhau.

## 2.2.6.0 — 21/11/2026

- UltraViewer tự tìm lại lịch sử reset đúng máy khi mở lại cửa sổ / app hoặc sau khởi động lại Windows, gồm bản sao lưu tạo bởi phiên bản cũ. Hiện thời gian và trạng thái reset, chờ ID, xác minh hoặc khôi phục cùng đường dẫn sao lưu; không reset tự động khi mở cửa sổ.
- Lưu trạng thái và nhật ký thao tác cùng biên nhận trong ProgramData. Kiểm tra ID dựa trên bản sao lưu; không báo đã tạo ID mới sau khi khôi phục ID cũ, không nhận lịch sử từ máy khác hoặc nhầm bản sao lưu chuẩn bị ảnh gốc là reset máy khách.
- Thêm nút Paint trên Microsoft Store trong Cài Windows, mở trang Paint chính thức để kỹ thuật viên bấm Get / Cài đặt.

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
