import Darwin
import Foundation

enum TunnelConfig {
    /// LocalDevVPN / SideStore-style loopback tunnel endpoint.
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "locus.targetDeviceIP"

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    static func isValidIPv4(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr()
        return trimmed.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    @discardableResult
    static func setTargetIP(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIPv4(trimmed) else { return false }
        UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        return true
    }
}
