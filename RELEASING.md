# Phát hành phiên bản TechMaster Deploy

## Cập nhật trực tiếp từ repo (mặc định từ v1.1.1.0)

Nguồn cố định: **dangvien-dev/TechMaster-Deploy**, nhánh **main**. Không dùng repository TechMaster Pro, không cần GitHub Release hoặc file feed ở repo khác.

Mỗi lần có bản mới:

1. Sửa mã nguồn và `CHANGELOG.md`; tăng số trong `version.txt` để người dùng thấy rõ phiên bản.
2. Chạy các kiểm tra phù hợp.
3. Sau khi được phép ghi lên GitHub, commit và push các thay đổi lên nhánh `main`.
4. Người dùng bấm **Cập nhật từ repo**. App chốt commit, đọc cây Git và đối chiếu Git blob, chỉ tải tệp thay đổi, dựng launcher bằng trình biên dịch .NET Framework của Windows rồi áp dụng qua giao dịch có sao lưu.

Không cần build / upload ZIP cho mỗi lần thay đổi trên repo. Nếu có commit mới cùng số phiên bản, updater vẫn nhận diện bằng commit; không tự hạ xuống số phiên bản thấp hơn. Một checkout có thay đổi chưa commit được đánh dấu `dirty` trong ZIP cài ban đầu; không coi mã chỉ có cục bộ là mã đã công bố.

Repo public không cần token. Repo private dùng token Contents: Read lưu riêng bằng DPAPI trên máy Windows, chỉ gửi qua HTTPS tới GitHub API của repo cố định. Token không đi vào ZIP hoặc backup. Tính năng đọc GitHub không cấp quyền push và không đổi mức công khai của repo.

## ZIP cài ban đầu / chuyển offline

Tại checkout trên Windows, với Git và Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File App\Build-Release.ps1 -Version 1.1.1.0 -OutputDirectory C:\TechMaster-Releases\1.1.1.0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File App\Build-UpgradeHelper.ps1 -OutputDirectory C:\TechMaster-Releases\1.1.1.0
```

Builder tạo ZIP, `update-package.json` nội bộ, SHA256 và xác minh gói vừa tạo. `-LauncherPath` cho phép dùng launcher đã build. ZIP đầy đủ dùng cho cài mới và cập nhật offline; không sửa cấu hình người dùng trong checkout.

`TechMaster Update.exe` nhúng updater để nâng cấp một lần từ các bản chưa có tab cập nhật repo. Chọn thư mục app đang dùng, chọn Yes để lấy trực tiếp từ repo; No để chọn ZIP offline, không cần giải nén đè thủ công. Các ZIP thử trước v1.1.0.0 không có manifest nên không phải gói cập nhật offline hợp lệ.

## Kiểm tra và dữ liệu giữ lại

```powershell
powershell.exe -NoProfile -File App\Test-Update.ps1
powershell.exe -NoProfile -File App\Test-RepoUpdate.ps1
```

Updater giữ cấu hình / logo biên bản, biên bản đã xuất, KhoOffice, Office/ODT, FixClone/Logs, FixClone/Reinstall, shortcut và desktop.ini. Tệp chương trình sửa riêng sẽ khiến updater dừng thay vì ghi đè.

Biên nhận và sao lưu ở `.updates`. Quay lại chỉ khôi phục chương trình, không đưa dữ liệu cá nhân về quá khứ. Không xoá `.updates` khi còn muốn quay lại. Gói lỗi checksum, thiếu tệp, cây Git không đầy đủ hoặc công cụ vẫn đang chạy đều khiến updater dừng. Khi lỗi giữa giao dịch, updater thử khôi phục từ backup và báo rõ kết quả.

Chuẩn bị ZIP / công cụ nâng cấp hoặc chỉnh checkout không tự commit, push hoặc công khai repo. Cần kiểm tra giao diện, API GitHub và đóng / mở lại app trên Windows thực tế sau khi mã đã lên repo.
