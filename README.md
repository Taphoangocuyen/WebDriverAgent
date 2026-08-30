# DrakoCtrl — WDA Builder

Build WebDriverAgent IPA cho **TrollStore** — nhấn icon trên iPhone là WDA tự khởi động.

## Tính năng

- Build trên cloud (GitHub Actions) — không cần Mac
- Cài qua TrollStore — không cần Apple cert, không cần ký
- Nhấn icon trên iPhone → WDA tự khởi động
- IPC auth guard: route prefix + header `X-IPC-Auth` (vá thẳng vào source)
- Route tuỳ biến: nhập ảnh/video vào thư viện Ảnh, và **dán chữ qua bảng dán**
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

### Bước 2: Cài Auth Key (BẮT BUỘC)

Không có key thì workflow **dừng**, không build. Key ngắn hơn 16 ký tự cũng bị
từ chối. Key này phải **trùng** với `.auth_key` của app desktop, nếu không app
sẽ không gọi được WDA.

1. Repo → **Settings** → **Secrets and variables** → **Actions**
2. Thêm secret `IPC_AUTH_KEY` (32+ ký tự)

### Bước 3: Chạy Build

1. Repo → Tab **Actions** → **Build DrakoCtrl WDA for TrollStore**
2. **Run workflow** → tuỳ chỉnh:
   - `bundle_id`: Bundle ID (mặc định: `com.facebook.WebDriverAgentRunner`)
   - `display_name`: Tên hiển thị dưới icon trên iPhone (mặc định: `DRAKO`)
   - `ipa_filename`: Tên file IPA xuất ra (mặc định: `DrakoCtrl`). **Giữ nguyên** —
     app desktop tìm file theo đúng tên `DrakoCtrl.ipa` trong thư mục tài nguyên
   - `auth_key`: để trống thì lấy secret `IPC_AUTH_KEY`
   - `min_ios_version`: iOS tối thiểu (mặc định: `15.0`)
   - `wda_version`: **giữ nguyên `v11.4.0`**. Để trống sẽ lấy bản mới nhất
     (≥ v16.7.0 đã gỡ RoutingHTTPServer → `patch_auth.py` fail). Ghim
     `v11.4.1` thì build được nhưng điều khiển kém mượt.
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
│   ├── FBPasteCommands.h/.m           ← Route /wda/paste, /wda/setClipboard
│   └── IPCAuthGuard.m                 ← KHÔNG còn dùng (xem mục Bảo mật)
├── scripts/
│   ├── patch_auth.py                  ← Vá auth vào RoutingConnection.m
│   ├── add_photo_commands.sh          ← Chép lệnh tuỳ biến vào cây WDA
│   ├── add_to_xcode.rb                ← Thêm 2 lệnh tuỳ biến + link Photos.framework
│   └── customize_wda.sh               ← Tên hiển thị, quyền, MinOS...
├── resources/
│   ├── entitlements.plist             ← TrollStore entitlements
│   ├── icon.png                       ← App icon
│   └── libXCTestSwiftSupport.dylib    ← Bản nhẹ, thay bản nặng của Xcode
└── README.md
```

## Route tuỳ biến của repo này

Không có trong appium/WebDriverAgent gốc. Mọi request đều phải mang route prefix
và header `X-IPC-Auth` như các route khác.

### Nhập ảnh/video

```
POST /wda/importPhoto   {"value": "<base64 ảnh>"}
POST /wda/importVideo   {"value": "<base64 video>", "extension": "mp4|mov|m4v"}
```

### Dán chữ

WDA gốc có sẵn `/wda/setPasteboard`, nhưng nó **chỉ ghi bảng dán**: chữ nằm
trong bộ nhớ tạm chứ không vào ô nhập. Repo này bổ sung phần dán thật.

Đáng làm vì `/wda/keys` gõ **từng ký tự** qua bàn phím iOS. Đo trên máy thật:

| | 350 ký tự |
|---|---|
| `/wda/keys` (gõ từng ký tự) | ~9.000ms |
| Đường bảng dán (3 nhịp dưới đây) | **206ms** |

#### Luồng ba nhịp — đây là cách dùng đúng

**iOS CHẶN ghi bảng dán khi WDA chạy nền** (đo trên iOS 15.8). Mà trong luồng
thật, đúng lúc cần dán thì WDA luôn đã về nền. Nên phải tách làm ba nhịp, bên
gọi tự lo việc chuyển app:

```
đưa WDA lên tiền cảnh          142ms
POST /wda/setClipboard          43ms
về app đích                     21ms
POST /wda/pasteOnly
```

Bàn phím của app đích **vẫn còn** sau khi quay lại, nên ô nhập không mất tiêu điểm.

```
POST /wda/setClipboard
{"value": "<chữ cần dán>"}          // chuỗi UTF-8 thẳng, không base64

POST /wda/pasteOnly
{
  "strategy":    "auto",             // auto | cmdv | menu
  "verify":      true,               // đọc lại ô nhập để xác nhận chữ đã vào
  "timeout":     3.0,                // giây chờ mục "Dán" hiện ra
  "pasteLabels": ["Dán", "Paste"]    // cộng thêm nhãn, không thay danh sách mặc định
}
```

Trả về khi được:

```json
{"value": {"strategy": "menu", "clipboard": false, "pasted": true, "verified": true}}
```

`"clipboard": false` ở đây nghĩa là *lệnh này không ghi bảng dán* — đúng như thiết
kế của `pasteOnly`, không phải báo hỏng.

#### `/wda/paste` — gộp hai nhịp vào một

```
POST /wda/paste
{"value": "<chữ>", "strategy": "auto|cmdv|menu|clipboard", ...}
```

Chỉ dùng được khi WDA **đang ở tiền cảnh**. Trong luồng điều khiển bình thường
thì nó trả `PASTE_CLIPBOARD_BLOCKED` — hãy dùng luồng ba nhịp ở trên.

#### Hai đường dán

| strategy | Cách làm | Yêu cầu | Tốc độ |
|---|---|---|---|
| `cmdv` | `typeKey:@"v" modifierFlags:Command` | **iOS 17+** | nhanh |
| `menu` | Nhấn giữ ô nhập → bấm mục "Dán" trong thực đơn | iOS 15+ | ~1-2s |

`auto` thử `cmdv` trước rồi mới tới `menu`. Máy dưới iOS 17 thì `cmdv` bị loại
ngay, không tốn round-trip nào.

Đường `menu` không làm iOS hỏi "Cho phép dán?": iOS coi cú bấm vào mục Dán là
người dùng chủ động, khác với việc app tự đọc bảng dán bằng mã.

> **Lưu ý về vị trí con trỏ.** Nhấn giữ đặt lại con trỏ vào chỗ ngón tay chạm —
> giữa ô nhập. Ô trống thì không sao. Ô **đã có chữ** thì chữ dán vào sẽ chèn
> giữa đoạn cũ chứ không nối vào cuối.

#### Chọn hết và sao chép

```
POST /wda/selectAll
{"timeout": 3.0, "selectAllLabels": ["Chọn tất cả", "Select All"]}

POST /wda/copy
{"selectAll": true, "timeout": 3.0,
 "copyLabels": [...], "selectAllLabels": [...]}
```

`/wda/copy` **chỉ sao chép, không đọc về**. Muốn lấy chữ về máy tính thì vẫn
phải đưa WDA lên tiền cảnh rồi gọi `/wda/getPasteboard` (route sẵn có của WDA
gốc) — cùng bức tường của `setClipboard` nhưng ở chiều ngược lại.

Kết quả của `/wda/copy`:

```json
{"value": {"copied": true, "selectedAll": true,
           "clipboardChanged": true, "value": "chữ trong ô"}}
```

- `value` là giá trị **ô nhập** đọc được lúc sao chép, KHÔNG phải nội dung bảng
  dán. Thường trùng nhau khi `selectAll: true`, nhưng đừng coi là bằng chứng.
- `clipboardChanged` chỉ là dấu hiệu tham khảo: cùng lý do iOS chặn *ghi* bảng
  dán lúc chạy nền, `changeCount` cũng có thể đọc ra số cũ.

`selectAll` cũng dùng được như một tuỳ chọn của `/wda/pasteOnly` và `/wda/paste`
để **dán đè** thay vì chèn vào giữa:

```
POST /wda/pasteOnly   {"selectAll": true}
```

Mặc định `false` — nó xoá chữ sẵn có trong ô, mà bên gọi mới biết ô đó có đáng
xoá hay không.

#### Hai route KHÔNG thêm

Panda Helper (một bản WDA đóng gói lại) có `/wda/pushPasteboard` và
`/wda/pullPasteboard`. Repo này không thêm vì đã có sẵn hai đường làm đúng việc
đó: `/wda/setPasteboard` + `/wda/getPasteboard` của WDA gốc, và
`/wda/setClipboard` ở trên. Thêm nữa chỉ tạo ra ba cách làm một việc.

#### Mã lỗi

Bên gọi khớp theo tiền tố để biết có nên lùi về `/wda/keys` không:

| Mã | Nghĩa |
|---|---|
| `PASTE_BAD_ARG` | Tham số sai |
| `PASTE_CLIPBOARD_BLOCKED` | iOS không cho WDA ghi bảng dán lúc chạy nền |
| `PASTE_NO_FOCUS` | Không ô nhập nào đang được chọn |
| `PASTE_CMDV_FAILED` | Máy dưới iOS 17, hoặc Command+V không ăn |
| `PASTE_FAILED` | Cả hai đường đều trượt |

> Các endpoint **không** tự đưa WDA lên tiền cảnh rồi quay lại app hộ bên gọi.
> Chuyển app là việc nhìn thấy được trên màn hình người dùng — bên máy tính mới
> biết lúc nào làm là hợp lý.

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
