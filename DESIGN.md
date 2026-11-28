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
