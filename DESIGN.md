# Quy ước thiết kế giao diện TechMaster Deploy

Áp dụng cho mọi cửa sổ WPF (`App\*.xml`, `FixClone\*.xml`, `Office\*.xml`). Phần lớn quy tắc được **áp tự động** khi cửa sổ mở bằng `Import-DeployWindow` (`App/Wpf.Runtime.ps1`), và được **kiểm tra tự động** bằng `App/Test-DesignRules.ps1` trong Windows CI. Thêm cửa sổ mới không cần làm gì thêm ngoài dùng đúng các khối dưới đây; nếu test báo lỗi thì sửa giao diện, không nới test.

## Màu và chữ

| Vai trò | Giá trị |
|---|---|
| Nền cửa sổ | `#F3F6FB` |
| Thẻ (Card) | nền `White`, viền `#DFE7F1`, bo `12`, padding `18` |
| Chữ chính / tiêu đề | `#10223F` |
| Chữ phụ / nhãn | `#526880`, cỡ `12` |
| Nút chính | nền `#214674`, chữ trắng |
| Nút phụ | nền `#E7EEF8`, chữ `#183655` |
| Viền ô nhập | `#C7D5E5` |
| Viền focus | `#38BDF8` |
| Font | Segoe UI `14`; mã / lệnh: Consolas |

## Bo góc

- **Nút**: bo `8` (template chung, tự áp cho mọi `Button` không có template riêng).
- **Ô nhập** (TextBox, PasswordBox, ComboBox): bọc trong `Border Tag="RoundedClip" CornerRadius="8" BorderBrush="#C7D5E5" BorderThickness="1" Background="White"`. Không đặt viền trên chính ô nhập (`BorderThickness="0"`).
- **CheckBox**: ô vuông bo `5`, tích màu `#214674`, chữ cách ô `8` (template chung, tự áp). Không tự vẽ CheckBox riêng; style riêng của cửa sổ chỉ nên đặt `Margin`.
- **Thẻ**: bo `12`. **Thông báo** (`Border Tag="Notice"`): theo `Set-DeployNotice`.

## Chiều cao và căn hàng

- **Ô nhập một dòng cao 40** (`$script:DeployInputHeight`). App tự đặt chiều cao cho khung `RoundedClip` chứa TextBox / PasswordBox / ComboBox; **không** đặt `MinHeight`, `Height` hay padding dọc trên ô nhập trong XAML. Ô nhiều dòng (`AcceptsReturn`, `TextWrapping="Wrap"`) hoặc khung đã có `Height` riêng thì giữ nguyên.
- **Ô nhập cùng hàng** (các cột của cùng một `Grid`) phải cùng chiều cao và cùng mép trên. Nhãn phía trên các ô cùng hàng giữ ngắn để không xuống dòng lệch nhau; giải thích dài đặt dưới hàng.
- **Nút đứng cạnh ô nhập** (cùng `Grid` và cùng `Grid.Row` với khung ô nhập) tự nhận chiều cao 40 và căn giữa theo hàng. Muốn nút cạnh ô nhập thì đặt cả hai trực tiếp trong một `Grid` nhiều cột, không lồng nút vào `StackPanel` / `WrapPanel` khác.
- Nút ở chân cửa sổ và nút đứng riêng: chiều cao theo template chung (padding `16,10`).

## Bố cục

- Cửa sổ con: dải tiêu đề `#10223F` (Heading 24, Subtitle `#BED2E9`), vùng nội dung cuộn, chân cửa sổ nền trắng chứa nút căn phải theo thứ tự: phụ → chính → Đóng.
- Mỗi chức năng một thẻ; một cửa sổ mở theo nút chỉ hiện phần của nút đó.
- Kiểm tra layout ở tỉ lệ 100 % và 150 % (test WPF của từng cửa sổ và `Test-DesignRules.ps1`).

## Nội dung chữ

- Tiếng Việt; thuật ngữ kỹ thuật, mã lỗi, tên file, lệnh giữ nguyên tiếng Anh.
- Trạng thái dùng ký hiệu thống nhất: `✓` đạt, `✗` lỗi cần xử lý, `!` cảnh báo thật, `–` thông tin. Không dùng `!` / khung vàng cho trạng thái bình thường (ví dụ lần đầu chưa nhập mật khẩu).

## Nguyên tắc xử lý lỗi trên máy

Mọi chức năng sửa lỗi / cấu hình máy chọn cách làm theo thứ tự ưu tiên dưới đây. Chỉ xuống bậc sau khi bậc trước không giải quyết được, và phải nói rõ cho người dùng vì sao.

1. **Giữ nguyên bảo mật của Windows.** Ưu tiên cách đúng chuẩn không cần hạ bảo mật: tài khoản có mật khẩu thay cho Guest / không mật khẩu, cài driver có chữ ký bằng quyền Administrator thay cho nới Point and Print, kết nối trực tiếp (ví dụ máy in theo IP) thay cho đường vòng phải mở thêm quyền.
2. **Rủi ro thấp nhất, phạm vi hẹp nhất.** Nếu buộc phải thay đổi: chỉ đổi trên máy đang xử lý (không đổi máy chủ / máy khác), chỉ đổi đúng thiết lập cần thiết, không đổi thiết lập dùng chung khi có cách riêng lẻ. Ví dụ: chế độ tương thích RPC chỉ đổi cách máy khách kết nối, không tắt `RpcAuthnLevelPrivacyEnabled` trên máy chủ.
3. **Đảo ngược được.** Sao lưu giá trị cũ trước khi ghi, có nút **Hoàn tác**, ghi nhật ký `*.jsonl`. Không xoá dữ liệu / driver / key khi không cần; thao tác không đảo ngược được phải hỏi xác nhận và nêu hậu quả.
4. **Kiểm tra trước, sửa sau.** Có bước **Kiểm tra** chỉ đọc; sau khi sửa luôn đọc lại để xác nhận, không báo thành công khi Windows chưa xác nhận.
5. **Không làm**: tắt bản vá bảo mật, bật Guest / đăng nhập không mật khẩu (`AllowInsecureGuestAuth`, `LimitBlankPasswordUse=0`), tắt tường lửa / Defender / UAC / SMB signing, cài driver không chữ ký, mở chia sẻ cho Everyone. Nếu người dùng tự làm các việc này bên ngoài app, app chỉ báo rủi ro, không tự làm thay.

Mỗi chức năng mới mô tả trong PR / `PROGRESS.md` cách làm đã chọn thuộc bậc nào và vì sao không dùng bậc cao hơn.
