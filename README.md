# Bộ script kiểm tra laptop mới & cài đặt ứng dụng

Repo gồm 2 bộ script dành cho Windows 10/11:

1. **Kiểm tra toàn diện máy mới** – thu thập thông tin phần cứng, chạy test tay và xuất báo cáo Markdown + HTML.
2. **Cài đặt ứng dụng** – kiểm tra ứng dụng đã có, chỉ tải/cài những ứng dụng còn thiếu.

> Không cần cài Python hay phần mềm phụ. Chỉ cần Windows PowerShell có sẵn trên Windows.

---

## Danh sách file

| File | Chức năng |
|---|---|
| `KiemTraMayMoi.ps1` | Script chính kiểm tra máy, test tay và xuất báo cáo |
| `ChayKiemTra.bat` | Chạy nhanh script kiểm tra với quyền Administrator |
| `CaiDatApp.ps1` | Script kiểm tra và cài ứng dụng còn thiếu |
| `ChayCaiDatApp.bat` | Chạy nhanh script cài app với quyền Administrator |
| `README.md` | Hướng dẫn sử dụng |

**Giữ tất cả file trong cùng một thư mục.** Các file `.bat` sẽ tự tìm file `.ps1` tương ứng.

---

## 1. Kiểm tra laptop mới

### Chạy nhanh

1. Double-click **`ChayKiemTra.bat`**.
2. Windows hiện UAC → chọn **Yes** để cấp quyền Administrator.
3. Làm theo hướng dẫn trên cửa sổ PowerShell.

Script sẽ kiểm tra tự động các thông tin như:

- Hãng máy, model, serial, BIOS, bo mạch chủ
- Windows, phiên bản, kích hoạt bản quyền
- CPU, RAM từng khe, ổ cứng, SMART, GPU, màn hình
- Pin: dung lượng thiết kế, độ chai, số chu kỳ
- Wi-Fi, Bluetooth, cổng kết nối, USB
- Bảo mật: TPM, Secure Boot, BitLocker, Defender, Firewall
- Windows Update, lỗi hệ thống, phần mềm đã cài
- Nhiệt độ, dịch vụ hệ thống

### Test tay mặc định

Script sẽ hỏi và tự mở công cụ cho 4 mục:

1. **Loa** – phát 1 tiếng bíp ngắn.
2. **Micro** – mở ứng dụng ghi âm để thu và phát lại.
3. **Camera** – mở ứng dụng Camera.
4. **Bàn phím** – mở sơ đồ bàn phím trên màn hình:
   - Nhấn phím thật, phím tương ứng chuyển xanh.
   - Phím đặc biệt như `Fn`, `PrtSc`, `Pause` có thể click để đánh dấu.
   - Có nút **LÀM LẠI** và **XONG**.
   - Báo cáo ghi lại số phím đã test và các phím chưa test.

Với mỗi mục, nhập:

- `1` = Đạt
- `2` = Không đạt
- `0` = Bỏ qua
- `q` = Dừng phần test tay

Có thể nhập ghi chú tình trạng sau mỗi mục.

### Chạy đầy đủ các bài test cũ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\KiemTraMayMoi.ps1" -FullManual
```

Chế độ này bật thêm test màn hình, cảm ứng, touchpad, sạc/pin, vân tay.

### Chỉ lấy thông tin, không test tay

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\KiemTraMayMoi.ps1" -SkipManual
```

### Kết quả báo cáo

Báo cáo được tạo trong:

```text
BaoCaoKiemTra\<TÊN_MÁY>_<ngày_giờ>\
├─ BaoCao_KiemTra_<TÊN_MÁY>_<ngày_giờ>.md
├─ BaoCao_KiemTra_<TÊN_MÁY>_<ngày_giờ>.html
├─ pin-chi-tiet.html
└─ assets\
```

File HTML tự mở sau khi kiểm tra xong. Giao diện HTML có bảng **Thông tin chung**, sidebar mục lục, kết quả test tay và các mục chi tiết.

### Tùy chọn hữu ích

```powershell
-Technician "Tên kỹ thuật viên"
-Customer "Mã đơn"
-OutputFolder "D:\BaoCao"
-NoOpen
-AllTests
-NoElevate
```

---

## 2. Cài đặt ứng dụng

### Chạy nhanh

1. Double-click **`ChayCaiDatApp.bat`**.
2. Chọn **Yes** khi Windows hỏi Administrator.

Script kiểm tra các ứng dụng:

- Telegram Desktop
- Viber
- WhatsApp
- Microsoft Office / Microsoft 365
- UniKey
- Google Chrome

**Nếu ứng dụng đã có — kể cả bản cũ — script sẽ bỏ qua, không tải lại.** Nếu chưa có, script mới cài bản mới nhất.

### Kiểm tra trước khi cài

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\CaiDatApp.ps1" -CheckOnly
```

Chế độ này chỉ hiển thị trạng thái, không cài và không thay đổi cấu hình.

### Tùy chọn

```powershell
-SkipOffice             # Không cài Office
-SkipDefaultBrowser     # Không mở phần đặt trình duyệt mặc định
-DownloadFolder "D:\AppInstallers"
-NoElevate
```

Ví dụ:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\CaiDatApp.ps1" -SkipOffice
```

### Nguồn cài đặt

- Telegram, Viber, WhatsApp, Office, Chrome: ưu tiên **winget**.
- Nếu winget không cài được, script tải installer chính thức vào:

```text
Downloads\AppInstallers\
```

- UniKey: tải bản mới nhất từ `unikey.org`, cài vào Program Files và tạo shortcut khởi động.
- Installer tải trực tiếp được kiểm tra chữ ký số trước khi chạy.
- Log lưu tại:

```text
Downloads\AppInstallers\CaiDatApp_<ngày_giờ>.log
```

### Google Chrome

Script sẽ:

- Cài Chrome bản mới nhất nếu chưa có.
- Đặt **Google** làm công cụ tìm kiếm mặc định bằng Chrome policy.
- Cố gắng mở trang đặt Chrome làm trình duyệt mặc định.

**Lưu ý:** Windows 10/11 không cho phép script đặt trình duyệt mặc định hoàn toàn tự động. Khi cửa sổ **Default apps** mở ra, bạn cần chọn **Google Chrome → Set default**.

Nếu không muốn policy Google Search, có thể xóa khóa:

```text
HKLM\SOFTWARE\Policies\Google\Chrome
```

### Microsoft Office

- Nếu máy chưa có Office, script cài **Microsoft 365 Apps** bản mới nhất.
- Cần đăng nhập tài khoản Microsoft 365 để kích hoạt.
- Nếu không cần Office, dùng `-SkipOffice`.

---

## Yêu cầu hệ thống

- Windows 10 hoặc Windows 11
- Windows PowerShell 5.1 trở lên
- Kết nối Internet khi cài ứng dụng
- Quyền Administrator để đọc đầy đủ TPM/SMART/BitLocker và cài ứng dụng

---

## Xử lý sự cố

### File `.ps1` không chạy khi double-click

Windows thường mở file `.ps1` bằng Notepad. Hãy dùng file `.bat` hoặc chạy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\KiemTraMayMoi.ps1"
```

### Console hiển thị tiếng Việt bị lỗi

Script tự chuyển console sang font **Consolas**. Nếu vẫn lỗi, chuột phải thanh tiêu đề console → **Properties → Font → Consolas**.

### Không đọc được TPM, SMART, BitLocker

Chạy lại bằng quyền Administrator:

```text
Chuột phải PowerShell → Run as administrator
```

### Chrome chưa phải trình duyệt mặc định

Windows chặn đặt mặc định tự động. Trong cửa sổ **Default apps** vừa mở, chọn **Google Chrome → Set default**.

### Office chưa kích hoạt

Mở Word/Excel → đăng nhập tài khoản Microsoft 365 có bản quyền.

---

## Ghi chú

- Báo cáo kiểm tra máy có chứa serial, tên máy, SSID Wi-Fi. Cẩn thận khi chia sẻ công khai.
- Script không tự động xóa dữ liệu, không gỡ ứng dụng.
- Nếu ứng dụng đã cài bản cũ, script giữ nguyên và bỏ qua theo yêu cầu.
- Khi cài ứng dụng, nên đóng các ứng dụng đang chạy để tránh cần khởi động lại.

---

## Tác giả / Repo

GitHub: [Alextrinh59/Script-for-new-laptop](https://github.com/Alextrinh59/Script-for-new-laptop)
