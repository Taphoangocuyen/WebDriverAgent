// ServerClient.swift — Phone Home / Server Verification
// Khi ShieldConfig.serverEnabled = false → hoạt động offline (stub mode)
// Khi có server → gọi API verify/activate/heartbeat

import Foundation

class ServerClient {

    // MARK: - Singleton

    static let shared = ServerClient()
    private init() {}

    private var heartbeatTimer: Timer?

    // MARK: - API Models

    struct ActivateRequest: Codable {
        let appRequestID: String
        let deviceID: String
        let appName: String
        let bundleID: String
        let licenseKey: String
        let timestamp: String
    }

    struct VerifyRequest: Codable {
        let appRequestID: String
        let deviceID: String
        let appName: String
        let bundleID: String
        let timestamp: String
    }

    struct ServerResponse: Codable {
        let success: Bool
        let message: String?
        let expiryDays: Int?
        let signature: String?
    }

    // MARK: - Activate

    /// Kích hoạt license với server
    func activate(licenseKey: String, completion: @escaping (Bool, Int?) -> Void) {
        guard ShieldConfig.serverEnabled, !ShieldConfig.serverURL.isEmpty else {
            NSLog("\(ShieldConfig.logPrefix) Server: Disabled — offline activate (auto-approve)")
            completion(true, ShieldConfig.trialDays)
            return
        }

        let request = ActivateRequest(
            appRequestID: UUID().uuidString,
            deviceID: TimeLock.shared.getDeviceID(),
            appName: ShieldConfig.appName,
            bundleID: ShieldConfig.bundleID,
            licenseKey: licenseKey,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        postJSON(endpoint: "/activate", body: request) { response in
            if let resp = response, resp.success {
                NSLog("\(ShieldConfig.logPrefix) Server: Activate success — \(resp.expiryDays ?? 0) days")
                completion(true, resp.expiryDays)
            } else {
                NSLog("\(ShieldConfig.logPrefix) Server: Activate failed — \(response?.message ?? "no response")")
                completion(false, nil)
            }
        }
    }

    // MARK: - Verify

    /// Verify trạng thái license với server
    func verify(completion: @escaping (Bool, Int?) -> Void) {
        guard ShieldConfig.serverEnabled, !ShieldConfig.serverURL.isEmpty else {
            NSLog("\(ShieldConfig.logPrefix) Server: Disabled — offline verify (auto-approve)")
            completion(true, nil)
            return
        }

        let request = VerifyRequest(
            appRequestID: UUID().uuidString,
            deviceID: TimeLock.shared.getDeviceID(),
            appName: ShieldConfig.appName,
            bundleID: ShieldConfig.bundleID,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        postJSON(endpoint: "/verify", body: request) { response in
            if let resp = response, resp.success {
                // Cập nhật last server check
                KeychainStore.saveDate(key: ShieldConfig.keyLastServerCheck, date: Date())

                if let days = resp.expiryDays, days > 0 {
                    TimeLock.shared.extendLicense(days: days)
                }
                completion(true, resp.expiryDays)
            } else {
                NSLog("\(ShieldConfig.logPrefix) Server: Verify failed — \(response?.message ?? "no response")")
                completion(false, nil)
            }
        }
    }

    // MARK: - Heartbeat

    /// Bắt đầu gửi heartbeat định kỳ
    func startHeartbeat() {
        guard ShieldConfig.serverEnabled else {
            NSLog("\(ShieldConfig.logPrefix) Server: Heartbeat skipped — server disabled")
            return
        }

        stopHeartbeat()

        let interval = TimeInterval(ShieldConfig.heartbeatIntervalSecs)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }

        NSLog("\(ShieldConfig.logPrefix) Server: Heartbeat started — interval \(ShieldConfig.heartbeatIntervalSecs)s")
    }

    /// Dừng heartbeat
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Gửi 1 heartbeat
    private func sendHeartbeat() {
        guard ShieldReachability.shared.isReachable else {
            NSLog("\(ShieldConfig.logPrefix) Server: Heartbeat skipped — no network")
            return
        }

        verify { success, _ in
            if success {
                NSLog("\(ShieldConfig.logPrefix) Server: Heartbeat OK")
            } else {
                NSLog("\(ShieldConfig.logPrefix) Server: Heartbeat failed")
            }
        }
    }

    // MARK: - HTTP Client

    private func postJSON<T: Encodable>(endpoint: String, body: T, completion: @escaping (ServerResponse?) -> Void) {
        let urlString = ShieldConfig.serverURL + endpoint
        guard let url = URL(string: urlString) else {
            NSLog("\(ShieldConfig.logPrefix) Server: Invalid URL — \(urlString)")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShieldConfig.appID, forHTTPHeaderField: "X-App-ID")
        request.timeoutInterval = 15

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        } catch {
            NSLog("\(ShieldConfig.logPrefix) Server: Encode failed — \(error)")
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("\(ShieldConfig.logPrefix) Server: Request failed — \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                completion(nil)
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let resp = try decoder.decode(ServerResponse.self, from: data)
                completion(resp)
            } catch {
                NSLog("\(ShieldConfig.logPrefix) Server: Decode failed — \(error)")
                completion(nil)
            }
        }
        task.resume()
    }
}
