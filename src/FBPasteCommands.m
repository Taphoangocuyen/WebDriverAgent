/**
 * FBPasteCommands — Dán chữ vào ô nhập bằng bảng dán của iOS
 * Custom command cho WebDriverAgent (DrakoCtrl)
 *
 * POST /wda/setClipboard
 *   {"value": "<chữ>"}
 *
 * POST /wda/pasteOnly
 *   {"strategy": "auto|cmdv|menu", "verify": true, "timeout": 3.0,
 *    "pasteLabels": ["Dán","Paste"]}
 *
 * POST /wda/paste  — gộp hai lệnh trên vào một
 *   {"value": "<chữ>", "strategy": "auto|cmdv|menu|clipboard", ...}
 *
 * ── Vì sao có file này ────────────────────────────────────────────────────
 * WDA gốc đã có /wda/setPasteboard, nhưng nó DỪNG ở chỗ ghi bảng dán: chữ nằm
 * trong bộ nhớ tạm chứ không vào ô nhập. Muốn nó vào ô thì vẫn phải có một cú
 * dán thật trên máy. File này làm nốt phần đó, và trả về cho máy tính biết cách
 * nào đã ăn — để bên kia còn quyết định có lùi về gõ từng ký tự hay không.
 *
 * ── Hai đường dán, thử theo thứ tự ────────────────────────────────────────
 * 1. cmdv — [element typeKey:@"v" modifierFlags:Command]. Nhanh nhất, không
 *    phải quét cây phần tử. Nhưng API này chỉ có từ iOS 17 và bản dựng phải là
 *    Xcode 15 trở lên, nên máy cũ sẽ rơi xuống đường 2.
 * 2. menu — nhấn giữ ô nhập cho hiện thực đơn sửa chữ rồi bấm mục "Dán".
 *    Chậm hơn (~1-2 giây) nhưng chạy được từ iOS 15, và quan trọng hơn: iOS
 *    coi cú bấm này là NGƯỜI DÙNG chủ động dán nên KHÔNG hỏi "Cho phép dán?"
 *    như khi app tự đọc bảng dán bằng mã.
 *
 * ── Vì sao có /wda/pasteOnly tách riêng ───────────────────────────────────
 * Đo trên máy thật (iOS 15.8): iOS CHẶN ghi bảng dán khi WDA chạy nền. Mà
 * trong luồng thật, đúng lúc cần dán thì WDA luôn đã về nền. Nên /wda/paste
 * (gộp ghi + dán) chết ngay ở bước ghi, dù bảng dán đã có sẵn đúng nội dung.
 *
 * Luồng chạy được là ba nhịp, bên gọi tự lo hai nhịp đầu:
 *   đưa WDA lên tiền cảnh → /wda/setClipboard → về app đích → /wda/pasteOnly
 * Đo thực tế: 142ms + 43ms + 21ms = 206ms cho 350 ký tự, so với ~9.000ms nếu
 * gõ từng ký tự qua /wda/keys. Bàn phím vẫn còn sau khi quay lại app đích.
 *
 * ── Cái không làm ─────────────────────────────────────────────────────────
 * Không tự đưa WDA lên tiền cảnh rồi quay lại app hộ bên gọi. Chuyển app là
 * việc nhìn thấy được trên màn hình người dùng, và bên máy tính mới biết lúc
 * nào làm là hợp lý — làm lén trong một route thì nó nháy màn hình vào những
 * lúc không ai ngờ.
 */

#import "FBPasteCommands.h"

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBResponsePayload.h"
#import "FBRunLoopSpinner.h"
#import "XCUIApplication+FBHelpers.h"

#pragma mark - Hằng số

/// Nhấn giữ bao lâu thì iOS hiện thực đơn sửa chữ. Dưới ~0,5s bị hiểu là chạm.
static const NSTimeInterval kFBPasteNhanGiuGiay = 0.8;

/// Hạn chờ mục "Dán" hiện ra, khi bên gọi không nói gì.
static const NSTimeInterval kFBPasteHanMacDinhGiay = 3.0;

/// Hạn chờ ô nhập đổi giá trị sau cú dán. Xem FBPasteChoDoiGiaTri để biết vì sao
/// không đọc một phát rồi kết luận.
static const NSTimeInterval kFBPasteChoDoiGiay = 1.5;

/**
 * Nhãn của mục "Dán" trong thực đơn sửa chữ, theo ngôn ngữ của MÁY iPhone
 * (không phải ngôn ngữ của app trên máy tính).
 *
 * Không có mã định danh ổn định cho mục này nên chỉ còn cách so nhãn. Máy đặt
 * ngôn ngữ lạ thì bên gọi truyền thêm "pasteLabels" — danh sách này chỉ là mặc
 * định, không phải giới hạn.
 */
static NSArray<NSString *> *FBPasteNhanMacDinh(void)
{
  static NSArray<NSString *> *ds;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    ds = @[
      @"Dán", @"Paste",
      @"Coller", @"Einfügen", @"Pegar", @"Incolla", @"Colar", @"Plakken",
      @"Wklej", @"Yapıştır", @"Lipire", @"Vložit", @"Beillesztés",
      @"Вставить", @"Вставити", @"Επικόλληση",
      @"貼り付け", @"粘贴", @"貼上", @"붙여넣기",
      @"لصق", @"הדבק", @"วาง", @"Tempel", @"Tempelkan",
      @"Klistra in", @"Lim inn", @"Sæt ind", @"Liitä",
    ];
  });
  return ds;
}

#pragma mark - Bảng dán

/**
 * Ghi chữ vào bảng dán chung và nói lại xem iOS có thật sự nhận không.
 *
 * Kiểm bằng changeCount chứ KHÔNG đọc lại pb.string. Đọc lại có cái giá của nó:
 * nếu cú ghi hỏng thì thứ đọc được là chữ do app KHÁC bỏ vào, và từ iOS 16 kiểu
 * đọc đó làm hiện hộp "Cho phép dán?" ngay trên màn hình người dùng.
 * changeCount và hasStrings đều không lộ nội dung nên không kích hộp thoại.
 */
static BOOL FBPasteGhiBangDan(NSString *chu)
{
  UIPasteboard *pb = UIPasteboard.generalPasteboard;
  NSInteger truoc = pb.changeCount;
  pb.string = chu;
  return pb.changeCount != truoc && pb.hasStrings;
}

#pragma mark - Đọc giá trị ô nhập

/**
 * Giá trị hiện tại của một phần tử, dùng để so trước/sau cú dán.
 *
 * Trả nil khi KHÔNG đọc được (phần tử đã cũ, truy vấn ném ngoại lệ). Nil khác
 * hẳn chuỗi rỗng: rỗng là "ô trống", còn nil là "không biết" — gộp hai thứ này
 * làm một thì một lần đọc hỏng sẽ bị tính thành "ô đã đổi" và endpoint báo dán
 * thành công trong khi chẳng có gì vào ô cả.
 */
static NSString *FBPasteDocGiaTri(XCUIElement *phanTu)
{
  @try {
    id v = phanTu.value;
    if ([v isKindOfClass:NSString.class]) {
      return (NSString *)v;
    }
    return nil == v ? @"" : [NSString stringWithFormat:@"%@", v];
  } @catch (NSException *e) {
    return nil;
  }
}

/**
 * Đợi giá trị ô nhập khác đi so với `truoc`, tối đa `han` giây.
 *
 * Đọc MỘT LẦN ngay sau cú dán là không đủ, và đọc hụt ở đây không chỉ làm báo
 * cáo sai: với strategy `auto`, "chưa đổi" nghĩa là rơi xuống đường thực đơn và
 * DÁN LẦN THỨ HAI — người dùng nhận được chữ nhân đôi. Đó là lý do chỗ này phải
 * chờ chứ không đọc một phát rồi kết luận.
 *
 * Trả về giá trị đọc được lần cuối, hoặc nil nếu không đọc nổi.
 */
static NSString *FBPasteChoDoiGiaTri(XCUIElement *phanTu, NSString *truoc, NSTimeInterval han)
{
  NSString *moc = truoc ?: @"";
  __block NSString *sau = nil;
  // Quay vòng bằng FBRunLoopSpinner chứ không NSThread sleep: nó nhả run loop
  // giữa các nhịp, đúng cách WDA vẫn chờ ở mọi chỗ khác.
  [[[[FBRunLoopSpinner new] timeout:han] interval:0.15] spinUntilTrue:^BOOL{
    sau = FBPasteDocGiaTri(phanTu);
    return nil == sau || ![sau isEqualToString:moc];
  }];
  return sau;
}

#pragma mark - Đường 1: Command+V

static BOOL FBPasteBangCmdV(XCUIElement *dich, NSString **loi)
{
#if __clang_major__ >= 15
  if (@available(iOS 17.0, *)) {
    // Có SDK không có nghĩa là máy có: typeKey chỉ tồn tại từ iOS 17 nên trên
    // máy cũ hơn thông điệp sẽ là "không đáp ứng selector" chứ không phải nổ.
    if (![dich respondsToSelector:@selector(typeKey:modifierFlags:)]) {
      if (loi) { *loi = @"máy không có API typeKey"; }
      return NO;
    }
    @try {
      [dich typeKey:@"v" modifierFlags:XCUIKeyModifierCommand];
      return YES;
    } @catch (NSException *e) {
      if (loi) { *loi = e.reason ?: @"typeKey ném ngoại lệ"; }
      return NO;
    }
  }
#endif
  if (loi) { *loi = @"cần iOS 17 trở lên"; }
  return NO;
}

#pragma mark - Đường 2: thực đơn sửa chữ

static BOOL FBPasteBangThucDon(XCUIApplication *app,
                               XCUIElement *oNhap,
                               NSArray<NSString *> *nhan,
                               NSTimeInterval han,
                               NSString **loi)
{
  @try {
    // Nhấn giữ chứ không chạm hai lần: chạm hai lần CHỌN một từ, mà dán đè lên
    // vùng đang chọn thì mất chữ của người dùng. Nhấn giữ chỉ đặt lại con trỏ.
    [oNhap pressForDuration:kFBPasteNhanGiuGiay];
  } @catch (NSException *e) {
    if (loi) { *loi = [NSString stringWithFormat:@"nhấn giữ hỏng: %@", e.reason ?: @"?"]; }
    return NO;
  }

  NSPredicate *loc = [NSPredicate predicateWithFormat:@"label IN %@", nhan];

  // iOS dựng thực đơn này khác nhau theo phiên bản: có bản là MenuItem, có bản
  // là Button nằm trong một khung khác. Tìm cả hai, đừng tin mỗi một kiểu.
  XCUIElement *muc = [[[app descendantsMatchingType:XCUIElementTypeMenuItem]
                       matchingPredicate:loc] firstMatch];
  BOOL thay = NO;
  @try {
    thay = [muc waitForExistenceWithTimeout:han];
  } @catch (NSException *e) {
    thay = NO;
  }

  if (!thay) {
    muc = [[[app descendantsMatchingType:XCUIElementTypeButton]
            matchingPredicate:loc] firstMatch];
    @try {
      thay = [muc waitForExistenceWithTimeout:1.0];
    } @catch (NSException *e) {
      thay = NO;
    }
  }

  if (!thay) {
    if (loi) {
      *loi = [NSString stringWithFormat:
        @"không thấy mục Dán sau %.1fs — ngôn ngữ máy có thể không nằm trong danh sách nhãn, truyền thêm 'pasteLabels'",
        han];
    }
    return NO;
  }

  @try {
    [muc tap];
    return YES;
  } @catch (NSException *e) {
    if (loi) { *loi = [NSString stringWithFormat:@"bấm mục Dán hỏng: %@", e.reason ?: @"?"]; }
    return NO;
  }
}

#pragma mark - Đọc tham số

/// Đọc 'strategy' từ thân yêu cầu, mặc định "auto".
static NSString *FBPasteDocCach(FBRouteRequest *request)
{
  id tho = request.arguments[@"strategy"];
  return [tho isKindOfClass:NSString.class] ? [(NSString *)tho lowercaseString] : @"auto";
}

#pragma mark -

@implementation FBPasteCommands

+ (NSArray *)routes
{
  return @[
    [[FBRoute POST:@"/wda/paste"].withoutSession respondWithTarget:self action:@selector(handlePaste:)],
    [[FBRoute POST:@"/wda/paste"] respondWithTarget:self action:@selector(handlePaste:)],
    [[FBRoute POST:@"/wda/pasteOnly"].withoutSession respondWithTarget:self action:@selector(handlePasteOnly:)],
    [[FBRoute POST:@"/wda/pasteOnly"] respondWithTarget:self action:@selector(handlePasteOnly:)],
    [[FBRoute POST:@"/wda/setClipboard"].withoutSession respondWithTarget:self action:@selector(handleSetClipboard:)],
    [[FBRoute POST:@"/wda/setClipboard"] respondWithTarget:self action:@selector(handleSetClipboard:)],
  ];
}

#pragma mark - POST /wda/setClipboard

+ (id<FBResponsePayload>)handleSetClipboard:(FBRouteRequest *)request
{
  id tho = request.arguments[@"value"];
  if (![tho isKindOfClass:NSString.class]) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_BAD_ARG: thiếu 'value' kiểu chuỗi. Gửi JSON: {\"value\": \"<chữ>\"}");
  }
  if (!FBPasteGhiBangDan((NSString *)tho)) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_CLIPBOARD_BLOCKED: iOS không cho ghi bảng dán (WDA đang chạy nền)");
  }
  return FBResponseWithObject(@{@"clipboard": @YES});
}

#pragma mark - POST /wda/pasteOnly

/**
 * Chỉ ra lệnh dán, KHÔNG đụng vào bảng dán.
 *
 * Vì sao phải tách khỏi /wda/paste: đo trên máy thật (iOS 15.8) cho thấy iOS
 * CHẶN ghi bảng dán khi WDA chạy nền. Nên luồng chạy được là ba nhịp, và bên
 * gọi tự lo hai nhịp đầu:
 *
 *   đưa WDA lên tiền cảnh → /wda/setClipboard → về app đích → /wda/pasteOnly
 *
 * Ghép ghi-và-dán vào một lệnh như /wda/paste thì nhịp cuối chết ngay ở bước
 * ghi, dù bảng dán ĐÃ có sẵn đúng nội dung từ nhịp giữa. Đó không phải lỗi của
 * /wda/paste — nó vẫn đúng khi WDA đang ở tiền cảnh — mà là vì trong luồng
 * thật, lúc cần dán thì WDA luôn đã về nền rồi.
 */
+ (id<FBResponsePayload>)handlePasteOnly:(FBRouteRequest *)request
{
  return [self danVaoONhap:request daGhiBangDan:NO];
}

#pragma mark - POST /wda/paste

+ (id<FBResponsePayload>)handlePaste:(FBRouteRequest *)request
{
  id tho = request.arguments[@"value"];
  if (![tho isKindOfClass:NSString.class] || 0 == [(NSString *)tho length]) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_BAD_ARG: thiếu 'value' (chuỗi khác rỗng). Gửi JSON: {\"value\": \"<chữ>\"}");
  }
  NSString *chu = (NSString *)tho;

  NSString *cach = FBPasteDocCach(request);
  if (!([cach isEqualToString:@"auto"] || [cach isEqualToString:@"cmdv"]
        || [cach isEqualToString:@"menu"] || [cach isEqualToString:@"clipboard"])) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_BAD_ARG: 'strategy' phải là auto | cmdv | menu | clipboard, nhận '%@'", cach);
  }

  // Ghi bảng dán TRƯỚC mọi thứ khác. Hỏng ở đây thì hai đường dán bên dưới đều
  // vô nghĩa — tệ hơn: chúng sẽ dán lại chữ CŨ còn sót trong bảng dán.
  if (!FBPasteGhiBangDan(chu)) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_CLIPBOARD_BLOCKED: iOS không cho ghi bảng dán (WDA đang chạy nền). "
      @"Hãy đưa WDA lên tiền cảnh, gọi /wda/setClipboard, về app đích rồi gọi /wda/pasteOnly.");
  }

  if ([cach isEqualToString:@"clipboard"]) {
    return FBResponseWithObject(@{@"strategy": @"clipboard", @"clipboard": @YES,
                                  @"pasted": @NO, @"verified": @NO});
  }

  return [self danVaoONhap:request daGhiBangDan:YES];
}

#pragma mark - Phần dán dùng chung cho /wda/paste và /wda/pasteOnly

+ (id<FBResponsePayload>)danVaoONhap:(FBRouteRequest *)request daGhiBangDan:(BOOL)daGhi
{
  NSString *cach = FBPasteDocCach(request);
  if (!([cach isEqualToString:@"auto"] || [cach isEqualToString:@"cmdv"]
        || [cach isEqualToString:@"menu"])) {
    return FBResponseWithUnknownErrorFormat(
      @"PASTE_BAD_ARG: 'strategy' phải là auto | cmdv | menu, nhận '%@'", cach);
  }

  BOOL kiemLai = YES;
  id thoKiem = request.arguments[@"verify"];
  if ([thoKiem isKindOfClass:NSNumber.class]) {
    kiemLai = [(NSNumber *)thoKiem boolValue];
  }

  NSTimeInterval han = kFBPasteHanMacDinhGiay;
  id thoHan = request.arguments[@"timeout"];
  if ([thoHan isKindOfClass:NSNumber.class] && [(NSNumber *)thoHan doubleValue] > 0) {
    han = [(NSNumber *)thoHan doubleValue];
  }

  NSArray<NSString *> *nhan = FBPasteNhanMacDinh();
  id thoNhan = request.arguments[@"pasteLabels"];
  if ([thoNhan isKindOfClass:NSArray.class]) {
    NSMutableArray<NSString *> *gop = [NSMutableArray array];
    for (id n in (NSArray *)thoNhan) {
      if ([n isKindOfClass:NSString.class]) {
        [gop addObject:(NSString *)n];
      }
    }
    if (gop.count > 0) {
      // Cộng thêm chứ không thay: bên gọi bổ sung một ngôn ngữ thì đừng làm
      // hỏng những máy đang chạy tốt bằng nhãn mặc định.
      [gop addObjectsFromArray:nhan];
      nhan = gop.copy;
    }
  }

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  BOOL thuCmdV = [cach isEqualToString:@"auto"] || [cach isEqualToString:@"cmdv"];
  BOOL thuThucDon = [cach isEqualToString:@"auto"] || [cach isEqualToString:@"menu"];

  // Đường thực đơn phải có ô nhập để nhấn giữ; đường kiểm-lại phải có ô nhập để
  // so trước/sau. Chỉ cmdv + không kiểm lại thì bỏ được truy vấn này (nó tốn
  // vài trăm ms trên máy thật).
  XCUIElement *oNhap = nil;
  NSString *truoc = nil;
  if (kiemLai || thuThucDon) {
    @try {
      oNhap = app.fb_activeElement;
    } @catch (NSException *e) {
      oNhap = nil;
    }
    if (nil == oNhap || !oNhap.exists) {
      return FBResponseWithUnknownErrorFormat(
        @"PASTE_NO_FOCUS: không ô nhập nào đang được chọn trên máy");
    }
    if (kiemLai) {
      truoc = FBPasteDocGiaTri(oNhap);
    }
  }

  NSMutableArray<NSString *> *nhatKy = [NSMutableArray array];

  // Trả lời sau một cú dán mà ta không đọc lại được ô nhập. Không nói dối là đã
  // kiểm, nhưng cũng không coi là hỏng — cú dán vẫn có thể đã vào.
  id (^traLoi)(NSString *, BOOL) = ^id(NSString *duong, BOOL daKiem) {
    return FBResponseWithObject(@{@"strategy": duong, @"clipboard": @(daGhi),
                                  @"pasted": @YES, @"verified": @(daKiem)});
  };

  if (thuCmdV) {
    NSString *loi = nil;
    if (FBPasteBangCmdV(app, &loi)) {
      if (!kiemLai) {
        return traLoi(@"cmdv", NO);
      }
      NSString *sau = FBPasteChoDoiGiaTri(oNhap, truoc, kFBPasteChoDoiGiay);
      if (nil == sau) {
        return traLoi(@"cmdv", NO);
      }
      if (![sau isEqualToString:(truoc ?: @"")]) {
        return traLoi(@"cmdv", YES);
      }
      [nhatKy addObject:@"cmdv: ô nhập không đổi"];
    } else {
      [nhatKy addObject:[@"cmdv: " stringByAppendingString:(loi ?: @"hỏng")]];
    }
    if ([cach isEqualToString:@"cmdv"]) {
      return FBResponseWithUnknownErrorFormat(@"PASTE_CMDV_FAILED: %@",
                                              [nhatKy componentsJoinedByString:@"; "]);
    }
  }

  if (thuThucDon) {
    NSString *loi = nil;
    if (FBPasteBangThucDon(app, oNhap, nhan, han, &loi)) {
      if (!kiemLai) {
        return traLoi(@"menu", NO);
      }
      NSString *sau = FBPasteChoDoiGiaTri(oNhap, truoc, kFBPasteChoDoiGiay);
      if (nil == sau) {
        return traLoi(@"menu", NO);
      }
      if (![sau isEqualToString:(truoc ?: @"")]) {
        return traLoi(@"menu", YES);
      }
      [nhatKy addObject:@"menu: bấm Dán xong mà ô nhập không đổi"];
    } else {
      [nhatKy addObject:[@"menu: " stringByAppendingString:(loi ?: @"hỏng")]];
    }
  }

  return FBResponseWithUnknownErrorFormat(
    @"PASTE_FAILED: %@", [nhatKy componentsJoinedByString:@"; "]);
}

@end
