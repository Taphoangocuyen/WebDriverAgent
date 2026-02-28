// ShieldLib.h — WDA Protection System (Pure Objective-C)
// Thay thế hhhhsd.dylib — bạn kiểm soát hoàn toàn

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>

// ═══════════════════════════════════════════════════
// CONFIG — THAY ĐỔI CÁC GIÁ TRỊ NÀY THEO NHU CẦU
// ═══════════════════════════════════════════════════
#define SHIELD_APP_ID           @"com.icontrol.wda"
#define SHIELD_APP_NAME         @"iPhoneControl"
#define SHIELD_BUNDLE_ID        @"com.facebook.WebDriverAgentRunner.xctrunner"
#define SHIELD_TRIAL_DAYS       30
#define SHIELD_GRACE_HOURS      72
#define SHIELD_HEARTBEAT_SECS   3600
#define SHIELD_SERVER_ENABLED   NO
#define SHIELD_SERVER_URL       @""
#define SHIELD_KEYCHAIN_SERVICE @"com.icontrol.shield"
#define SHIELD_LOG_PREFIX       @"[Shield]"

// Keychain keys
#define KEY_ACTIVATION_STATUS   @"shield_activation_status"
#define KEY_ACTIVATION_DATE     @"shield_activation_date"
#define KEY_EXPIRY_DATE         @"shield_expiry_date"
#define KEY_DEVICE_ID           @"shield_device_id"
#define KEY_LICENSE_KEY          @"shield_license_key"
#define KEY_LAST_SERVER_CHECK   @"shield_last_server_check"
#define KEY_LAST_KNOWN_DATE     @"shield_last_known_date"
#define KEY_GRACE_START         @"shield_grace_start"

// RSA Public Key (Base64, không có header/footer PEM)
#define SHIELD_RSA_PUBLIC_KEY   @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvH1kOfj9vy2sbflJhrAfncdwAqJx1H3+mFIHeJHinxVNsLpS5xKECw/W4V3U7Ouw+0OTXmG+tre9IWq+iqCDRlwr/Uydf9SLDBv0ZiqkVwqUUGRN+aSn0yW6iApK5aHyxCdN1FiZ2+K7ZOdaRtMY67JrKmrY19CSOkixXQk9afdLh5boq96PcO7dCrezNAOZjQ8/JvyheN3K6EqwccXWim0sUcuxb0t4wtOv6gJszBjCFZF/gx4nmaRawemi5K7xXfBsxzYAbWK36jdkkeNlJuubSVPUPUJqh7SFhAU/QJCRguubC0q3p3p/uStR9U2C/+9RWrjRDtiIsfzVNZqONwIDAQAB"
