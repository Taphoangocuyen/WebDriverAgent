// MZRSA.swift — RSA Encryption/Decryption
// Dùng Security.framework (iOS native) để encrypt/decrypt/verify
// Public key nhúng trong app, private key giữ trên server

import Foundation
import Security

struct MZRSA {

    // MARK: - Public Key Operations

    /// Load public key từ base64 string (không có header/footer PEM)
    static func loadPublicKey(_ base64String: String) -> SecKey? {
        let keyString = base64String
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let keyData = Data(base64Encoded: keyString) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Failed to decode base64 public key")
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:      kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Failed to create public key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return secKey
    }

    /// Load private key từ base64 string
    static func loadPrivateKey(_ base64String: String) -> SecKey? {
        let keyString = base64String
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let keyData = Data(base64Encoded: keyString) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Failed to decode base64 private key")
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:      kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Failed to create private key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return secKey
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypt data với public key
    static func encrypt(data: Data, publicKey: SecKey) -> Data? {
        let algorithm: SecKeyAlgorithm = .rsaEncryptionOAEPSHA256

        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Algorithm not supported for encryption")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &error) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Encryption failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return encryptedData as Data
    }

    /// Decrypt data với private key
    static func decrypt(data: Data, privateKey: SecKey) -> Data? {
        let algorithm: SecKeyAlgorithm = .rsaEncryptionOAEPSHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Algorithm not supported for decryption")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, data as CFData, &error) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Decryption failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return decryptedData as Data
    }

    // MARK: - String convenience

    /// Encrypt string → base64 string
    static func encryptString(_ string: String, publicKeyBase64: String) -> String? {
        guard let publicKey = loadPublicKey(publicKeyBase64),
              let data = string.data(using: .utf8),
              let encrypted = encrypt(data: data, publicKey: publicKey) else {
            return nil
        }
        return encrypted.base64EncodedString()
    }

    /// Decrypt base64 string → string
    static func decryptString(_ base64String: String, privateKeyBase64: String) -> String? {
        guard let privateKey = loadPrivateKey(privateKeyBase64),
              let data = Data(base64Encoded: base64String),
              let decrypted = decrypt(data: data, privateKey: privateKey) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    // MARK: - Signature Verification

    /// Verify RSA signature (server ký, app verify bằng public key)
    static func verifySignature(data: Data, signature: Data, publicKeyBase64: String) -> Bool {
        guard let publicKey = loadPublicKey(publicKeyBase64) else {
            return false
        }

        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePKCS1v15SHA256

        guard SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Verify algorithm not supported")
            return false
        }

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            algorithm,
            data as CFData,
            signature as CFData,
            &error
        )

        if !result {
            NSLog("\(ShieldConfig.logPrefix) RSA: Signature verification failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
        }
        return result
    }

    /// Verify license string: data|base64signature
    static func verifyLicense(_ licenseString: String) -> [String: Any]? {
        let parts = licenseString.components(separatedBy: "|")
        guard parts.count == 2,
              let dataPayload = parts[0].data(using: .utf8),
              let signatureData = Data(base64Encoded: parts[1]) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: Invalid license format")
            return nil
        }

        guard verifySignature(data: dataPayload, signature: signatureData, publicKeyBase64: ShieldConfig.rsaPublicKey) else {
            NSLog("\(ShieldConfig.logPrefix) RSA: License signature invalid")
            return nil
        }

        // Parse JSON payload
        guard let json = try? JSONSerialization.jsonObject(with: dataPayload) as? [String: Any] else {
            NSLog("\(ShieldConfig.logPrefix) RSA: License payload not valid JSON")
            return nil
        }

        NSLog("\(ShieldConfig.logPrefix) RSA: License verified successfully")
        return json
    }
}
