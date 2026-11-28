# TechMaster Deploy

Bộ công cụ triển khai Windows và Office.

Từ **2.0.0.0**, giao diện chính và cửa sổ cập nhật dùng **WPF** trên Windows PowerShell 5.1 / .NET Framework có sẵn trong Windows 10/11. Mở `TechMaster Deploy.exe`; chọn chức năng bằng thanh điều hướng bên trái. Từ 2.1.0.0, gỡ / dọn Office có bảng tích chọn từng key; các bước xác nhận dùng nút WPF, không yêu cầu gõ từ khoá. Công cụ triển khai vẫn ghi nhật ký chi tiết.

Menu chia theo chức năng; app mở ở **Tổng quan**.

| Nhóm | Menu | Công cụ | Thư mục |
|---|---|---|---|
| | **Tổng quan** | Thông tin máy (Windows / build, CPU, RAM, ổ hệ thống, IP, bản quyền Windows / Office), lối vào nhanh, chạy TechMaster trên máy khác | `App\` |
| CÀI ĐẶT | **Cài Windows** | Mở trang tải của Microsoft, tạo USB, chạy Windows Setup từ ISO, cài lại Paint, dọn Windows.old | ISO do người dùng chọn |
| | **Phần mềm** | Office Deployment Tool (tải về kho, cài từ kho / trực tiếp, gỡ Office) và ứng dụng cơ bản qua WinGet | `Office\`, kho ở `KhoOffice\` |
| | **Bản quyền & biên bản** | Kích hoạt Windows / Office (online → portal, QR, nhận Confirmation ID qua LAN), key dùng tạm; biên bản và xác nhận bàn giao HTML (in / lưu PDF) | `KichHoat\`, `BienBan\` |
| CẤU HÌNH | **Tuỳ chỉnh Windows** | Định dạng ngày / số, bàn phím US cho EVKey, menu chuột phải, trình duyệt / PDF mặc định | `FixClone\`, `App\` |
| | **Máy in** | Thêm máy in theo IP (TCP/IP, driver từ kho), kết nối máy in chia sẻ bằng tài khoản có mật khẩu (không tắt bảo mật in), máy in mặc định, khổ A4, dọn máy in không còn kết nối | `App\` |
| | **Mạng LAN & chia sẻ** | Tài khoản scan / share / print, chia sẻ thư mục có phân quyền và tường lửa LAN, kết nối lưu mật khẩu một lần, chạy TechMaster qua LAN | `App\` |
| TRIỂN KHAI | **Clone hàng loạt** | Máy gốc: kiểm tra / sửa lỗi Sysprep, chuẩn bị và chạy Sysprep, `Reinstall`. Sau khi clone: xử lý trùng lặp, UltraViewer trùng ID, Desktop và phím chụp | `FixClone\` |
| HỖ TRỢ | **Chẩn đoán & sửa lỗi** | Fix Driver; chẩn đoán ứng dụng bị báo virus / không mở được và sửa lỗi có chọn lọc | `FixClone\`, `App\` |
| | **Cập nhật** | Kiểm tra, cài bản mới, lịch sử và khôi phục | `.updates\` |

## Cách dùng

1. Chép cả thư mục `TechMaster-Deploy` ra USB, giữ nguyên cấu trúc thư mục con.
2. Mở **`TechMaster Deploy.exe`** và chấp nhận yêu cầu Administrator. Muốn tạo shortcut Desktop, dùng File Explorer hoặc chạy `App\Tao-Shortcut.bat`.
3. Thanh trên cùng và trang **Tổng quan** hiện tên máy, cấu hình và trạng thái bản quyền Windows / Office (bấm **Làm mới** hoặc **Đọc lại** để đọc lại; **Sao chép thông tin** để dán vào phiếu).
4. Chọn thao tác, xem phạm vi thay đổi rồi bấm xác nhận. Công cụ triển khai có thể mở cửa sổ nhật ký riêng; không cần gõ YES / XOA OFFICE. Tab Biên bản xuất trực tiếp từ giao diện.

Bản chia sẻ mới không kèm cấu hình hoặc logo công ty. Với bộ công cụ đã dùng, bấm **Xoá thông tin đơn vị / logo** trong Biên bản để nhập thông tin đơn vị mới. Gói phát hành không kèm biên bản khách hàng đã xuất.

Danh sách ứng dụng tự thêm lưu tại `%LOCALAPPDATA%\TechMaster Deploy\CustomApps.json`, chỉ trên tài khoản Windows đang dùng; không đẩy lên repo hoặc đồng bộ máy khác.

## Hướng dẫn và hỗ trợ

Chấm đỏ trên nút **Cập nhật** báo có bản mới; app kiểm tra nền lúc mở và mỗi 30 phút, không tự tải hoặc cài.

Bấm **Hướng dẫn nhanh** ở cuối menu để xem cách dùng từng tính năng ngay trong app. **Có gì mới** có danh sách phiên bản và nội dung cập nhật. Mục **Liên hệ / góp ý** mở Zalo **0976852096** hoặc email **vienkendo@gmail.com**; khi báo lỗi, gửi phiên bản app, bước vừa thao tác và ảnh / nhật ký đã che thông tin riêng tư.

## Cập nhật phiên bản

Từ **v1.1.1.0**, tab **Cập nhật → Kiểm tra cập nhật** lấy mã trực tiếp từ **dangvien-dev/TechMaster-Deploy**, nhánh **main**. Không cần GitHub Release, manifest phát hành trên repo khác hoặc tải / giải nén ZIP bằng tay.

App kiểm tra commit mới, hiển thị phiên bản, chỉ lấy những tệp nguồn đã thay đổi, rồi sao lưu và hỏi xác nhận trước khi đóng / cập nhật / mở lại. Mỗi lần chỉ dùng tệp của cùng một commit; tệp tải về được đối chiếu Git blob và các bước thay tệp được kiểm tra SHA256. Từ v1.1.3.0, đường cập nhật công khai lấy trực tiếp từ Git / raw, tránh giới hạn API khi nhiều máy dùng chung mạng. Launcher được biên dịch bằng .NET Framework sẵn có trên Windows, không thực thi script build tải từ repo.

Nguồn công khai không cần đăng nhập. Giao diện thường chỉ hiện phiên bản và các lựa chọn cập nhật / khôi phục. Cấu hình truy cập dành cho người quản lý được mô tả trong RELEASING.md.

**Lịch sử cập nhật**, **Có gì mới?** và **Khôi phục bản trước** vẫn dùng được. Cấu hình biên bản, logo, biên bản đã xuất, kho Office, ODT, nhật ký và Reinstall được giữ nguyên. Sao lưu nằm ở `.updates`; đừng xoá nếu còn muốn quay lại. Tệp chương trình sửa riêng không bị tự ghi đè.

**Bản cũ chưa hỗ trợ repo:** dùng công cụ `TechMaster-Update.exe` mới để chọn thư mục app hiện tại, rồi bấm tải / cài; có nút chọn ZIP offline khi cần. Sau lần nâng cấp này chỉ dùng nút Kiểm tra cập nhật. Cập nhật ZIP vẫn có để chuyển bản offline.

**Bản cũ lỗi HTTP 403 khi cập nhật:** đóng app, tải `App/Repair-Update.ps1` từ repo rồi chạy bằng PowerShell với `-Root` là thư mục TechMaster-Deploy hiện tại. Công cụ lấy updater mới riêng, giữ dữ liệu và hỏi xác nhận trước khi cài; xem [hướng dẫn sửa cập nhật](RELEASING.md#sửa-cập-nhật-trên-bản-cũ).

**Nâng cấp bằng giao diện:** đóng app cũ, mở `TechMaster-Update.exe` trong Downloads của repo, chọn file `TechMaster Deploy.exe` đang dùng hoặc nhập thư mục app. Bấm **Tiếp tục → Tải bản cập nhật → Cài đặt bản cập nhật → Đóng và mở ứng dụng**. Cập nhật xong giữ nguyên màn hình kết quả; chỉ mở app sau khi bấm **Đóng và mở ứng dụng**. Nút X chỉ đóng updater. Có nút chọn ZIP nếu cần cập nhật offline. Từ bản 2.0 dùng nút cập nhật trong app; không nhập `y` hoặc `CAP NHAT` nữa. Khi nâng cấp từ bản cũ, cửa sổ updater đang chạy vẫn mang giao diện cũ đến khi đóng; mở lại từ app mới để dùng giao diện / icon mới. Từ 2.1.1, nút Cập nhật trên đầu app gọi lại cửa sổ cập nhật nếu bị khuất hoặc thu nhỏ, và thanh trạng thái chính hiện tiến trình tải.

**UltraViewer trùng ID:** vào **Clone hàng loạt → Sau khi clone → Đặt lại ID UltraViewer** để sao lưu rồi reset hai trường UID / PreferID của bản **6.6.133** đã kiểm tra. Thao tác ngắt UltraViewer, nên chạy tại máy hoặc qua remote khác. Có nút kiểm tra và khôi phục. Khi tạo ảnh mới, bật tuỳ chọn chuẩn bị UltraViewer trong cửa sổ trước Sysprep; dịch vụ được giữ tắt trên ảnh gốc và bật lại sau clone để nhận ID riêng một lần. Chẩn đoán UltraViewer vẫn chỉ đọc. Lịch sử reset / xác minh / khôi phục và bản sao lưu được giữ trong `%ProgramData%\TechMaster Deploy\UltraViewer Backups`; mở lại cửa sổ sẽ tìm lại lịch sử đúng máy, gồm biên nhận từ bản cũ. Không cần reset lần nữa chỉ để kiểm tra ID. Nếu cài lại / reset Windows hoặc xoá ProgramData thì lịch sử có thể mất; đây không phải sao lưu bên ngoài ổ Windows.

Trước Sysprep có cửa sổ nhắc chọn **Screen Snipping → Always** cho Windows + Shift + S, kiểm tra và sao lưu / dọn icon Word / Excel trùng. Chỉ dọn shortcut cùng đích, giữ các thiết lập Word. Máy đã clone mở chức năng này ở **Sau khi clone → Kiểm tra Desktop và phím chụp**.

Các thay đổi chỉ có trong workspace hoặc ZIP chưa tự xuất hiện trên GitHub. Người quản lý phải đẩy mã mới lên `main`; app không tự push hoặc thay đổi repo. Xem [RELEASING.md](RELEASING.md).

## Chữ tiếng Việt trong cửa sổ console

Các công cụ gỡ / cài Office, kích hoạt, biên bản và FixClone dùng chung khởi tạo UTF-8 và chọn font **Consolas** cho cửa sổ console Windows kiểu cũ. Giữ nguyên cả thư mục `App` khi giải nén bộ công cụ. Việc chọn font chỉ áp dụng cho console đang chạy, không sửa font mặc định trong Registry hay profile PowerShell.

Nếu máy vẫn hiện ô vuông, mở menu thanh tiêu đề PowerShell → **Properties → Font → Consolas**, rồi mở lại công cụ. Windows Terminal tự quản lý font: chọn Consolas hoặc một font hỗ trợ tiếng Việt trong Settings của Terminal. Đổi code page riêng lẻ không bổ sung được ký tự còn thiếu trong font.

## Cài Windows

1. Mở tab **Cài Windows**, bấm **Trang tải Microsoft** ở dòng Windows 11 hoặc Windows 10 để mở trang tải chính thức trong trình duyệt.
2. Sau khi tải ISO, bấm **Chọn ISO…**. Ứng dụng gắn ISO, kiểm tra chữ ký Microsoft của `setup.exe` và mở Windows Setup. Các lựa chọn giữ dữ liệu và bước xác nhận cài đặt nằm trong Windows Setup.
3. Để cài mới từ USB, bấm **Tạo USB Windows 11** hoặc **Tạo USB Windows 10**. TechMaster tải và kiểm tra chữ ký của Media Creation Tool, sau đó mở công cụ để bạn chọn USB trống từ 8 GB. Dữ liệu trên USB được chọn sẽ bị xóa.
4. Sau khi cài trực tiếp và kiểm tra dữ liệu, mở lại app, bấm **Dọn Windows.old**. Trong **Disk Cleanup**, chọn **Dọn tệp hệ thống → Bản cài đặt Windows trước đây**, kiểm tra các mục khác rồi xác nhận xoá. Xóa Windows.old sẽ bỏ khả năng quay lại bản Windows cũ.

## Biên bản bản quyền

- Thông tin đơn vị lưu ở `BienBan\BienBan-Config.json`, nhập một lần.
- Logo: file `BienBan\Logo.svg` (hoặc `.png` / `.jpg`). Đổi bằng nút **Chọn logo…**.
  Giao diện không xem trước được SVG; logo SVG vẫn hiện đúng trong biên bản.
- Biên bản lưu ở `BienBan\BienBan\<Tên máy>_<ngày giờ>.html`, tự mở trong trình duyệt → nút **In / Lưu PDF**.
- Chỉ in 5 ký tự cuối key. Luôn có ghi chú "không phải chứng nhận do Microsoft cấp".
- Tổng kết lấy từ cùng danh sách license hiển thị trong bảng; thiếu dữ liệu / lỗi đọc được báo riêng, không tự kết luận là chưa kích hoạt. Sau khi cập nhật công cụ hoặc trạng thái license, cần **xuất lại biên bản**; HTML cũ không tự cập nhật.

## Tải / cài Office (Office Deployment Tool)

- Theo dõi giai đoạn, thời gian và dung lượng trong kho ngay trên trang Phần mềm. Sau khi chạy xong, nút **Xem nhật ký** mở kết quả. Tải và cài Office chạy nền. Mọi trạng thái và kết quả hiển thị ngay trên tab.

- `setup.exe` (ODT) tự tải từ `officecdn.microsoft.com` lần đầu, **kiểm tra chữ ký số Microsoft** trước khi chạy; chữ ký không hợp lệ thì xoá và dừng.
- Sản phẩm: Home & Business 2024 / 2021 (bán lẻ), Microsoft 365 Apps business / enterprise, LTSC Professional Plus / Standard 2024, Professional Plus 2021 (Volume).
- Mặc định: tiếng Việt + tiếng Anh, 64-bit, không cài Teams, OneDrive, Skype (Lync), Groove, Bing.
- **Tải về kho** một lần (3–5 GB) → chép `KhoOffice\` ra USB / NAS → **Cài từ kho** trên các máy khác, không cần mạng.
- Ô **Key** tuỳ chọn: có key thì ODT cài kèm key và tự kích hoạt; file cấu hình có key bị xoá sau khi chạy.
- Tool **chỉ tải / cài**, không kích hoạt. Bản Volume (LTSC) cần key Volume / KMS của tổ chức; Microsoft 365 kích hoạt bằng tài khoản.

## Gỡ / dọn Office

Trong **Bản quyền & biên bản**, tại **Kích hoạt Office**, bấm **Key dùng tạm Office…** để kiểm tra / xoá key, tương tự mục key Windows. Phần này không có nút gỡ ứng dụng. Nếu cần gỡ bộ Office, vào **Tải / cài Office → Gỡ Office…**. Bảng hiện loại license, trạng thái và 5 ký tự cuối key; mặc định không chọn key nào:

1. **Kiểm tra**: liệt kê Product ID Click-to-Run và key Office đọc được từ SoftwareLicensingProduct; chỉ hiển thị 5 ký tự cuối.
2. **Xoá key đã chọn**: tích đúng các key cần xoá rồi bấm nút, kiểm tra danh sách trong hộp xác nhận. Key không chọn được giữ nguyên, gồm Retail bạn cần dùng. Nút chọn key dùng thử chỉ chọn Grace/Trial được nhận diện rõ; không gỡ ứng dụng.
3. **Gỡ bộ Office**: chỉ áp dụng Office Click-to-Run 2021 / 2024. Tích key cần xoá rồi bấm Gỡ Office. Nếu còn key bộ Office cần giữ, công cụ từ chối gỡ ứng dụng để tránh ảnh hưởng key đó; Visio / Project được giữ.

**Trước Sysprep:** có lựa chọn dọn key tạm mặc định bật. Công cụ lưu thiết lập Word trước; chỉ tự xoá license Office 2021 / 2024 có tên chứa Grace / Trial và trạng thái chưa kích hoạt. Retail dù chưa kích hoạt vẫn được giữ, key không nhận diện chắc chắn cần bạn xem / chọn thủ công. Chỉ gọi UninstallProductKey, không xoá kho token / giấy phép chung hay ứng dụng. Sau clone kiểm tra lại theo lựa chọn đã lưu, giúp dọn key tạm Office có thể tạo lại khi mở trên máy gốc.

Công cụ gọi `ClearKeyManagementServiceMachine`, `ClearKeyManagementServicePort`, `UninstallProductKey` trên từng license có Application ID của Office, rồi đọc lại để kiểm tra. Không chạy `slmgr /upk`, không xoá key Windows hoặc kho token dùng chung. Cấu hình KMS dùng chung với Windows không bị thay đổi.

Một số provider CIM không trả `ReturnValue` khi thực hiện thành công. Khi gặp trường hợp này, công cụ đọc lại cấu hình KMS; sau bước xoá key luôn kiểm tra lại danh sách license. Mã lỗi khác 0, lỗi CIM hoặc trạng thái vẫn còn sẽ được báo lỗi, không coi là đã dọn xong.

KMS có thể thuộc bản quyền hợp lệ của tổ chức. Công cụ **không kết luận bản quyền lậu** từ trạng thái KMS và **không tự xoá phần mềm crack, dịch vụ, tác vụ, tài khoản hoặc token Microsoft 365**. Công cụ kích hoạt bên ngoài còn trên máy có thể tự nạp key lại; cần gỡ công cụ đó và quét bảo mật riêng trước khi cài bản quyền hợp lệ. Vì vậy không coi thao tác này là chứng nhận máy đã sạch mã độc hoặc đã khôi phục mọi tệp Office từng bị sửa.

Chạy trực tiếp bằng Windows PowerShell (vẫn yêu cầu xác nhận khi xoá):

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Inspect
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Keys
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File Office\Office-Cleanup.ps1 -Mode Remove
```

Kiểm thử mô phỏng, không thay đổi Office trên máy:

```powershell
powershell.exe -NoProfile -File Office\Test-OfficeCleanup.ps1
```

## Cài ứng dụng cơ bản

1. Mở **Phần mềm**, phần **Ứng dụng**, chọn Chrome, 7-Zip, VLC, SumatraPDF, Foxit PDF Reader, ONLYOFFICE Desktop Editors, LibreOffice, Notepad++, Zalo, WinRAR, UltraViewer hoặc EVKey rồi bấm **Cài ứng dụng đã chọn**.
2. Giữ TechMaster mở trong lúc WinGet tải và cài lần lượt. Tiến trình đếm số ứng dụng đã xử lý. WinGet bỏ qua phiên bản đã cài và tab hiển thị kết quả cho từng ứng dụng.
3. UltraViewer dùng bộ cài tiếng Việt **6.6.133** từ link chính thức; kiểm tra chữ ký nhà phát hành và phiên bản trước khi chạy, rồi đọc lại phiên bản sau cài. Bản đã cài / đang chạy được giữ để tránh ngắt hỗ trợ. Các app còn lại dùng WinGet.
4. WinRAR: sau cài hoặc khi đã có sẵn, app mở WinRAR lần đầu để hoàn tất thiết lập theo tài khoản; thử lại menu chuột phải. WinRAR đang chạy được giữ nguyên.
5. Foxit Reader: app kiểm tra riêng máy in PDF sau cài. Reader bản mới không kèm máy in ảo Foxit như bản Reader cũ; Microsoft Print to PDF là tính năng riêng của Windows. Kết quả có hàng đợi không thay thế việc thử in một trang thực tế.
4. Bấm **Xem nhật ký** để xem kết quả cài. Nếu máy chưa có WinGet, bấm **Hướng dẫn WinGet** để cài hoặc cập nhật App Installer.

## Chi tiết từng bộ

- `FixClone\README.md`
- `KichHoat\README.md`

## Trạng thái kiểm tra

| Phần | Trạng thái |
|---|---|
| Script FixClone, Kich-Hoat (TEST qua LAN) | Đã chạy trên máy thật 2026-11-16 |
| Mẫu biên bản (bố cục, logo, 1 trang A4) | Đã xem trước bằng dữ liệu giả |
| Giao diện WPF và updater | Kiểm tra tải cửa sổ, điều khiển, xác nhận và trạng thái bằng Windows CI; thao tác hệ thống dùng mô phỏng |
| `Office\Office-ODT.ps1` | XML cấu hình đã kiểm cú pháp; tải / cài thật **chưa chạy** |
| Đọc WMI trong biên bản trên máy thật | **Chưa chạy** |

Bản này là công cụ tạm dùng trước. Bản chính thức sẽ nằm trong TechMaster Pro theo SPEC-005 / 006 / 007 và issue #44.

## Build launcher từ mã nguồn

Trên Windows, chạy `powershell.exe -NoProfile -ExecutionPolicy Bypass -File App\Build-Launcher.ps1` trong thư mục dự án. File `TechMaster Deploy.exe` sẽ được tạo cạnh README.

### Fix Driver (dùng chung mọi máy / mainboard)

Vào **Chẩn đoán & sửa lỗi → Mở Fix Driver** để quét thiết bị báo lỗi, lấy Hardware ID / link Catalog (máy in / MFP của hãng trong bảng VID thì mở trang driver của hãng thay cho link Catalog theo VID/PID), cài CAB hoặc thư mục INF đã tải, và cài từ kho USB / NAS tối đa 4 vòng. Không cần profile để dùng các chức năng này; không có driver được đóng gói hoặc tải tự động. Profile JSON chỉ bổ sung khuyến nghị riêng khi khớp model, mẫu đầu là SingPC I5-12450H BIOS 5.32. Xem [thiết kế và hướng dẫn test](FixClone/DriverFix.md), [JSON profile mẫu](FixClone/DriverFix.SingPC.json). Mọi cài / disable / chỉnh nguồn đều cần Admin và ghi log local.

**Thiếu Paint:** vào **Cài Windows → Paint trên Microsoft Store**, bấm **Get / Cài đặt** trên trang Paint chính thức của Microsoft. App chỉ mở trang Store, không tự cài hoặc báo hoàn tất khi chưa kiểm tra.

**Máy in / trình duyệt / PDF mặc định:** vào **Máy in → Máy in mặc định / A4…** (trình duyệt / PDF: **Tuỳ chỉnh Windows → Trình duyệt / PDF mặc định…**; dọn máy in: **Máy in → Dọn máy in không kết nối…**; mỗi nút mở cửa sổ riêng chỉ có phần của nó). Chọn máy in đã cài, tích A4 và / hoặc đặt mặc định rồi bấm **Áp dụng máy in**. App kiểm tra quyền Admin, ghi log trong `%LOCALAPPDATA%\TechMaster Deploy\Windows Tools`, đọc lại A4 và máy in mặc định; nếu chỉ một bước thành công thì báo riêng. Mặc định áp dụng cho tài khoản đang chạy app, tắt Windows tự chọn máy in dùng gần nhất. Khổ giấy hàng đợi có thể ảnh hưởng người cùng dùng máy in; khổ giấy riêng của tài liệu Word / Excel không tự đổi.

**Dọn máy in không kết nối:** nút **Dọn máy in không kết nối…** cạnh Thiết lập mặc định mở thẳng thẻ dọn máy in. Gỡ giống **Remove device** trong Devices and Printers: xoá hàng đợi in, rồi xoá các mục thiết bị ẩn (đã ngắt kết nối) cùng container; driver giữ nguyên. Danh sách gồm máy in USB / mạng Windows đang báo Offline và thiết bị máy in còn sót không còn hàng đợi; máy in ảo PDF / XPS / OneNote / Fax và thiết bị đang kết nối không bao giờ bị gỡ. App hỏi xác nhận, kiểm tra lại ngay trước khi gỡ, hiện tiến trình từng máy, có thể khởi động lại Print Spooler khi Windows chưa xoá xong, đọc lại kết quả và ghi nhật ký trong `%LOCALAPPDATA%\TechMaster Deploy\Windows Tools`.

**Chia sẻ trong mạng LAN:** **Mạng LAN & chia sẻ → Tài khoản chia sẻ LAN…** tạo user `scan` / `share` / `print` (mật khẩu do kỹ thuật viên nhập) chỉ dùng qua mạng: chặn đăng nhập tại máy, Remote Desktop, tác vụ, dịch vụ; ẩn khỏi màn hình đăng nhập; mật khẩu không hết hạn; nhóm Users. **Chia sẻ thư mục…** chọn thư mục, đặt tên, phân quyền Chỉ đọc / Đọc & ghi cho từng tài khoản (quyền chia sẻ + NTFS), mở tường lửa riêng của TechMaster chỉ cho mạng Private / Domain cùng dải mạng, chuyển mạng Public sang Private khi được chọn; không mở cho Everyone / Guest, không cho chia sẻ thư mục hệ thống. **Kết nối thư mục chia sẻ…** chạy trên máy người dùng: thử đăng nhập rồi lưu mật khẩu vào Windows Credential Manager của người đang dùng máy, tạo lối tắt / gán ổ đĩa, để người dùng mở thư mục không phải nhập lại. App không ghi mật khẩu vào file hay nhật ký.

**Chạy TechMaster trên máy khác, không cần USB:**

- *Qua LAN:* trên máy đang có app, **Mạng LAN & chia sẻ → Chia sẻ TechMaster qua LAN…** (hoặc nút cùng tên ở Tổng quan), chọn tài khoản máy kia dùng (tài khoản đang dùng hoặc `share`) rồi **Chia sẻ TechMaster**. Thư mục chương trình được chia sẻ thành `\\TÊN-MÁY\TechMaster$` (ẩn, chỉ đọc, không Everyone / Guest; tường lửa chỉ trong LAN). Trên máy kia mở `\\TÊN-MÁY\TechMaster$\App\Chay-Tu-Mang.bat`: tệp được chép vào thư mục tạm (không cần quyền quản trị, vì kết nối mạng thuộc phiên đăng nhập này) và kiểm tra theo danh sách tệp của app (`update-package.json` của bản cài, có SHA256 từng tệp kể cả exe; hoặc `update-source.json` nếu chia sẻ từ mã nguồn); bước cài chạy với quyền quản trị bằng lệnh nhúng sẵn, khoá `C:\TechMaster-Deploy` chỉ cho Administrators / SYSTEM sửa, kiểm tra lại từng tệp và `TechMaster Deploy.exe` rồi mở app. Lần sau chỉ chép tệp thay đổi; bản mới hơn trong thư mục đã khoá được mở luôn. Bấm **Ngừng chia sẻ** khi xong.
- *Qua Internet:* trên máy kia mở PowerShell, dán `irm https://dangvien-dev.github.io/tm.txt | iex` (nút **Sao chép lệnh**). Lệnh xin quyền quản trị, tải gói ZIP đang công bố trên trang (theo `downloads/latest.json`) vào bộ nhớ, kiểm tra SHA256, cài vào `C:\TechMaster-Deploy` đã khoá rồi mở; bản cài sẵn trong thư mục đã khoá thì chỉ mở, cập nhật bằng nút **Cập nhật** trong app.

Chọn trình duyệt / ứng dụng PDF đã đăng ký, bấm nút mở Cài đặt rồi xác nhận **Set default / Đặt mặc định** trong Windows. Quay lại bấm **Kiểm tra lại** để đối chiếu HTTP, HTTPS hoặc .pdf. Bản Windows chưa hỗ trợ mở đúng trang ứng dụng thì chọn ứng dụng trong trang chung. App không ghi UserChoice hash, không ép đổi khi chưa có xác nhận trong Windows. Nếu mở app bằng tài khoản quản trị khác, thiết lập thuộc tài khoản đó.

**Menu chuột phải trên Windows mới:** app ghi và đọc lại cấu hình menu truyền thống, nhưng không coi đó là xác nhận giao diện đã đổi. Từ mốc `26200.9974` trở lên, thông báo nêu Windows có thể bỏ qua key; cùng build có thể khác do triển khai dần. Cảnh báo vẫn hiện nếu key đã tồn tại hoặc sau khi restart Explorer. Có thể giữ **Shift + chuột phải** để mở menu đầy đủ, hoặc bật **Arrange primary actions inline** nếu mục này có trong **Customize menu**. Đây là hướng dẫn thao tác thủ công; app chưa tự ghi registry của toggle. Log phân biệt xác minh key với giao diện chưa được xác minh, kèm build và UBR. Mốc phiên bản là ngưỡng cảnh báo, không phải phát hiện chắc chắn tính năng đã bật.

**Đọc kết quả Fix Driver:** giao diện hiện tổng thiết bị đã đọc, số Windows báo Code 0, số có mã lỗi và số chưa rõ trạng thái. Bật **Hiện tất cả thiết bị** để xem danh sách đã đọc, dùng **Mở Device Manager** để đối chiếu. Không có dữ liệu CIM sẽ báo lỗi, không hiện như quét thành công 0 lỗi; mã thiếu hiện `?` và không được tính là hoạt động. Số lỗi chuyển sang Code 0 được tách khỏi số thiết bị đang báo Code 0. Module chưa tìm phiên bản driver mới hơn cho thiết bị đang hoạt động. Lỗi khởi tạo vẫn có log trong `%LOCALAPPDATA%\TechMaster Deploy\DriverFix\Sessions` và nút **Mở nhật ký** vẫn dùng được.
