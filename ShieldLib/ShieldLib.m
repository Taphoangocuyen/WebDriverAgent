// ShieldLib.m — WDA Protection System (Pure Objective-C)
// Tất cả trong 1 file: Keychain + TimeLock + Reachability + RSA + LicenseManager
// Compile: clang → dylib, KHÔNG cần Swift runtime

#import "ShieldLib.h"

#pragma mark - ═══ Date Formatter ═══

static NSDateFormatter *_shieldDateFormatter(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    });
    return fmt;
}

#pragma mark - ═══ KeychainStore ═══

static BOOL KeychainSave(NSString *key, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;

    // Xóa item cũ
    NSDictionary *deleteQuery = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: SHIELD_KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: key
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

    // Thêm mới
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass:          (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:    SHIELD_KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount:    key,
        (__bridge id)kSecValueData:      data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    return status == errSecSuccess;
}

static NSString *KeychainLoad(NSString *key) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: SHIELD_KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecReturnData:  @YES,
        (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL KeychainDelete(NSString *key) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: SHIELD_KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: key
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

static BOOL KeychainSaveDate(NSString *key, NSDate *date) {
    return KeychainSave(key, [_shieldDateFormatter() stringFromDate:date]);
}

static NSDate *KeychainLoadDate(NSString *key) {
    NSString *str = KeychainLoad(key);
    if (!str) return nil;
    return [_shieldDateFormatter() dateFromString:str];
}

#pragma mark - ═══ Reachability ═══

static BOOL ShieldIsNetworkReachable(void) {
    struct sockaddr_in zeroAddr;
    memset(&zeroAddr, 0, sizeof(zeroAddr));
    zeroAddr.sin_len = sizeof(zeroAddr);
    zeroAddr.sin_family = AF_INET;

    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithAddress(
        NULL, (const struct sockaddr *)&zeroAddr
    );
    if (!ref) return NO;

    SCNetworkReachabilityFlags flags = 0;
    BOOL success = SCNetworkReachabilityGetFlags(ref, &flags);
    CFRelease(ref);

    if (!success) return NO;
    if (!(flags & kSCNetworkReachabilityFlagsReachable)) return NO;
    if (flags & kSCNetworkReachabilityFlagsConnectionRequired) return NO;

    return YES;
}

#pragma mark - ═══ Device ID ═══

static NSString *ShieldGetDeviceID(void) {
    NSString *saved = KeychainLoad(KEY_DEVICE_ID);
    if (saved) return saved;

    // Dùng NSUUID thay vì UIDevice — không cần main thread
    // Tránh block main thread gây WDA chớp
    NSString *deviceID = [NSUUID UUID].UUIDString;
    KeychainSave(KEY_DEVICE_ID, deviceID);
    return deviceID;
}

#pragma mark - ═══ TimeLock ═══

typedef NS_ENUM(NSInteger, ShieldLockStatus) {
    ShieldLockStatusActive = 0,
    ShieldLockStatusExpired,
    ShieldLockStatusTampered,
    ShieldLockStatusGraceActive,
    ShieldLockStatusGraceExpired,
    ShieldLockStatusNotActivated
};

static BOOL ShieldIsDateTampered(NSDate *now) {
    NSDate *lastKnown = KeychainLoadDate(KEY_LAST_KNOWN_DATE);
    if (!lastKnown) return NO;

    NSTimeInterval diff = [now timeIntervalSinceDate:lastKnown];
    // Chỉnh ngược quá 5 phút → tampered
    if (diff < -300.0) {
        NSLog(@"%@ TimeLock: Clock moved backwards! last=%@ now=%@",
              SHIELD_LOG_PREFIX,
              [_shieldDateFormatter() stringFromDate:lastKnown],
              [_shieldDateFormatter() stringFromDate:now]);
        return YES;
    }
    // Nhảy tương lai quá 366 ngày → suspicious
    if (diff > 366.0 * 86400.0) {
        NSLog(@"%@ TimeLock: Suspicious forward time jump", SHIELD_LOG_PREFIX);
        return YES;
    }
    return NO;
}

static ShieldLockStatus ShieldCheckGracePeriod(NSDate *now) {
    NSDate *graceStart = KeychainLoadDate(KEY_GRACE_START);
    if (graceStart) {
        NSDate *graceEnd = [graceStart dateByAddingTimeInterval:SHIELD_GRACE_HOURS * 3600.0];
        if ([now compare:graceEnd] == NSOrderedAscending) {
            NSInteger hoursLeft = (NSInteger)([graceEnd timeIntervalSinceDate:now] / 3600.0);
            NSLog(@"%@ TimeLock: Grace active — %ldh remaining", SHIELD_LOG_PREFIX, (long)hoursLeft);
            return ShieldLockStatusGraceActive;
        }
        NSLog(@"%@ TimeLock: Grace expired", SHIELD_LOG_PREFIX);
        return ShieldLockStatusGraceExpired;
    }
    // Bắt đầu grace period
    KeychainSaveDate(KEY_GRACE_START, now);
    NSLog(@"%@ TimeLock: Grace started — %dh", SHIELD_LOG_PREFIX, SHIELD_GRACE_HOURS);
    return ShieldLockStatusGraceActive;
}

static void ShieldActivateTrial(void) {
    NSDate *now = [NSDate date];
    NSDate *expiry = [now dateByAddingTimeInterval:SHIELD_TRIAL_DAYS * 86400.0];

    KeychainSaveDate(KEY_ACTIVATION_DATE, now);
    KeychainSaveDate(KEY_EXPIRY_DATE, expiry);
    KeychainSaveDate(KEY_LAST_KNOWN_DATE, now);
    KeychainSave(KEY_ACTIVATION_STATUS, @"1");
    ShieldGetDeviceID();

    NSLog(@"%@ TimeLock: Trial activated — %d days, expires %@",
          SHIELD_LOG_PREFIX, SHIELD_TRIAL_DAYS,
          [_shieldDateFormatter() stringFromDate:expiry]);
}

static void ShieldExtendLicense(int days) {
    NSDate *now = [NSDate date];
    NSDate *newExpiry = [now dateByAddingTimeInterval:days * 86400.0];
    KeychainSaveDate(KEY_EXPIRY_DATE, newExpiry);
    KeychainSaveDate(KEY_LAST_KNOWN_DATE, now);
    KeychainSaveDate(KEY_LAST_SERVER_CHECK, now);
    KeychainDelete(KEY_GRACE_START);
    NSLog(@"%@ TimeLock: Extended %d days → %@",
          SHIELD_LOG_PREFIX, days,
          [_shieldDateFormatter() stringFromDate:newExpiry]);
}

static ShieldLockStatus ShieldCheckTimeLock(void) {
    NSDate *now = [NSDate date];

    // 1. Chưa kích hoạt?
    NSDate *activationDate = KeychainLoadDate(KEY_ACTIVATION_DATE);
    if (!activationDate) {
        NSLog(@"%@ TimeLock: Not activated", SHIELD_LOG_PREFIX);
        return ShieldLockStatusNotActivated;
    }

    // 2. Chống chỉnh ngày
    if (ShieldIsDateTampered(now)) {
        return ShieldLockStatusTampered;
    }
    KeychainSaveDate(KEY_LAST_KNOWN_DATE, now);

    // 3. Kiểm tra hạn
    NSDate *expiryDate = KeychainLoadDate(KEY_EXPIRY_DATE);
    if (!expiryDate) {
        return ShieldLockStatusExpired;
    }

    if ([now compare:expiryDate] == NSOrderedAscending) {
        NSInteger daysLeft = (NSInteger)([expiryDate timeIntervalSinceDate:now] / 86400.0);
        NSLog(@"%@ TimeLock: Active — %ld days remaining", SHIELD_LOG_PREFIX, (long)daysLeft);
        return ShieldLockStatusActive;
    }

    // 4. Hết hạn → grace period nếu offline
    if (!ShieldIsNetworkReachable() || !SHIELD_SERVER_ENABLED) {
        return ShieldCheckGracePeriod(now);
    }

    NSLog(@"%@ TimeLock: Expired", SHIELD_LOG_PREFIX);
    return ShieldLockStatusExpired;
}

#pragma mark - ═══ LicenseManager ═══

@interface ShieldLicenseManager : NSObject
+ (instancetype)shared;
- (BOOL)checkLicense;
- (void)lockAppWithReason:(NSString *)reason;
@end

@implementation ShieldLicenseManager

+ (instancetype)shared {
    static ShieldLicenseManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ShieldLicenseManager alloc] init];
    });
    return instance;
}

- (BOOL)checkLicense {
    NSLog(@"%@ License check — device:%@", SHIELD_LOG_PREFIX, ShieldGetDeviceID());

    ShieldLockStatus status = ShieldCheckTimeLock();

    switch (status) {
        case ShieldLockStatusNotActivated:
            NSLog(@"%@ First launch — activating trial (%d days)", SHIELD_LOG_PREFIX, SHIELD_TRIAL_DAYS);
            ShieldActivateTrial();
            return YES;

        case ShieldLockStatusActive:
            NSLog(@"%@ License ACTIVE", SHIELD_LOG_PREFIX);
            return YES;

        case ShieldLockStatusGraceActive:
            NSLog(@"%@ License in GRACE PERIOD", SHIELD_LOG_PREFIX);
            return YES;

        case ShieldLockStatusTampered:
            NSLog(@"%@ LICENSE TAMPERED!", SHIELD_LOG_PREFIX);
            [self lockAppWithReason:@"Phat hien chinh ngay he thong. Vui long khoi phuc ngay gio chinh xac."];
            return NO;

        case ShieldLockStatusExpired:
            NSLog(@"%@ License EXPIRED", SHIELD_LOG_PREFIX);
            [self lockAppWithReason:@"Het han su dung. Vui long gia han license."];
            return NO;

        case ShieldLockStatusGraceExpired:
            NSLog(@"%@ Grace period EXPIRED", SHIELD_LOG_PREFIX);
            [self lockAppWithReason:@"Het han su dung. Vui long gia han license."];
            return NO;
    }
    return NO;
}

- (void)lockAppWithReason:(NSString *)reason {
    NSLog(@"%@ APP LOCKED: %@", SHIELD_LOG_PREFIX, reason);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
            }
        }
        if (!keyWindow) {
            keyWindow = UIApplication.sharedApplication.windows.firstObject;
        }

        UIViewController *rootVC = keyWindow.rootViewController;
        if (!rootVC) {
            NSLog(@"%@ No root VC — terminating in 2s", SHIELD_LOG_PREFIX);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ exit(0); });
            return;
        }

        UIViewController *presenter = rootVC.presentedViewController ?: rootVC;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"License"
            message:reason
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { exit(0); }]];

        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

@end

#pragma mark - ═══ DYLIB ENTRY POINT ═══

__attribute__((constructor))
static void shield_dylib_init(void) {
    NSLog(@"%@ ShieldLib v3.0 loaded", SHIELD_LOG_PREFIX);

    // Đợi app launch xong rồi mới check license
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil
        queue:nil
        usingBlock:^(NSNotification *note) {
            NSLog(@"%@ App launched — scheduling license check...", SHIELD_LOG_PREFIX);

            // ★ Chạy license check trên BACKGROUND thread
            // Không block main thread → WDA không bị chớp
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSLog(@"%@ Running license check (background)...", SHIELD_LOG_PREFIX);
                BOOL ok = [[ShieldLicenseManager shared] checkLicense];
                NSLog(@"%@ License result: %@", SHIELD_LOG_PREFIX, ok ? @"OK" : @"BLOCKED");
            });
        }];
}
