// LicenseManager.swift — Bộ điều phối chính
// Kết hợp TimeLock + Keychain + Reachability + Server để gate WDA

import Foundation
import UIKit

class LicenseManager {

    // MARK: - Singleton

    static let shared = LicenseManager()
    private init() {}

    private var isLocked = false

    // MARK: - Main Check

    /// Kiểm tra toàn bộ license — return true nếu OK, false nếu bị lock
    func checkLicense() -> Bool {
        NSLog("\(ShieldConfig.logPrefix) ═══════════════════════════════════════")
        NSLog("\(ShieldConfig.logPrefix) License check started")
        NSLog("\(ShieldConfig.logPrefix) App: \(ShieldConfig.appName) (\(ShieldConfig.appID))")
        NSLog("\(ShieldConfig.logPrefix) Server: \(ShieldConfig.serverEnabled ? ShieldConfig.serverURL : "DISABLED")")
        NSLog("\(ShieldConfig.logPrefix) ═══════════════════════════════════════")

        // 1. Start reachability monitor
        ShieldReachability.shared.startNotifier()

        // 2. Check TimeLock status
        let status = TimeLock.shared.checkStatus()

        switch status {
        case .notActivated:
            // Lần đầu → tự động kích hoạt trial
            NSLog("\(ShieldConfig.logPrefix) First launch — activating trial (\(ShieldConfig.trialDays) days)")
            TimeLock.shared.activateTrial()
            startBackgroundTasks()
            return true

        case .active:
            NSLog("\(ShieldConfig.logPrefix) License ACTIVE")
            startBackgroundTasks()
            return true

        case .graceActive:
            NSLog("\(ShieldConfig.logPrefix) License in GRACE PERIOD (offline)")
            startBackgroundTasks()
            return true

        case .tampered:
            NSLog("\(ShieldConfig.logPrefix) LICENSE TAMPERED — date manipulation detected!")
            lockApp(reason: "Phat hien chinh ngay he thong. Vui long khoi phuc ngay gio chinh xac.")
            return false

        case .expired:
            return handleExpired()

        case .graceExpired:
            NSLog("\(ShieldConfig.logPrefix) Grace period EXPIRED")
            lockApp(reason: "Het han su dung. Vui long gia han license.")
            return false
        }
    }

    // MARK: - Handle Expired

    /// Xử lý khi hết hạn: thử verify với server, nếu không → lock
    private func handleExpired() -> Bool {
        NSLog("\(ShieldConfig.logPrefix) License EXPIRED — attempting server verify...")

        // Nếu không có server → lock ngay
        guard ShieldConfig.serverEnabled else {
            NSLog("\(ShieldConfig.logPrefix) No server configured — locking")
            lockApp(reason: "Het han su dung. Vui long gia han license.")
            return false
        }

        // Nếu không có mạng → bắt đầu grace period
        guard ShieldReachability.shared.isReachable else {
            NSLog("\(ShieldConfig.logPrefix) No network — entering grace period")
            let graceStatus = TimeLock.shared.checkStatus()
            if graceStatus == .graceActive {
                startBackgroundTasks()
                return true
            }
            lockApp(reason: "Het han su dung va khong co ket noi mang.")
            return false
        }

        // Có server + có mạng → verify synchronously (block startup)
        var serverResult = false
        let semaphore = DispatchSemaphore(value: 0)

        ServerClient.shared.verify { success, days in
            serverResult = success
            semaphore.signal()
        }

        // Đợi tối đa 10 giây
        let timeout = semaphore.wait(timeout: .now() + 10)

        if timeout == .timedOut {
            NSLog("\(ShieldConfig.logPrefix) Server verify timed out — entering grace period")
            return TimeLock.shared.checkStatus() == .graceActive
        }

        if serverResult {
            NSLog("\(ShieldConfig.logPrefix) Server verify SUCCESS — license renewed")
            startBackgroundTasks()
            return true
        }

        lockApp(reason: "License khong hop le. Vui long lien he ho tro.")
        return false
    }

    // MARK: - Background Tasks

    /// Khởi động heartbeat + reachability listener
    private func startBackgroundTasks() {
        // Start heartbeat
        ServerClient.shared.startHeartbeat()

        // Listen for network changes
        ShieldReachability.shared.whenReachable = { status in
            NSLog("\(ShieldConfig.logPrefix) Network restored: \(status.rawValue)")
            // Khi có mạng lại → thử verify
            if ShieldConfig.serverEnabled {
                ServerClient.shared.verify { success, _ in
                    if success {
                        NSLog("\(ShieldConfig.logPrefix) Background verify OK")
                    }
                }
            }
        }

        ShieldReachability.shared.whenUnreachable = {
            NSLog("\(ShieldConfig.logPrefix) Network lost")
        }
    }

    // MARK: - Lock App

    /// Lock WDA — hiện alert và chặn hoạt động
    func lockApp(reason: String) {
        isLocked = true
        NSLog("\(ShieldConfig.logPrefix) APP LOCKED: \(reason)")

        // Dừng background tasks
        ServerClient.shared.stopHeartbeat()

        // Hiện alert trên main thread
        DispatchQueue.main.async {
            self.showLockAlert(message: reason)
        }
    }

    /// Hiện UIAlertController thông báo lock
    private func showLockAlert(message: String) {
        // Tìm key window tương thích iOS 13+
        let window: UIWindow? = {
            if #available(iOS 13.0, *) {
                return UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }
            } else {
                return UIApplication.shared.windows.first { $0.isKeyWindow }
            }
        }()

        guard let keyWindow = window,
              let rootVC = keyWindow.rootViewController else {
            NSLog("\(ShieldConfig.logPrefix) Cannot show alert — no root view controller")
            // Fallback: terminate
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                exit(0)
            }
            return
        }

        // Dismiss any presented VC first
        let presenter = rootVC.presentedViewController ?? rootVC

        let alert = UIAlertController(
            title: "License",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            // Thoát app sau khi bấm OK
            exit(0)
        })

        presenter.present(alert, animated: true)
    }

    // MARK: - Manual Activation

    /// Kích hoạt bằng license key (gọi từ bên ngoài)
    func activateWithKey(_ licenseKey: String, completion: @escaping (Bool) -> Void) {
        NSLog("\(ShieldConfig.logPrefix) Activating with license key...")

        // Lưu key
        KeychainStore.save(key: ShieldConfig.keyLicenseKey, value: licenseKey)

        // Gọi server activate
        ServerClient.shared.activate(licenseKey: licenseKey) { success, days in
            if success {
                let extensionDays = days ?? ShieldConfig.trialDays
                TimeLock.shared.extendLicense(days: extensionDays)
                NSLog("\(ShieldConfig.logPrefix) Activation SUCCESS — \(extensionDays) days")
                completion(true)
            } else {
                NSLog("\(ShieldConfig.logPrefix) Activation FAILED")
                completion(false)
            }
        }
    }

    // MARK: - Status Query

    /// Lấy thông tin license để hiển thị
    var licenseInfo: [String: String] {
        return TimeLock.shared.getLicenseInfo()
    }

    var isAppLocked: Bool {
        return isLocked
    }
}
