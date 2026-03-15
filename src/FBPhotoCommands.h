/**
 * FBPhotoCommands — Import Photo/Video vào thư viện Ảnh iPhone
 * Custom command cho WebDriverAgent (iPhone Control)
 *
 * Routes:
 *   POST /wda/importPhoto — Import ảnh (raw bytes trong body)
 *   POST /wda/importVideo — Import video (raw bytes trong body)
 */

#import <Foundation/Foundation.h>
#import <WebDriverAgentLib/FBCommandHandler.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBPhotoCommands : NSObject <FBCommandHandler>

@end

NS_ASSUME_NONNULL_END
