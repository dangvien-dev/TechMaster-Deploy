# Ghi chú cho trợ lý lập trình

- Giao diện WPF phải theo `DESIGN.md` (bo góc nút / ô nhập / CheckBox, ô nhập một dòng cao 40, ô và nút cùng hàng thẳng hàng). `App/Test-DesignRules.ps1` kiểm tra các quy tắc này trên mọi cửa sổ; khi test báo lỗi thì sửa giao diện, không nới test.
- File `.ps1` lưu UTF-8 **có BOM** (Windows PowerShell 5.1), xuống dòng LF. Sau khi đổi tệp chương trình, chạy `App/Build-UpdateIndex.ps1` để cập nhật `update-source.json`; CI kiểm bằng `-Check`.
- Tăng `version.txt`, ghi `CHANGELOG.md` và `PROGRESS.md` cho mỗi bản.
