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
├── src/IPCAuthGuard.m                 ← Auth guard Layer 2 (swizzle backup)
├── scripts/
│   ├── patch_auth.py                  ← Auth guard Layer 1 (source patch)
│   ├── customize_wda.sh               ← Tuỳ chỉnh WDA (permissions, MinOS...)
│   └── add_to_xcode.rb               ← Thêm IPCAuthGuard.m vào Xcode project
├── resources/
│   ├── entitlements.plist             ← TrollStore entitlements
│   └── icon.png                       ← App icon
└── README.md
```

## Bảo mật — Double-Layer Auth

Khi build với `auth_key`, WDA được bảo vệ 2 lớp:

**Layer 1 — Source Patch** (`patch_auth.py`):
- Inject auth check trực tiếp vào `RoutingConnection.m`
- Request phải có route prefix: `/ipc_XXXXXXXX/session` (thay vì `/session`)
- Request phải có header: `X-IPC-Auth: <key>`
- Không đúng → WDA trả "unknown command"

**Layer 2 — Swizzle Backup** (`IPCAuthGuard.m`):
- Hook `httpResponseForMethod:URI:` qua method swizzling
- Kiểm tra route prefix + auth header
- Trả HTTP 403 nếu không hợp lệ
- Backup nếu Layer 1 bị bypass

**Whitelist** (không cần auth):
- `/status` — health check cơ bản
- `/health` — health check bổ sung

## Yêu cầu iPhone

- iOS 15.0+ (configurable)
- TrollStore đã cài sẵn
- ldid đã cài trong TrollStore Settings
