// TimeLock.swift — Time-based Lock Mechanism
// Quản lý trial period, expiry, chống chỉnh ngày, offline grace period

import Foundation
import UIKit

class TimeLock {

    enum LockStatus {
        case active             // Còn hạn, hoạt động bình thường
        case expired            // Hết hạn
        case tampered           // Phát hiện chỉnh ngày ngược
        case graceActive        // Offline grace period đang hoạt động
        case graceExpired       // Grace period đã hết
        case notActivated       // Chưa kích hoạt (lần đầu)
    }

    // MARK: - Singleton

    static let shared = TimeLock()
    private init() {}

    // MARK: - Check Status

    /// Kiểm tra trạng thái lock hiện tại
    func checkStatus() -> LockStatus {
        let now = Date()

        // 1. Chưa kích hoạt?
        guard let activationDateStr = KeychainStore.load(key: ShieldConfig.keyActivationDate),
              let _ = dateFromString(activationDateStr) else {
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Not activated yet")
            return .notActivated
        }

        // 2. Chống chỉnh ngày ngược
        if isDateTampered(now) {
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Date tampering detected!")
            return .tampered
        }

        // Cập nhật last_known_date
        KeychainStore.saveDate(key: ShieldConfig.keyLastKnownDate, date: now)

        // 3. Kiểm tra hạn sử dụng
        guard let expiryDateStr = KeychainStore.load(key: ShieldConfig.keyExpiryDate),
              let expiryDate = dateFromString(expiryDateStr) else {
            NSLog("\(ShieldConfig.logPrefix) TimeLock: No expiry date found")
            return .expired
        }

        if now < expiryDate {
            let daysLeft = Calendar.current.dateComponents([.day], from: now, to: expiryDate).day ?? 0
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Active — \(daysLeft) days remaining")
            return .active
        }

        // 4. Hết hạn — kiểm tra offline grace period
        let reachability = ShieldReachability.shared
        if !reachability.isReachable || !ShieldConfig.serverEnabled {
            return checkGracePeriod(now: now)
        }

        NSLog("\(ShieldConfig.logPrefix) TimeLock: Expired")
        return .expired
    }

    // MARK: - Activate Trial

    /// Kích hoạt trial period
    func activateTrial() {
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: ShieldConfig.trialDays, to: now)!
        let deviceID = getDeviceID()

        KeychainStore.saveDate(key: ShieldConfig.keyActivationDate, date: now)
        KeychainStore.saveDate(key: ShieldConfig.keyExpiryDate, date: expiry)
        KeychainStore.saveDate(key: ShieldConfig.keyLastKnownDate, date: now)
        KeychainStore.save(key: ShieldConfig.keyDeviceID, value: deviceID)
        KeychainStore.saveBool(key: ShieldConfig.keyActivationStatus, value: true)

        NSLog("\(ShieldConfig.logPrefix) TimeLock: Trial activated — \(ShieldConfig.trialDays) days, expires \(dateToString(expiry))")
    }

    // MARK: - Extend License

    /// Gia hạn license (gọi từ server response hoặc manual)
    func extendLicense(days: Int) {
        let now = Date()
        // Gia hạn từ ngày hiện tại (không từ ngày hết hạn cũ)
        let newExpiry = Calendar.current.date(byAdding: .day, value: days, to: now)!

        KeychainStore.saveDate(key: ShieldConfig.keyExpiryDate, date: newExpiry)
        KeychainStore.saveDate(key: ShieldConfig.keyLastKnownDate, date: now)
        KeychainStore.saveDate(key: ShieldConfig.keyLastServerCheck, date: now)

        // Reset grace period
        KeychainStore.delete(key: ShieldConfig.keyGracePeriodStart)

        NSLog("\(ShieldConfig.logPrefix) TimeLock: License extended — \(days) days, new expiry \(dateToString(newExpiry))")
    }

    // MARK: - Anti-Tamper

    /// Phát hiện chỉnh ngày ngược
    private func isDateTampered(_ now: Date) -> Bool {
        guard let lastKnownDate = KeychainStore.loadDate(key: ShieldConfig.keyLastKnownDate) else {
            return false // Lần đầu, chưa có dữ liệu
        }

        // Cho phép sai lệch 5 phút (timezone/NTP sync)
        let tolerance: TimeInterval = 5 * 60
        if now.timeIntervalSince(lastKnownDate) < -tolerance {
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Clock moved backwards — last: \(dateToString(lastKnownDate)), now: \(dateToString(now))")
            return true
        }

        // Phát hiện nhảy quá xa về tương lai (> 366 ngày)
        let maxForwardJump: TimeInterval = 366 * 24 * 3600
        if now.timeIntervalSince(lastKnownDate) > maxForwardJump {
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Suspicious forward time jump detected")
            return true
        }

        return false
    }

    // MARK: - Grace Period

    /// Kiểm tra offline grace period
    private func checkGracePeriod(now: Date) -> LockStatus {
        let graceHours = ShieldConfig.gracePeriodHours

        if let graceStart = KeychainStore.loadDate(key: ShieldConfig.keyGracePeriodStart) {
            // Grace đã bắt đầu — kiểm tra còn hạn không
            let graceEnd = Calendar.current.date(byAdding: .hour, value: graceHours, to: graceStart)!
            if now < graceEnd {
                let hoursLeft = Int(graceEnd.timeIntervalSince(now) / 3600)
                NSLog("\(ShieldConfig.logPrefix) TimeLock: Grace period active — \(hoursLeft)h remaining")
                return .graceActive
            } else {
                NSLog("\(ShieldConfig.logPrefix) TimeLock: Grace period expired")
                return .graceExpired
            }
        } else {
            // Bắt đầu grace period
            KeychainStore.saveDate(key: ShieldConfig.keyGracePeriodStart, date: now)
            NSLog("\(ShieldConfig.logPrefix) TimeLock: Grace period started — \(graceHours)h")
            return .graceActive
        }
    }

    // MARK: - Device ID

    /// Lấy device identifier (UDID thay thế)
    func getDeviceID() -> String {
        // Thử đọc từ Keychain trước (persistent)
        if let savedID = KeychainStore.load(key: ShieldConfig.keyDeviceID) {
            return savedID
        }

        // Tạo mới từ identifierForVendor + bundle info
        var deviceID: String
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            deviceID = vendorID
        } else {
            deviceID = UUID().uuidString
        }

        KeychainStore.save(key: ShieldConfig.keyDeviceID, value: deviceID)
        return deviceID
    }

    // MARK: - Info

    /// Lấy thông tin license hiện tại
    func getLicenseInfo() -> [String: String] {
        var info: [String: String] = [:]
        info["status"] = "\(checkStatus())"
        info["device_id"] = KeychainStore.load(key: ShieldConfig.keyDeviceID) ?? "N/A"

        if let activation = KeychainStore.load(key: ShieldConfig.keyActivationDate) {
            info["activation_date"] = activation
        }
        if let expiry = KeychainStore.load(key: ShieldConfig.keyExpiryDate) {
            info["expiry_date"] = expiry
        }
        if let lastCheck = KeychainStore.load(key: ShieldConfig.keyLastServerCheck) {
            info["last_server_check"] = lastCheck
        }
        return info
    }

    // MARK: - Date Helpers

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func dateToString(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    private func dateFromString(_ str: String) -> Date? {
        return dateFormatter.date(from: str)
    }
}
