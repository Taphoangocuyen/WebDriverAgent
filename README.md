# DrakoCtrl — WDA Builder

Build WebDriverAgent IPA cho **TrollStore** — nhấn icon trên iPhone là WDA tự khởi động.

## Tính năng

- Build trên cloud (GitHub Actions) — không cần Mac
- Cài qua TrollStore — không cần Apple cert, không cần ký
- Nhấn icon trên iPhone → WDA tự khởi động
- Double-layer IPC auth guard (route prefix + auth header)
- Tuỳ chỉnh tên, icon, Bundle ID, Min iOS version

## Hướng dẫn

### Bước 1: Push repo lên GitHub

Tạo repo **Private** trên GitHub:

```bash
cd wda-builder-auth
git init
git add -A
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/wda-builder.git
git push -u origin main
```

### Bước 2: Cài Auth Key (tuỳ chọn)

Nếu muốn bảo vệ WDA bằng IPC auth:

1. Repo → **Settings** → **Secrets and variables** → **Actions**
2. Thêm secret `IPC_AUTH_KEY` với key bất kỳ (32+ ký tự)

### Bước 3: Chạy Build

1. Repo → Tab **Actions** → **Build DrakoCtrl WDA for TrollStore**
2. **Run workflow** → tuỳ chỉnh:
   - `bundle_id`: Bundle ID (mặc định: `com.facebook.WebDriverAgentRunner`)
   - `display_name`: Tên hiển thị (mặc định: `DrakoCtrl`)
   - `auth_key`: Auth key (hoặc để trống nếu dùng secret)
   - `min_ios_version`: iOS tối thiểu (mặc định: `15.0`)
3. Nhấn **Run** → đợi ~15 phút

### Bước 4: Cài lên iPhone qua TrollStore

1. Tải `DrakoCtrl.ipa` từ **Artifacts**
2. Chuyển IPA sang iPhone (AirDrop, Safari, USB...)
3. Mở bằng **TrollStore** → nhấn **Install**
4. Nhấn icon app → WDA tự khởi động!

## Cấu trúc

```
├── .github/workflows/build-wda.yml    ← Workflow chính (GitHub Actions)
├── src/
│   ├── FBPhotoCommands.h/.m           ← Route /wda/importPhoto, /wda/importVideo
│   └── IPCAuthGuard.m                 ← KHÔNG còn dùng (xem mục Bảo mật)
├── scripts/
│   ├── patch_auth.py                  ← Vá auth vào RoutingConnection.m
│   ├── add_photo_commands.sh          ← Chép FBPhotoCommands vào cây WDA
│   ├── add_to_xcode.rb                ← Thêm FBPhotoCommands + link Photos.framework
│   └── customize_wda.sh               ← Tên hiển thị, quyền, MinOS...
├── resources/
│   ├── entitlements.plist             ← TrollStore entitlements
│   ├── icon.png                       ← App icon
│   └── libXCTestSwiftSupport.dylib    ← Bản nhẹ, thay bản nặng của Xcode
└── README.md
```

## Bảo mật — Auth một lớp (source patch)

`auth_key` là **bắt buộc**. Không truyền vào ô nhập thì workflow lấy repository
secret `IPC_AUTH_KEY`; không có cả hai thì build dừng. Key ngắn hơn 16 ký tự
cũng bị từ chối.

**Source Patch** (`patch_auth.py`) — vá thẳng vào `RoutingConnection.m`:
- Request phải có route prefix: `/ipc_XXXXXXXX/session` (thay vì `/session`)
- Request phải có header: `X-IPC-Auth: <key>`
- Không đúng → WDA trả "unknown command"

**Whitelist** (không cần auth):
- `/status` — health check cơ bản
- `/health` — health check bổ sung

> **Layer 2 (swizzle) đã bị bỏ.** Trước đây `src/IPCAuthGuard.m` hook
> `httpResponseForMethod:URI:` làm lớp dự phòng. Nó không còn được thêm vào
> Xcode project nữa (xem `scripts/add_to_xcode.rb`) — file còn nằm trong repo
> nhưng **không được biên dịch**. Lý do bỏ: source patch chạy inline nên không
> có đường vòng để bypass, còn swizzle thì phụ thuộc thứ tự nạp và từng làm
> build gãy. Đừng dựa vào nó.

## Yêu cầu iPhone

- iOS 15.0+ (configurable)
- TrollStore đã cài sẵn
- ldid đã cài trong TrollStore Settings
