/**
 * FBPhotoCommands — Import Photo/Video vào thư viện Ảnh iPhone
 * Custom command cho WebDriverAgent (DrakoCtrl)
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

#pragma mark - Quyền ghi vào thư viện Ảnh

/**
 * Bảo đảm có quyền GHI vào thư viện Ảnh TRƯỚC khi lưu.
 *
 * Trước đây code gọi thẳng performChanges rồi phó mặc cho iOS. Lần chạy đầu,
 * iOS hiện hộp xin quyền ngay lúc đó, còn performChanges thất bại âm thầm —
 * app chỉ nhận được "Unknown error saving photo" nên không biết là do quyền,
 * do hết giờ, hay do file hỏng.
 *
 * Dùng PHAccessLevelAddOnly chứ không phải ReadWrite: ta chỉ THÊM ảnh/video.
 * Hộp thoại nhẹ hơn và khớp đúng NSPhotoLibraryAddUsageDescription đã khai
 * trong Info.plist — xin ReadWrite mà chỉ khai AddOnly là iOS kill app.
 *
 * Trả về nil nếu được phép; ngược lại trả chuỗi lý do để báo lên app desktop.
 */
static NSString *FBPhotoAddPermissionError(void)
{
  // Hộp xin quyền chỉ hiện LẦN ĐẦU. Các lần sau hàm này trả về ngay lập tức,
  // nên 90 giây dưới đây không cộng vào thời gian của mỗi lần nhập.
  static const int64_t kChoNguoiDungGiay = 90;

  PHAuthorizationStatus status;
  if (@available(iOS 14.0, *)) {
    status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
  } else {
    status = [PHPhotoLibrary authorizationStatus];
  }

  if (PHAuthorizationStatusNotDetermined == status) {
    __block PHAuthorizationStatus ketQua = status;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    if (@available(iOS 14.0, *)) {
      [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                 handler:^(PHAuthorizationStatus s) {
        ketQua = s;
        dispatch_semaphore_signal(sem);
      }];
    } else {
      [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus s) {
        ketQua = s;
        dispatch_semaphore_signal(sem);
      }];
    }
    if (0 != dispatch_semaphore_wait(sem,
              dispatch_time(DISPATCH_TIME_NOW, kChoNguoiDungGiay * NSEC_PER_SEC))) {
      return [NSString stringWithFormat:
        @"Timed out after %lld s waiting for the Photos permission dialog on the device. Tap Allow, then retry.",
        kChoNguoiDungGiay];
    }
    status = ketQua;
  }

  switch (status) {
    case PHAuthorizationStatusAuthorized:
      return nil;
    case PHAuthorizationStatusLimited:
      // Với AddOnly, Limited vẫn thêm được ảnh mới.
      return nil;
    case PHAuthorizationStatusDenied:
      return @"Photos permission denied. On the iPhone: Settings > Privacy & Security > Photos > DrakoCtrl > Add Photos Only.";
    case PHAuthorizationStatusRestricted:
      return @"Photos access is restricted by Screen Time or an MDM policy.";
    case PHAuthorizationStatusNotDetermined:
      return @"Photos permission still undetermined after the request.";
  }
  return @"Could not determine Photos permission status.";
}

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

  // Xin quyền TRƯỚC khi làm việc nặng: bị từ chối thì khỏi giải mã base64
  // (thân yêu cầu video có thể tới hàng trăm MB).
  NSString *permError = FBPhotoAddPermissionError();
  if (nil != permError) {
    return FBResponseWithUnknownErrorFormat(@"%@", permError);
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

  // Phân biệt HẾT GIỜ với lưu thất bại: trước đây cả hai đều rơi vào cùng một
  // nhánh và báo "Unknown error", che mất nguyên nhân thật.
  if (0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
    return FBResponseWithUnknownErrorFormat(
      @"Timed out after 30 s while Photos saved the image. Permission was already granted, so this is not a permission problem.");
  }

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

  // Xin quyền TRƯỚC khi làm việc nặng: bị từ chối thì khỏi giải mã base64
  // (thân yêu cầu video có thể tới hàng trăm MB).
  NSString *permError = FBPhotoAddPermissionError();
  if (nil != permError) {
    return FBResponseWithUnknownErrorFormat(@"%@", permError);
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

  if (0 != dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) {
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    return FBResponseWithUnknownErrorFormat(
      @"Timed out after 60 s while Photos saved the video. Permission was already granted, so this is not a permission problem.");
  }

  if (!success) {
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    NSString *msg = saveError.localizedDescription ?: @"Unknown error saving video";
    return FBResponseWithUnknownErrorFormat(@"Failed to save video: %@", msg);
  }

  return FBResponseWithOK();
}

@end
