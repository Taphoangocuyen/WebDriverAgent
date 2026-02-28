// ShieldEntry.swift — Entry Point (dylib constructor)
// Tự động chạy khi hhhhsd.dylib được load bởi WebDriverAgentRunner-Runner
// Gọi LicenseManager.checkLicense() để gate WDA startup

import Foundation
import UIKit

// ═══════════════════════════════════════════════════════════
// DYLIB ENTRY POINT
// ShieldInit.c chứa __attribute__((constructor)) gọi → shield_constructor_entry()
// → đăng ký observer → khi app launch xong → checkLicense()
// ═══════════════════════════════════════════════════════════

@objc class ShieldLoader: NSObject {

    /// Được gọi từ C constructor khi dylib load
    @objc static func initializeShield() {
        NSLog("\(ShieldConfig.logPrefix) ═══ ShieldLib loaded ═══")
        NSLog("\(ShieldConfig.logPrefix) Module: ShieldLib v1.0")
        NSLog("\(ShieldConfig.logPrefix) App: \(ShieldConfig.appName)")

        // Đăng ký observer đợi app launch xong
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
    }

    /// Được gọi sau khi app launch xong — UIKit đã ready
    @objc static func appDidFinishLaunching() {
        NSLog("\(ShieldConfig.logPrefix) App launched — starting license check")

        // Delay nhẹ để UI hoàn tất render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            performLicenseCheck()
        }
    }

    /// Thực hiện kiểm tra license
    private static func performLicenseCheck() {
        let result = LicenseManager.shared.checkLicense()

        if result {
            NSLog("\(ShieldConfig.logPrefix) License OK — WDA allowed to run")
        } else {
            NSLog("\(ShieldConfig.logPrefix) License FAILED — WDA blocked")
        }

        // Log license info
        let info = LicenseManager.shared.licenseInfo
        for (key, value) in info {
            NSLog("\(ShieldConfig.logPrefix)   \(key): \(value)")
        }
    }
}

// ═══════════════════════════════════════════════════════════
// C-callable entry point — gọi từ ShieldInit.c constructor
// ═══════════════════════════════════════════════════════════

@_cdecl("shield_constructor_entry")
public func shieldConstructorEntry() {
    ShieldLoader.initializeShield()
}

// ═══════════════════════════════════════════════════════════
// C EXPORT — cho trường hợp gọi từ bên ngoài
// ═══════════════════════════════════════════════════════════

/// C-callable function để check license status
/// Return: 1 = OK, 0 = locked
@_cdecl("shield_check_license")
public func shieldCheckLicense() -> Int32 {
    return LicenseManager.shared.checkLicense() ? 1 : 0
}

/// C-callable function để lấy license info (JSON string)
@_cdecl("shield_get_info")
public func shieldGetInfo() -> UnsafePointer<CChar>? {
    let info = LicenseManager.shared.licenseInfo
    guard let data = try? JSONSerialization.data(withJSONObject: info),
          let jsonStr = String(data: data, encoding: .utf8) else {
        return nil
    }
    return (jsonStr as NSString).utf8String
}

/// C-callable function để activate bằng license key
@_cdecl("shield_activate")
public func shieldActivate(_ key: UnsafePointer<CChar>) {
    let licenseKey = String(cString: key)
    LicenseManager.shared.activateWithKey(licenseKey) { success in
        NSLog("\(ShieldConfig.logPrefix) Activate result: \(success)")
    }
}
