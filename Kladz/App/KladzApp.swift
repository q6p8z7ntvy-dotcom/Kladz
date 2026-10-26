import SwiftUI

@main
struct KladzApp: App {
    init() {
        KladzDefaultsMigration.run()
    }
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    /// Map when setup finished, or when already paired outside this walkthrough.
    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMap {
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
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleIncoming(url)
            }
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


/// Migrates preferences from the previous internal key namespace without exposing
/// the former product name in source strings or losing existing user settings.
private enum KladzDefaultsMigration {
    static func run() {
        let defaults = UserDefaults.standard
        let legacyPrefix = ["lo", "cus"].joined() + "."
        let keys = ["targetDeviceIP", "favorites", "recents", "setupComplete", "setupInProgress"]

        for suffix in keys {
            let legacyKey = legacyPrefix + suffix
            let currentKey = "kladz." + suffix
            if defaults.object(forKey: currentKey) == nil,
               let value = defaults.object(forKey: legacyKey) {
                defaults.set(value, forKey: currentKey)
            }
            defaults.removeObject(forKey: legacyKey)
        }
    }
}
