import Foundation
import idevice
import UIKit
import UserNotifications
import CoreLocation

/// Runs idevice's iOS 27+ pairable-host flow on-device.
///
/// Advertising uses Network.framework NWListener (Bonjour). Inbound TCP is
/// relayed to the Rust pairable-host on loopback. The 6-digit PIN is created
/// only after that connection + pair-setup handshake.
@MainActor
final class PairOnDeviceService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case advertising
        case deviceConnected
        case awaitingPIN(String)
        case succeeded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pin: String?
    @Published private(set) var debugPort: UInt16?

    private var worker: Thread?
    private var callbackBox = PairCallbackBox()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let keepAlive = PairingKeepAlive()
    private let audioKeepAlive = SilentAudioKeepAlive()
    private let advertiser = PairableHostAdvertiser()

    var isBusy: Bool {
        switch phase {
        case .advertising, .deviceConnected, .awaitingPIN: return true
        default: return false
        }
    }

    func start(pairingStore: PairingStore) {
        guard !isBusy else { return }
        phase = .advertising
        pin = nil
        debugPort = nil
        let box = PairCallbackBox()
        box.owner = self
        callbackBox = box

        requestNotificationPermission()
        beginKeepAlive()

        _ = pairingStore.pairingURL
        do {
            try PairingCredentialProtection.applyDirectory(
                at: pairingStore.pairingURL.deletingLastPathComponent()
            )
        } catch {
            // start() already enabled background keep-alives; clean them up on failure.
            handleFailure("Kladz could not apply the required protection to the pairing folder. Check available storage and try again.")
            return
        }

        let outputPath = pairingStore.pairingURL.path

        worker = Thread {
            autoreleasepool {
                Self.runBlockingAccept(outputPath: outputPath, box: box)
            }
        }
        worker?.name = "locus.pairable-host"
        worker?.qualityOfService = .userInitiated
        worker?.start()
    }

    func acknowledgeFailure() {
        if case .failed = phase {
            teardown()
            phase = .idle
            pin = nil
        }
    }

    func resetToIdle() {
        teardown()
        phase = .idle
        pin = nil
        debugPort = nil
    }

    fileprivate func handleListening(
        port: UInt16,
        serviceIdentifier: String,
        name: String,
        model: String,
        authTag: String,
        ver: String,
        minVer: String
    ) {
        debugPort = port
        advertiser.onFailure = { [weak self] in
            self?.handleFailure("Could not start local pairing discovery. Check that local network access is allowed, then try again.")
        }
        advertiser.publish(
            port: port,
            serviceIdentifier: serviceIdentifier,
            name: name,
            model: model,
            authTag: authTag,
            ver: ver,
            minVer: minVer
        )
        phase = .advertising
        NSLog("[Kladz] listening on %u, Bonjour id=%@", port, serviceIdentifier)
    }

    fileprivate func handleConnected() {
        phase = .deviceConnected
        Self.postPlainNotification(
            title: "Kladz connected",
            body: "Generating pairing code…"
        )
    }

    fileprivate func handlePIN(_ value: String) {
        pin = value
        phase = .awaitingPIN(value)
        Self.postPINNotification()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    fileprivate func handleSuccess() {
        pin = nil
        phase = .succeeded
        teardown()
        Self.postPlainNotification(
            title: "Kladz paired",
            body: "RPPairing is ready. Connect LocalDevVPN, then teleport."
        )
    }

    fileprivate func handleFailure(_ message: String) {
        pin = nil
        phase = .failed(message)
        teardown()
    }

    private func teardown() {
        // Detach callbacks from this session so late native callbacks cannot
        // mutate the state of a later pairing attempt.
        callbackBox.owner = nil
        advertiser.stop()
        endKeepAlive()
    }

    private func beginKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = true
        keepAlive.start()
        audioKeepAlive.start()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "locus.pairable-host") { [weak self] in
            self?.endKeepAlive()
        }
    }

    private func endKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = false
        keepAlive.stop()
        audioKeepAlive.stop()
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func postPINNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Kladz pairing code"
        // Never put the pairing secret in a lock-screen notification preview.
        content.body = "Open Kladz to view your code."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: "locus.pairing.pin", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func postPlainNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "locus.pairing.status.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func runBlockingAccept(outputPath: String, box: PairCallbackBox) {
        let name = "Kladz"
        let model = "Mac17,7"

        var outFile: OpaquePointer?
        var altIRK = [UInt8](repeating: 0, count: 16)

        let err: UnsafeMutablePointer<IdeviceFfiError>? = name.withCString { namePtr in
            model.withCString { modelPtr in
                pairable_host_accept(
                    namePtr,
                    modelPtr,
                    0,
                    pinDisplayTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    listeningTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    connectedTrampoline,
                    Unmanaged.passUnretained(box).toOpaque(),
                    &altIRK,
                    &outFile
                )
            }
        }

        if let err {
            // Native error text may contain implementation details or sensitive paths.
            // Keep the UI message stable and avoid surfacing raw FFI diagnostics.
            idevice_error_free(err)
            DispatchQueue.main.async {
                box.owner?.handleFailure("Pairing could not be completed. Check that Developer Mode is open and try again.")
            }
            return
        }

        guard let outFile else {
            DispatchQueue.main.async {
                box.owner?.handleFailure("Pairing finished but no pairing file was returned.")
            }
            return
        }

        defer { rp_pairing_file_free(outFile) }

        let parent = (outputPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

        let writeError = outputPath.withCString { path in
            rp_pairing_file_write(outFile, path)
        }
        if let writeError {
            idevice_error_free(writeError)
            // The native writer may have created a partial file before failing.
            try? FileManager.default.removeItem(atPath: outputPath)
            DispatchQueue.main.async {
                box.owner?.handleFailure("Pairing completed, but Kladz could not save the pairing file. Check available storage and try again.")
            }
            return
        }

        do {
            try PairingCredentialProtection.apply(to: URL(fileURLWithPath: outputPath))
        } catch {
            try? FileManager.default.removeItem(atPath: outputPath)
            DispatchQueue.main.async {
                box.owner?.handleFailure("Pairing completed, but Kladz could not apply the required protection to the pairing file. The file was removed; please try again.")
            }
            return
        }
        DispatchQueue.main.async { box.owner?.handleSuccess() }
    }
}

private final class PairingKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }
}

final class PairCallbackBox: @unchecked Sendable {
    weak var owner: PairOnDeviceService?
}

private func pinDisplayTrampoline(pin: UnsafePointer<CChar>?, context: UnsafeMutableRawPointer?) {
    guard let pin, let context else { return }
    let value = String(cString: pin)
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { box.owner?.handlePIN(value) }
}

private func listeningTrampoline(
    port: UInt16,
    serviceIdentifier: UnsafePointer<CChar>?,
    name: UnsafePointer<CChar>?,
    model: UnsafePointer<CChar>?,
    authTag: UnsafePointer<CChar>?,
    ver: UnsafePointer<CChar>?,
    minVer: UnsafePointer<CChar>?,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    let values = (
        port,
        serviceIdentifier.map { String(cString: $0) } ?? "",
        name.map { String(cString: $0) } ?? "Kladz",
        model.map { String(cString: $0) } ?? "Mac17,7",
        authTag.map { String(cString: $0) } ?? "",
        ver.map { String(cString: $0) } ?? "26",
        minVer.map { String(cString: $0) } ?? "17"
    )
    // NetService must be touched on the main thread / runloop.
    DispatchQueue.main.async {
        box.owner?.handleListening(
            port: values.0,
            serviceIdentifier: values.1,
            name: values.2,
            model: values.3,
            authTag: values.4,
            ver: values.5,
            minVer: values.6
        )
    }
}

private func connectedTrampoline(context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<PairCallbackBox>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { box.owner?.handleConnected() }
}
