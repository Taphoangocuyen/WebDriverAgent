// Config.swift — ShieldLib Configuration
// Cấu hình trung tâm cho hệ thống bảo vệ WDA
// ⚠️ THAY ĐỔI CÁC GIÁ TRỊ NÀY THEO NHU CẦU CỦA BẠN

import Foundation

struct ShieldConfig {

    // ═══════════════════════════════════════════════════
    // APP IDENTITY
    // ═══════════════════════════════════════════════════
    static let appID        = "com.icontrol.wda"
    static let appName      = "iPhoneControl"
    static let bundleID     = "com.facebook.WebDriverAgentRunner.xctrunner"

    // ═══════════════════════════════════════════════════
    // TRIAL / TIME LOCK
    // ═══════════════════════════════════════════════════
    static let trialDays: Int              = 30    // Số ngày dùng thử
    static let gracePeriodHours: Int       = 72    // Offline grace period (giờ)
    static let heartbeatIntervalSecs: Int  = 3600  // Phone home mỗi 1 giờ

    // ═══════════════════════════════════════════════════
    // SERVER (bật khi có server)
    // ═══════════════════════════════════════════════════
    static let serverEnabled: Bool   = false
    static let serverURL: String     = ""  // Ví dụ: "https://your-server.com/api"

    // ═══════════════════════════════════════════════════
    // RSA PUBLIC KEY (nhúng trong app — dùng để verify)
    // Private key giữ bí mật trên server
    // ═══════════════════════════════════════════════════
    static let rsaPublicKey = """
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvH1kOfj9vy2sbflJhrAf
    ncdwAqJx1H3+mFIHeJHinxVNsLpS5xKECw/W4V3U7Ouw+0OTXmG+tre9IWq+iqCD
    Rlwr/Uydf9SLDBv0ZiqkVwqUUGRN+aSn0yW6iApK5aHyxCdN1FiZ2+K7ZOdaRtMY
    67JrKmrY19CSOkixXQk9afdLh5boq96PcO7dCrezNAOZjQ8/JvyheN3K6EqwccXW
    im0sUcuxb0t4wtOv6gJszBjCFZF/gx4nmaRawemi5K7xXfBsxzYAbWK36jdkkeNl
    JuubSVPUPUJqh7SFhAU/QJCRguubC0q3p3p/uStR9U2C/+9RWrjRDtiIsfzVNZqO
    NwIDAQAB
    """

    // ═══════════════════════════════════════════════════
    // KEYCHAIN KEYS
    // ═══════════════════════════════════════════════════
    static let keychainService          = "com.icontrol.shield"
    static let keyActivationStatus      = "shield_activation_status"
    static let keyActivationDate        = "shield_activation_date"
    static let keyExpiryDate            = "shield_expiry_date"
    static let keyDeviceID              = "shield_device_id"
    static let keyLicenseKey            = "shield_license_key"
    static let keyLastServerCheck       = "shield_last_server_check"
    static let keyLastKnownDate         = "shield_last_known_date"
    static let keyGracePeriodStart      = "shield_grace_start"

    // ═══════════════════════════════════════════════════
    // LOG PREFIX
    // ═══════════════════════════════════════════════════
    static let logPrefix = "[Shield]"
}
