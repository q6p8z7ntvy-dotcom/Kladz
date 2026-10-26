import CryptoKit
import Foundation
import Security

/// Verifies owner-issued Ed25519 licenses. The signing private key must never ship in the app.
@MainActor
final class LicenseStore: ObservableObject {
    @Published private(set) var isActivated = false
    @Published var errorMessage: String?
    @Published private(set) var deviceID: String

    private let defaults = UserDefaults.standard
    private let deviceIDKey = "kladz.license.deviceID"
    private let tokenService = "com.chrismack.kladz.license"
    private let tokenAccount = "activation-token"
    private let publicKeyBase64URL = "TVj5AgIVM7K3d8m18tYb_0oSOea39HmBPbqVsRqqFH0"

    init() {
        let saved = UserDefaults.standard.string(forKey: "kladz.license.deviceID")
        let id = saved ?? UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "kladz.license.deviceID")
        deviceID = id
        isActivated = storedTokenIsValid()
    }

    func activate(_ rawToken: String) {
        errorMessage = nil
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard verify(token) else {
            errorMessage = String(localized: "license.invalid")
            return
        }
        guard saveToken(token) else {
            errorMessage = String(localized: "license.save_failed")
            return
        }
        isActivated = true
    }

    private func storedTokenIsValid() -> Bool {
        guard let token = readToken() else { return false }
        return verify(token)
    }

    private func verify(_ token: String) -> Bool {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let payloadData = Self.decodeBase64URL(String(pieces[0])),
              let signature = Self.decodeBase64URL(String(pieces[1])),
              let publicKeyData = Self.decodeBase64URL(publicKeyBase64URL),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              publicKey.isValidSignature(signature, for: Data(String(pieces[0]).utf8)),
              let payload = try? JSONDecoder().decode(LicensePayload.self, from: payloadData)
        else { return false }

        return payload.deviceID.caseInsensitiveCompare(deviceID) == .orderedSame
            && payload.expiresAt > Date().timeIntervalSince1970
            && !payload.licenseID.isEmpty
    }

    private func saveToken(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    private func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}

private struct LicensePayload: Decodable {
    let deviceID: String
    let expiresAt: TimeInterval
    let licenseID: String
}
