/**
 * FBPasteCommands — Dán chữ vào ô nhập bằng bảng dán của iOS
 * Custom command cho WebDriverAgent (DrakoCtrl)
 *
 * Routes:
 *   POST /wda/paste        — ghi bảng dán RỒI dán vào ô đang chọn
 *   POST /wda/setClipboard — chỉ ghi bảng dán, không dán
 *
 * Vì sao cần: /wda/keys gõ TỪNG ký tự qua bàn phím iOS (~24ms/ký tự đo trên
 * máy thật), nên 1.000 ký tự tốn ~24 giây và giữ máy bận suốt quãng đó. Đường
 * bảng dán tốn thời gian như nhau bất kể chữ dài bao nhiêu.
 */

#import <Foundation/Foundation.h>
#import "FBCommandHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface FBPasteCommands : NSObject <FBCommandHandler>

@end

NS_ASSUME_NONNULL_END
