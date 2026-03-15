/**
 * FBPhotoCommands — Import Photo/Video vào thư viện Ảnh iPhone
 * Custom command cho WebDriverAgent (iPhone Control)
 *
 * Routes:
 *   POST /wda/importPhoto — Import ảnh (base64 trong JSON body)
 *   POST /wda/importVideo — Import video (base64 trong JSON body)
 */

#import <Foundation/Foundation.h>
#import "FBCommandHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface FBPhotoCommands : NSObject <FBCommandHandler>

@end

NS_ASSUME_NONNULL_END
