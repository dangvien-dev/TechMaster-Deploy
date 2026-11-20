# Fix Driver — thiết kế và kiểm thử

## Phạm vi dùng chung

Module dùng được trên mọi máy / mainboard chạy Windows 10/11 có CIM và pnputil. Không cần profile để quét lỗi, tạo link Catalog, cài CAB / thư mục INF, cài từ kho USB / NAS hoặc xuất báo cáo. Mở **Fix Driver → Mở Fix Driver** trong ứng dụng; cũng có thể chạy `FixClone/DriverFix.ps1` bằng Windows PowerShell 5.1 STA.

Profile là gợi ý bổ sung khi nhận diện máy khớp. Không áp cấu hình SingPC lên máy khác. Không tự dò web, tải driver, đóng gói driver, ép driver sai Hardware ID, bỏ kiểm tra chữ ký, thay BIOS hoặc khởi động lại máy.

## Kiến trúc

- `DriverFix.Core.ps1`: CIM inventory, thông tin máy, mô tả mã lỗi, so sánh snapshot, Catalog query và kiểm tra JSON profile. Giữ cả thiết bị tốt để phân biệt chuyển Code 0 với thiết bị biến mất.
- `DriverFix.Engine.ps1`: quyền Admin, JSONL log, expand / pnputil, đối chiếu kho INF tối đa 4 vòng, disable có kiểm tra lại và chỉnh nguồn theo danh sách thao tác cố định.
- `DriverFix.Report.ps1`: HTML độc lập với thông tin máy, trước / sau, thao tác, kết quả lệnh, thiết bị còn lỗi và link Catalog; escape dữ liệu máy trước khi đưa vào HTML.
- `DriverFix.ps1` / `.xml`: giao diện WPF cùng runtime của app, tác vụ CIM / INF / native chạy trong worker runspace; không truy cập control từ worker. Xác nhận bằng nút bấm trước cài, disable và chỉnh nguồn.
- `DriverFix.SingPC.json`: profile mẫu trong mã nguồn. `DriverFix.Profiles.ps1` mang cùng JSON dạng dữ liệu để tương thích allowlist cập nhật của các bản app cũ. Test đối chiếu hai bản. Lần mở đầu xuất thành JSON có thể sửa trong thư mục local; không ghi đè sửa đổi của kỹ thuật viên. Gói cập nhật chỉ vận chuyển PS1/XML/MD được allowlist, không cần mở rộng allowlist cũ để tải JSON.

Dữ liệu cục bộ tại `%LOCALAPPDATA%\TechMaster Deploy\DriverFix`:

- `Profiles`: JSON theo dòng máy. Thêm / sửa rồi đóng và mở lại module. Profile lỗi hiện ở giao diện; nhiều profile cùng khớp sẽ tắt các thao tác riêng theo model để tránh chọn nhầm.
- `Sessions\<timestamp>-<id>\events.jsonl`: snapshot, yêu cầu Admin, lệnh và tham số, exit code, stdout/stderr, hash CAB/INF, kết quả và lỗi từng bước. Giá trị nguồn trước/sau được lưu để kỹ thuật viên đối chiếu.
- `Reports\<ComputerName>_<yyyyMMdd-HHmm>.html`: không ghi đè báo cáo cùng phút; tự thêm hậu tố nếu trùng.

## Quét và link Catalog

CIM `Win32_PnPEntity` được đọc một lần; danh sách lỗi lọc `ConfigManagerErrorCode -ne 0`. Mỗi hàng giữ Name, Code và mô tả, toàn bộ HardwareID, InstanceId, Service và PNPClass. Code 43 là thiết bị báo lỗi; descriptor chỉ là một khả năng ở USB.

Link Catalog được tạo bằng `Uri.EscapeDataString`, không ghép `&` chưa encode. PCI / HDAUDIO dùng VEN/DEV, USB / HID dùng VID/PID, ACPI lấy ID (kể cả dạng VEN/DEV), INTELAUDIO tách controller/linktype và endpoint DEV. Tối đa 3 link, loại trùng và bỏ SUBSYS trong các query chính. Catalog có thể không có driver phù hợp; kỹ thuật viên xem kiến trúc OS, ngày / phiên bản, danh sách Hardware ID và nhà phát hành trên Catalog trước khi tải.

## Cài CAB / thư mục INF và kho cục bộ

1. Chọn CAB đã tải, hoặc thư mục chứa INF. Xác nhận phạm vi cài. CAB giải nén bằng `expand -F:*` vào thư mục tạm riêng, ghi SHA256 và danh sách INF; dọn thư mục tạm của phiên sau thao tác.
2. Chạy `pnputil /add-driver <folder>\*.inf /subdirs /install`. Chỉ thêm / cài gói Windows chấp nhận; không ép một gói thay driver đang được xếp hạng tốt hơn.
3. Chạy `pnputil /scan-devices`, đợi 3 giây và quét CIM. Trạng thái Code 0 được ghi nhận là hoạt động; lệnh thành công chỉ có nghĩa pnputil chấp nhận lệnh, không đảm bảo thiết bị đã hết lỗi. Exit 3010 hiện yêu cầu restart chủ động.
4. Thiết bị lỗi mới xuất hiện sau driver cha được hiển thị để tải tiếp. Code 22 (disable), 45 (không kết nối), 47 (đã tháo an toàn) không tự cài từ kho.
5. Kho USB/NAS phải được giải nén sẵn. Duyệt INF trong thư mục con, bỏ junction / symlink. Đối chiếu từng Hardware ID từ dài nhất đến ngắn nhất bằng regex đã escape, có ranh giới token; bỏ comment để tránh khớp tên nhắc trong chú thích hoặc SUBSYS của máy khác. Ưu tiên thứ tự profile khi có, rồi INF phiên bản cao hơn trong nhánh được đề xuất. pnputil vẫn là nơi quyết định tính tương thích cuối cùng (OS, kiến trúc, chữ ký, rank).
6. Sau mỗi vòng cài quét lại, tối đa 4 vòng. Mỗi cặp InstanceId / INF / SHA chỉ thử một lần trong lượt chạy; thiết bị con mới có thể dùng cùng INF. Dừng nếu không còn INF chưa thử khớp. Không coi disable hoặc biến mất là đã sửa bằng driver.
7. Nút Dừng không giết pnputil đang chạy. Chờ lệnh kết thúc rồi dừng trước gói tiếp theo; cửa sổ chưa cho đóng khi worker đang chạy.

Kho do kỹ thuật viên quản lý, có thể chứa driver riêng của đơn vị. Không đưa CAB/INF/SYS/CAT vào repo, thư mục phát hành hoặc ZIP ứng dụng. Tool không đồng bộ kho lên GitHub.

## Bổ sung profile

Copy mẫu JSON local, đổi `id` duy nhất và `name`, sửa `match.anyOf`. Mỗi điều kiện trong anyOf kết hợp các trường có mặt bằng AND; các điều kiện kết hợp bằng OR. `manufacturer`, `model`, `bios` là chuỗi chính xác, không phân biệt hoa thường. `hardwarePattern` nhận Hardware ID với dấu `*` ở cuối. Có thể nhận diện một model bằng Manufacturer+Model, hoặc theo BIOS, hoặc Hardware ID; nên dùng điều kiện đủ cụ thể để tránh áp sang máy khác.

`installOrder` gồm `order`, `name`, `hardwarePatterns`, `recommendedVersion` (rỗng nếu không hạn chế nhánh), `queries` (chuỗi tìm Catalog), `links` (tuỳ chọn link HTTP/HTTPS chính thức). Không chứa lệnh script. `disable` chỉ dùng Hardware ID USB/ACPI cụ thể hoặc endpoint INTELAUDIO; không nhận PCI / bus cha hoặc pattern toàn bộ USB. Class controller/storage/network/System và service hub/storage còn được bảo vệ ở engine. `powerActions` nhận các ID có sẵn: `UsbSelectiveSuspendAc`, `PcieLinkStateAc`, `UsbHidDevicePower`, `SleepNeverAc`. Không chạy chuỗi lệnh tùy ý trong JSON.

Mọi profile đều phải đúng schema 1; lỗi sẽ được thông báo. Không cần tạo profile chỉ để cài driver thông thường.

## Profile mẫu SingPC

Dữ liệu do người dùng xác minh trên **SingPC I5-12450H BIOS 5.32**, AMI Aptio, Alder Lake-P/H, SUBSYS 72708086. Chỉ tự khớp khi cả Manufacturer, Model và BIOS đúng.

1. `ACPI\INTC1055`: Intel Serial IO GPIO, gói Catalog kèm I2C/SPI/UART 51xx.
2. `INTELAUDIO\DSP_CTLR_DEV_51C8&VEN_8086&DEV_0222`: Intel SST OED 10.29.0.x, đối chiếu BUS thực tế (máy mẫu 10.29.0.12181).
3. Thiết bị con AE50 / LINKTYPE 06, AE33 / LINKTYPE 03: tìm nhánh 10.29.0.x. Chỉ khi không dùng các tính năng này trên máy bàn và đã thử driver phù hợp mới cân nhắc disable từng thiết bị. Có nút xác nhận riêng, engine đọc lại InstanceId / Hardware ID, xác nhận Code 22 sau thao tác. Bật lại bằng Device Manager → Enable device.
4. BT LE Sideband / Detection Verification mới chỉ có tên trong dữ liệu được cung cấp: ghi chú để tìm ID thực tế, không tự disable theo tên.

Không ép hdaudbus.inf lên SST BUS do BIOS DSP mode. Phương án cuối xem tùy chọn Audio DSP trong BIOS bằng tay. Nguồn chỉ là tuỳ chọn được chọn từng mục: tắt USB selective suspend / PCIe link-state / sleep trên AC; giữ DC. WMI `MSPower_DeviceEnable` chỉ đổi đúng instance USB/HID (hoặc hậu tố `_n`), ghi giá trị trước; nếu không hỗ trợ thì báo thất bại / không có thiết bị áp dụng. Không tự khẳng định lỗi vật lý USB hoặc lỗi resume BIOS đã được sửa bởi driver.

## Kiểm thử tự động

Từ checkout mã nguồn, chạy trong Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File FixClone\Test-DriverFix.ps1
powershell.exe -NoProfile -STA -File FixClone\Test-DriverFixWpf.ps1
powershell.exe -NoProfile -STA -File App\Test-Wpf.ps1
```

Test engine mock CIM / pnputil / powercfg / WMI, kiểm tra URL encoding, profile, INF UTF16, ranh giới ID, version, Admin denial, CAB, lỗi lệnh, reboot, nhiều vòng, giới hạn 4 vòng, huỷ giữa gói, disable đọc lại Code 22, nguồn AC, WMI đúng instance, HTML và không có driver payload trong Git. Test WPF chỉ ValidateOnly và dữ liệu giả, không cài driver lên runner. Các test này không thay cho kiểm tra phần cứng.

## Hướng dẫn test trên máy có lỗi

1. Dùng một máy test / bản sao ổ có thể phục hồi. Ghi nhận Device Manager, phiên bản Windows và thiết bị không hoạt động trước xử lý. Mở app bằng quyền Admin.
2. Vào Fix Driver, chọn Code 28. Đối chiếu Name, Code, **toàn bộ** Hardware ID và InstanceId với Device Manager → Details. Thử thêm Code 10/43 nếu có; chúng có thể do phần cứng / BIOS chứ không chỉ driver.
3. Trên một máy **không phải SingPC**, xác nhận không áp profile SingPC nhưng link Catalog và các nút cài vẫn hoạt động. PCI/USB/ACPI/audio phải tạo query đúng, link mở trình duyệt mặc định và Copy lấy đủ ID.
4. Tải một CAB đúng Hardware ID và OS/kiến trúc từ Catalog. Chọn CAB, xem xác nhận, cài. Khi pnputil không chọn driver do rank hoặc lỗi chữ ký, xem log và danh sách lỗi; app không báo đã sửa nếu thiết bị còn mã lỗi.
5. So sánh Device Manager sau quét. Với gói driver cha, xác nhận thiết bị con mới xuất hiện trong danh sách và thông báo. Cài tiếp gói đúng ID của con. Nếu thiết bị biến mất, không được tính là Code 0.
6. Lặp lại bằng thư mục INF có khoảng trắng trong đường dẫn. Với kho USB/NAS, chuẩn bị INF cha và con rồi chạy kho: thứ tự / vòng có trong log; không quá 4 vòng, không thử vô hạn cùng gói. Thử kho không có ID phù hợp: không cài gì.
7. Trên SingPC đúng BIOS, đối chiếu SST BUS thực tế trước OED. Thử kho có cả 10.29.0.x và nhánh khác: chỉ chọn nhánh đề xuất. Chạy tới khi các con AE50 / AE33 xuất hiện. Disable chỉ sau khi xem mất tính năng; đọc lại Code 22, thử Enable device trong Device Manager.
8. Thử từng chỉnh nguồn riêng, so sánh `powercfg /query` và WMI trước/sau trong log, kiểm tra DC giữ nguyên. Trường hợp WMI không hỗ trợ phải hiện kết quả rõ. Thử USB idle / tắt màn hình, âm thanh, sleep/resume theo nhu cầu; không suy ra thành công chỉ từ exit code.
9. Khi đang cài kho, yêu cầu Dừng: gói hiện tại được phép hoàn tất; không cài gói sau. Không tắt máy giữa cài. Chủ động restart nếu log / trạng thái báo 3010, kiểm tra lại thiết bị và tính năng sau restart.
10. Xuất báo cáo HTML, kiểm tra CPU/board/BIOS/RAM, trước/sau, các gói/lệnh đã thử, Code 0, thiết bị biến mất, Code 22 và thiết bị còn thiếu kèm link. Giữ cả thư mục log khi cần phân tích lỗi. Báo cáo chứa tên máy và Hardware ID; kỹ thuật viên tự chọn nơi chia sẻ.
