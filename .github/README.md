# AppleALC – bản sửa cho Acer Nitro 5 AN515-57 (ALC295)

Đây là fork của [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) có thêm bản sửa âm thanh cho Acer Nitro 5 AN515-57 (codec Realtek ALC295, layout-id 13).
Code sửa nằm ở nhánh **`an515-57-pin-hold`**. README gốc của AppleALC: [README.md](../README.md).

## Bản sửa làm gì

Lỗi trên bản AppleALC gốc:
- Tai nghe có tiếng rè cao kiểu "muỗi kêu".
- Cắm/rút jack 3.5 mm bị kẹt, không chuyển giữa loa và tai nghe.

Nguyên nhân: layout 13 khai báo pin `0x19` (mic của jack combo) là mic ngoài.
AppleHDA vì thế chạy một vòng lặp liên tục trên pin này, khoảng 10.000 lệnh/giây, gây ra khoảng 10.000 ngắt/giây.
Chính vòng lặp này tạo ra tiếng rè và làm nghẽn việc nhận biết cắm/rút.

Cách sửa:
1. Trong layout 13, khai báo `0x19` là không dùng (N/C), nên vòng lặp biến mất.
2. Thêm property `alc-pin-hold`. Tai nghe 3 chấu trên máy này cần `0x19` luôn bật (D0, pinctl `0x22`), nếu không sẽ câm. AppleALC sẽ giữ pin này luôn bật:
   - Giữ ngay từ lúc khởi động codec (không rè trước lần phát đầu tiên).
   - Bật lại sau mỗi lần sleep/wake.
   - Giấu trạng thái "có jack cắm" của pin này, để mic trong không bị đổi thành "Line In".

Đánh đổi: không dùng được mic của tai nghe có mic (headset). Mic trong của laptop vẫn hoạt động bình thường.

## Cài đặt

1. Vào [Releases](../../releases) và tải file `AppleALC-x.y.z-RELEASE.zip` mới nhất.
2. Giải nén, chép `AppleALC.kext` vào `EFI/OC/Kexts/`, thay bản cũ.
3. Trong `config.plist`, mục `DeviceProperties → Add → PciRoot(0x0)/Pci(0x1f,0x3)` cần có:

   | Key | Type | Value |
   |---|---|---|
   | `layout-id` | Data | `0D000000` |
   | `alc-pin-hold` | Data | `1922` |
   | `alctcsel` | Data | `01000000` |

4. Lilu trong EFI cũng phải là bản mới, vì kext được build với Lilu mới nhất.
5. Reboot.

**Không** dùng file kext từ trang Releases của acidanthera. Bản đó không có bản sửa này.

### macOS 26 Tahoe

Tahoe đã xoá AppleHDA khỏi hệ thống. Vì vậy cần thêm [SimpleHDA](https://github.com/laobamac/SimpleHDA), một kext để OpenCore nạp lại AppleHDA lúc boot mà không đụng tới ổ hệ thống. Đã chạy được trên 26.7.1.

1. Chép `SimpleHDA.kext` vào `EFI/OC/Kexts/`.
2. Thêm vào `Kernel → Add`, đặt ngay sau AppleALC. Thứ tự đúng là Lilu → AppleALC → SimpleHDA. Đặt `MinKernel` = `25.0.0`.
3. Boot-args phải có `keepsyms=1`.
4. Đặt `NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82 → prev-lang:kbd` = `en:252` (kiểu Data hoặc String). Thêm cả key này vào mục `NVRAM → Delete` của cùng GUID. Nếu biến này rỗng, SimpleHDA sẽ đặt tên thiết bị âm thanh bằng tiếng Trung.

## Cập nhật khi AppleALC ra bản mới

- Không có gì tự build. Khi cần, vào **Actions → AN515-57 release → Run workflow**: nó lấy code AppleALC mới nhất, gắn bản sửa vào, build và đăng lên Releases.
- Nếu cả AppleALC gốc lẫn bản sửa đều chưa đổi gì, workflow sẽ không tạo release mới.
- Nếu workflow báo đỏ với dòng "patch no longer applies", nghĩa là code gốc đã đổi chỗ trùng với bản sửa. Khi đó cần sửa tay (rebase) nhánh `an515-57-pin-hold`.

## Build trên máy (không cần Xcode)

```bash
git clone -b an515-57-pin-hold https://github.com/ptnzzn/AppleALC && cd AppleALC
# cần thêm: MacKernelSDK/ (git clone acidanthera/MacKernelSDK) và Lilu.kext bản DEBUG (SDK) đặt trong thư mục này
mkdir -p build && clang++ -std=c++17 -fobjc-arc -framework Foundation ResourceConverter/main.mm -o build/ResourceConverter
PROJECT_DIR=$PWD TARGET_BUILD_DIR=$PWD/build ./ResourceConverter/generate.sh
./build-kext.sh   # → build/AppleALC.kext
```
