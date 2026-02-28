// ShieldEntry.swift — Entry Point (dylib constructor)
// Tự động chạy khi hhhhsd.dylib được load bởi WebDriverAgentRunner-Runner
// Gọi LicenseManager.checkLicense() để gate WDA startup

import Foundation
import UIKit

// ═══════════════════════════════════════════════════════════
// DYLIB ENTRY POINT
// Khi iOS load dylib → ObjC runtime gọi +[ShieldLoader load]
// → checkLicense() → nếu OK thì WDA chạy bình thường
// → nếu FAIL thì block WDA hoặc thoát app
// ═══════════════════════════════════════════════════════════

@objc class ShieldLoader: NSObject {

    /// +load() được gọi TỰ ĐỘNG khi dylib load — trước cả main()
    /// Dùng để đăng ký observer, chờ app launch xong mới check license
    override class func load() {
        NSLog("\(ShieldConfig.logPrefix) ═══ ShieldLib loaded ═══")
        NSLog("\(ShieldConfig.logPrefix) Module: ShieldLib v1.0")
        NSLog("\(ShieldConfig.logPrefix) App: \(ShieldConfig.appName)")

        // Đăng ký observer đợi app launch xong
        // Vì +load() chạy quá sớm, UIApplication chưa ready
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
            NSLog("\(ShieldConfig.logPrefix) ✓ License OK — WDA allowed to run")
        } else {
            NSLog("\(ShieldConfig.logPrefix) ✗ License FAILED — WDA blocked")
            // LicenseManager đã show alert + sẽ exit(0)
        }

        // Log license info
        let info = LicenseManager.shared.licenseInfo
        for (key, value) in info {
            NSLog("\(ShieldConfig.logPrefix)   \(key): \(value)")
        }
    }
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
    // Cần giữ reference để pointer không bị dealloc
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
