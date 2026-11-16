# Kich-Hoat – Kích hoạt Windows / Office bán tự động

Bộ công cụ kích hoạt **Windows** và **Office** bằng key hợp lệ đã mua:

1. Thử kích hoạt **online** trước (không cần tài khoản).
2. Online thất bại thì chuyển sang **Product Activation Portal** của Microsoft
   (Installation ID → Confirmation ID).
3. Hỗ trợ làm portal trên **điện thoại**: quét QR lấy Installation ID, gửi Confirmation ID
   ngược về máy qua mạng LAN, không cần gõ tay.

> Công cụ **không** vượt qua bước xác minh của Microsoft. Key phải hợp lệ, số máy khai báo
> trên portal phải đúng sự thật.

---

## Danh sách file

| File | Chức năng |
|---|---|
| `Kich-Hoat-Windows.bat` | Kích hoạt Windows |
| `Kich-Hoat-Office.bat` | Kích hoạt Office (2016 trở lên) |
| `Kich-Hoat-TEST.bat` | Chạy thử quy trình QR + gửi qua LAN bằng **mã giả**, không thay đổi license |
| `Kich-Hoat.ps1` | Script chính (các file `.bat` gọi file này) |
| `QR-Template.html` | Trang hiển thị mã QR (nhúng thư viện `qrcode-generator`, MIT) |

Giữ **cả 5 file trong cùng một thư mục**. Các file `.bat` tự xin quyền Administrator.

---

## Yêu cầu

- Windows 10 / 11, PowerShell 5.1 (có sẵn)
- Đã nhập Product Key (Windows: Settings → Activation → Change product key; Office: nhập trong Word)
- Làm portal trên điện thoại: điện thoại và máy tính **chung Wi-Fi/LAN**
- Một tài khoản Microsoft để đăng nhập portal (nên dùng tài khoản của công ty, không dùng tài khoản cá nhân)

---

## Quy trình

```
Chạy Kich-Hoat-Windows.bat / Kich-Hoat-Office.bat
  │
  ├─ 1. Tìm sản phẩm đã nhập key nhưng chưa kích hoạt
  ├─ 2. Thử kích hoạt ONLINE ──── thành công → XONG
  │
  └─ 3. Kích hoạt qua Portal
        ├─ [1] Điện thoại (mặc định)
        │     • Máy mở trang có 2 mã QR
        │     • QR ①: quét → copy Installation ID → dán vào portal trên điện thoại
        │     • Portal cấp Confirmation ID (48 số) → copy
        │     • QR ②: quét → dán Confirmation ID → "Gửi về máy tính"
        │     • (Nhấn phím bất kỳ trên máy nếu muốn gõ tay)
        │
        └─ [2] Trên máy này
              • Installation ID đã copy sẵn vào clipboard, portal tự mở
              • Lấy Confirmation ID → copy → nhấn Enter trong script
  │
  └─ 4. Script nạp Confirmation ID → hiện trạng thái kích hoạt
```

**Địa chỉ portal**

| Sản phẩm | Portal |
|---|---|
| Windows | `https://aka.ms/WindowsActivate` → chọn **Activate a Microsoft Product** |
| Office | `https://visualsupport.microsoft.com/` |

Portal Windows có thể hiển thị "Windows 10" dù máy chạy Windows 11. Đây là bình thường
(Windows 11 dùng nhân 10.0, key dùng chung).

---

## Chạy thử (không cần máy chưa kích hoạt)

Chạy `Kich-Hoat-TEST.bat` trên máy bất kỳ, rồi kiểm tra:

1. Quét QR ① → hiện `1234567 1234567 …` (9 nhóm)
2. Quét QR ② → mở trang "Gửi Confirmation ID"
3. Gửi thiếu số → điện thoại báo lỗi, script vẫn chờ
4. Gửi đủ 48 số bất kỳ → script báo **TEST THÀNH CÔNG** và **Đã đóng cổng tường lửa tạm**

---

## Bảo mật khi nhận qua LAN

- Cổng nhận (`HttpListener`) mở ở cổng ngẫu nhiên 20000–40000, đường dẫn có mã ngẫu nhiên 12 ký tự.
- Rule tường lửa tạm `KichHoat-CID-Temp` chỉ tồn tại trong lúc chờ, tự xoá khi xong hoặc khi bấm Ctrl+C.
- Chỉ nhận đúng 48 chữ số. Gửi nhầm Installation ID (63 số) sẽ bị từ chối.

---

## Xử lý sự cố

| Hiện tượng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Online báo `0xC004C008` | Key đã kích hoạt trên máy khác | Một key Retail/OEM chỉ dùng cho 1 máy. Đã dùng ở máy khác thì cần key mới; key mới mua mà vẫn báo lỗi thì liên hệ nơi bán |
| Điện thoại báo **"The request is blocked."** | Tường lửa web Azure (WAF) của Microsoft chặn | Mở portal từ trang đầu (không mở thẳng `/captcha`), tắt VPN/DNS chặn quảng cáo, xoá cookie trang, đổi Wi-Fi ↔ 4G. Vẫn bị chặn thì chọn **[2] Trên máy này** |
| Không đăng nhập Microsoft được trên điện thoại | Trình duyệt nhúng (Zalo, Messenger…), chặn popup/cookie, chế độ ẩn danh | Mở bằng Chrome/Safari, cho phép popup + cookie bên thứ ba |
| Quét QR ② không mở được trang | Khác mạng, hoặc router bật **AP/Client isolation** | Cho điện thoại và máy tính chung mạng, hoặc nhấn phím bất kỳ để gõ tay |
| Nạp Confirmation ID thất bại | Confirmation ID không khớp Installation ID | Lấy lại Confirmation ID từ **đúng** Installation ID đang hiện trên máy |

---

## Trạng thái kiểm tra

| Phần | Trạng thái |
|---|---|
| Tạo QR ① / QR ② (giải mã lại đúng nội dung) | ✅ Đã kiểm tra |
| Nhận Confirmation ID qua LAN, kiểm tra 48 số, đóng tường lửa | ✅ Đã chạy thực tế (`Kich-Hoat-TEST.bat`) |
| Nạp Confirmation ID thật vào Windows/Office (`DepositOfflineConfirmationId`) | ⏳ Chưa chạy với Confirmation ID thật |
