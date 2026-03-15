/**
 * FBPhotoCommands — Import Photo/Video vào thư viện Ảnh iPhone
 * Custom command cho WebDriverAgent (iPhone Control)
 *
 * POST /wda/importPhoto — raw image bytes → Photos Library
 * POST /wda/importVideo — raw video bytes → Photos Library (temp file)
 */

#import "FBPhotoCommands.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBResponsePayload.h"
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
  NSData *imageData = request.httpBody;
  if (nil == imageData || imageData.length == 0) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"No image data in request body" traceback:nil]);
  }

  UIImage *image = [UIImage imageWithData:imageData];
  if (nil == image) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Cannot decode image from data" traceback:nil]);
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
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:msg traceback:nil]);
  }

  return FBResponseWithOK();
}

#pragma mark - Import Video

+ (id<FBResponsePayload>)handleImportVideo:(FBRouteRequest *)request
{
  NSData *videoData = request.httpBody;
  if (nil == videoData || videoData.length == 0) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"No video data in request body" traceback:nil]);
  }

  // Ghi ra temp file (Photos API cần file URL cho video)
  NSString *tempDir = NSTemporaryDirectory();
  NSString *tempFile = [tempDir stringByAppendingPathComponent:
    [NSString stringWithFormat:@"tempVideo_%@.mp4", [[NSUUID UUID] UUIDString]]];
  NSURL *tempURL = [NSURL fileURLWithPath:tempFile];

  if (![videoData writeToURL:tempURL atomically:YES]) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:@"Failed to write temp video file" traceback:nil]);
  }

  __block NSError *saveError = nil;
  __block BOOL success = NO;

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:tempURL];
  } completionHandler:^(BOOL ok, NSError *error) {
    success = ok;
    saveError = error;
    // Dọn temp file
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));

  if (!success) {
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    NSString *msg = saveError.localizedDescription ?: @"Unknown error saving video";
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:msg traceback:nil]);
  }

  return FBResponseWithOK();
}

@end
