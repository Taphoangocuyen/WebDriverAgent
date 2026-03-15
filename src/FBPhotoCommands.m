/**
 * FBPhotoCommands — Import Photo/Video vào thư viện Ảnh iPhone
 * Custom command cho WebDriverAgent (iPhone Control)
 *
 * POST /wda/importPhoto — base64 image data trong JSON body {"value": "..."}
 * POST /wda/importVideo — base64 video data trong JSON body {"value": "..."}
 */

#import "FBPhotoCommands.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBResponsePayload.h"
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@implementation FBPhotoCommands

#pragma mark - FBCommandHandler

+ (NSArray *)routes
{
  return @[
    [[FBRoute POST:@"/wda/importPhoto"].withoutSession respondWithTarget:self action:@selector(handleImportPhoto:)],
    [[FBRoute POST:@"/wda/importPhoto"] respondWithTarget:self action:@selector(handleImportPhoto:)],
    [[FBRoute POST:@"/wda/importVideo"].withoutSession respondWithTarget:self action:@selector(handleImportVideo:)],
    [[FBRoute POST:@"/wda/importVideo"] respondWithTarget:self action:@selector(handleImportVideo:)],
  ];
}

#pragma mark - Import Photo

+ (id<FBResponsePayload>)handleImportPhoto:(FBRouteRequest *)request
{
  NSString *base64String = request.arguments[@"value"];
  if (nil == base64String || base64String.length == 0) {
    return FBResponseWithUnknownErrorFormat(@"No image data in request body. Send JSON: {\"value\": \"<base64>\"}");
  }

  NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (nil == imageData || imageData.length == 0) {
    return FBResponseWithUnknownErrorFormat(@"Cannot decode base64 image data");
  }

  UIImage *image = [UIImage imageWithData:imageData];
  if (nil == image) {
    return FBResponseWithUnknownErrorFormat(@"Cannot create image from decoded data");
  }

  __block NSError *saveError = nil;
  __block BOOL success = NO;

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    [PHAssetChangeRequest creationRequestForAssetFromImage:image];
  } completionHandler:^(BOOL ok, NSError *error) {
    success = ok;
    saveError = error;
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

  if (!success) {
    NSString *msg = saveError.localizedDescription ?: @"Unknown error saving photo";
    return FBResponseWithUnknownErrorFormat(@"Failed to save photo: %@", msg);
  }

  return FBResponseWithOK();
}

#pragma mark - Import Video

+ (id<FBResponsePayload>)handleImportVideo:(FBRouteRequest *)request
{
  NSString *base64String = request.arguments[@"value"];
  if (nil == base64String || base64String.length == 0) {
    return FBResponseWithUnknownErrorFormat(@"No video data in request body. Send JSON: {\"value\": \"<base64>\"}");
  }

  NSData *videoData = [[NSData alloc] initWithBase64EncodedString:base64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (nil == videoData || videoData.length == 0) {
    return FBResponseWithUnknownErrorFormat(@"Cannot decode base64 video data");
  }

  // Ghi ra temp file (Photos API cần file URL cho video)
  NSString *tempDir = NSTemporaryDirectory();
  NSString *tempFile = [tempDir stringByAppendingPathComponent:
    [NSString stringWithFormat:@"tempVideo_%@.mp4", [[NSUUID UUID] UUIDString]]];
  NSURL *tempURL = [NSURL fileURLWithPath:tempFile];

  if (![videoData writeToURL:tempURL atomically:YES]) {
    return FBResponseWithUnknownErrorFormat(@"Failed to write temp video file");
  }

  __block NSError *saveError = nil;
  __block BOOL success = NO;

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:tempURL];
  } completionHandler:^(BOOL ok, NSError *error) {
    success = ok;
    saveError = error;
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));

  if (!success) {
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    NSString *msg = saveError.localizedDescription ?: @"Unknown error saving video";
    return FBResponseWithUnknownErrorFormat(@"Failed to save video: %@", msg);
  }

  return FBResponseWithOK();
}

@end
