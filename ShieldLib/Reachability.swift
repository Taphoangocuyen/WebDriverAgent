// Reachability.swift — Network Status Monitor
// Dùng SCNetworkReachability API để kiểm tra WiFi/Cellular/None
// Tương đương ashleymills/Reachability nhưng lightweight

import Foundation
import SystemConfiguration

class ShieldReachability {

    enum NetworkStatus: String {
        case wifi       = "WiFi"
        case cellular   = "Cellular"
        case none       = "No Connection"
    }

    // MARK: - Singleton

    static let shared = ShieldReachability()

    // MARK: - Properties

    private var reachabilityRef: SCNetworkReachability?
    private let queue = DispatchQueue(label: "com.icontrol.shield.reachability")
    private(set) var isRunning = false

    var whenReachable: ((NetworkStatus) -> Void)?
    var whenUnreachable: (() -> Void)?

    // MARK: - Init

    private init() {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let ref = withUnsafePointer(to: &zeroAddress) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                SCNetworkReachabilityCreateWithAddress(nil, addrPtr)
            }
        }
        self.reachabilityRef = ref
    }

    deinit {
        stopNotifier()
    }

    // MARK: - Current Status

    /// Lấy trạng thái mạng hiện tại (synchronous)
    var currentStatus: NetworkStatus {
        guard let ref = reachabilityRef else { return .none }

        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(ref, &flags) else { return .none }

        return statusFromFlags(flags)
    }

    var isReachable: Bool {
        return currentStatus != .none
    }

    // MARK: - Notifier

    /// Bắt đầu theo dõi thay đổi mạng
    func startNotifier() {
        guard !isRunning, let ref = reachabilityRef else { return }

        var context = SCNetworkReachabilityContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCNetworkReachabilityCallBack = { _, flags, info in
            guard let info = info else { return }
            let reachability = Unmanaged<ShieldReachability>.fromOpaque(info).takeUnretainedValue()
            reachability.handleFlagsChanged(flags)
        }

        if SCNetworkReachabilitySetCallback(ref, callback, &context) {
            SCNetworkReachabilitySetDispatchQueue(ref, queue)
            isRunning = true
            NSLog("\(ShieldConfig.logPrefix) Reachability: Notifier started")
        }
    }

    /// Dừng theo dõi
    func stopNotifier() {
        guard let ref = reachabilityRef, isRunning else { return }
        SCNetworkReachabilitySetCallback(ref, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(ref, nil)
        isRunning = false
    }

    // MARK: - Private

    private func handleFlagsChanged(_ flags: SCNetworkReachabilityFlags) {
        let status = statusFromFlags(flags)
        NSLog("\(ShieldConfig.logPrefix) Reachability: \(status.rawValue)")

        DispatchQueue.main.async { [weak self] in
            if status == .none {
                self?.whenUnreachable?()
            } else {
                self?.whenReachable?(status)
            }
        }

        // Post notification
        NotificationCenter.default.post(
            name: .shieldReachabilityChanged,
            object: self,
            userInfo: ["status": status]
        )
    }

    private func statusFromFlags(_ flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        guard flags.contains(.reachable) else { return .none }

        if flags.contains(.connectionRequired) {
            if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
                if !flags.contains(.interventionRequired) {
                    return flags.contains(.isWWAN) ? .cellular : .wifi
                }
            }
            return .none
        }

        return flags.contains(.isWWAN) ? .cellular : .wifi
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let shieldReachabilityChanged = Notification.Name("ShieldReachabilityChanged")
}
