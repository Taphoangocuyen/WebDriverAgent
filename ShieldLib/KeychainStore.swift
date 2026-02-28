// KeychainStore.swift — iOS Keychain Wrapper
// Lưu/đọc/xóa trạng thái kích hoạt trong Keychain
// Keychain tồn tại qua app reinstall (trừ khi factory reset)

import Foundation
import Security

struct KeychainStore {

    private static let service = ShieldConfig.keychainService

    // MARK: - Save

    /// Lưu string value vào Keychain
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Xóa item cũ nếu tồn tại
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("\(ShieldConfig.logPrefix) Keychain: Save failed for '\(key)' — status: \(status)")
        }
        return status == errSecSuccess
    }

    // MARK: - Load

    /// Đọc string value từ Keychain
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    /// Xóa item khỏi Keychain
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Date helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Lưu Date vào Keychain
    @discardableResult
    static func saveDate(key: String, date: Date) -> Bool {
        return save(key: key, value: dateFormatter.string(from: date))
    }

    /// Đọc Date từ Keychain
    static func loadDate(key: String) -> Date? {
        guard let str = load(key: key) else { return nil }
        return dateFormatter.date(from: str)
    }

    // MARK: - Bool helpers

    @discardableResult
    static func saveBool(key: String, value: Bool) -> Bool {
        return save(key: key, value: value ? "1" : "0")
    }

    static func loadBool(key: String) -> Bool {
        return load(key: key) == "1"
    }

    // MARK: - Clear all

    /// Xóa toàn bộ Shield data khỏi Keychain
    static func clearAll() {
        let keys = [
            ShieldConfig.keyActivationStatus,
            ShieldConfig.keyActivationDate,
            ShieldConfig.keyExpiryDate,
            ShieldConfig.keyDeviceID,
            ShieldConfig.keyLicenseKey,
            ShieldConfig.keyLastServerCheck,
            ShieldConfig.keyLastKnownDate,
            ShieldConfig.keyGracePeriodStart
        ]
        for key in keys {
            delete(key: key)
        }
        NSLog("\(ShieldConfig.logPrefix) Keychain: All Shield data cleared")
    }
}
