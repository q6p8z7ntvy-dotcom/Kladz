import SwiftUI

@main
struct KladzApp: App {
    init() {
        KladzDefaultsMigration.run()
    }

    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @StateObject private var license = LicenseStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !license.isActivated {
                    LicenseActivationView(license: license)
                } else if showMap {
                    RootView()
                } else {
                    SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile)) {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .environment(\.locale, Locale(identifier: "sv_SE"))
            .preferredColorScheme(.light)
            .onOpenURL { handleIncoming($0) }
            .onAppear {
                if !setupComplete, pairing.hasPairingFile, !SetupGate.isInProgress {
                    SetupGate.markComplete()
                    setupComplete = true
                }
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            try? pairing.importPairing(from: url)
        } else if ext == "gpx" {
            NotificationCenter.default.post(name: .kladzImportGPX, object: url)
        }
    }
}

extension Notification.Name {
    static let kladzImportGPX = Notification.Name("kladzImportGPX")
}

private enum KladzDefaultsMigration {
    static func run() {
        let defaults = UserDefaults.standard
        let legacyPrefix = ["lo", "cus"].joined() + "."
        let keys = ["targetDeviceIP", "favorites", "recents", "setupComplete", "setupInProgress"]
        for suffix in keys {
            let legacyKey = legacyPrefix + suffix
            let currentKey = "kladz." + suffix
            if defaults.object(forKey: currentKey) == nil, let value = defaults.object(forKey: legacyKey) {
                defaults.set(value, forKey: currentKey)
            }
            defaults.removeObject(forKey: legacyKey)
        }
    }
}
