import Foundation
import UniformTypeIdentifiers
import UIKit

@MainActor
final class PairingStore: ObservableObject {
    @Published private(set) var hasPairingFile = false
    @Published var lastError: String?

    static let fileName = "rp_pairing_file.plist"
    private static let maximumPairingFileSize = 5 * 1_024 * 1_024
    static let supportedTypes: [UTType] = {
        var types: [UTType] = [
            .item,          // anything — sideloaded plists often lack a proper UTI
            .data,
            .propertyList,
            .xml,
        ]
        for ext in ["plist", "mobiledevicepairing", "mobiledevicepair"] {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        if let custom = UTType("com.chrismack.kladz.rppairing") {
            types.append(custom)
        }
        return types
    }()

    private var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    var pairingURL: URL {
        directoryURL.appendingPathComponent(Self.fileName)
    }

    var pairingPath: String { pairingURL.path }

    init() {
        refresh()
    }

    func refresh() {
        let exists = FileManager.default.fileExists(atPath: pairingURL.path)
        guard exists else {
            // Still secure the containing directory before a future credential write.
            do {
                try PairingCredentialProtection.applyDirectory(at: directoryURL)
            } catch {
                lastError = "Could not secure the pairing folder: \(error.localizedDescription)"
            }
            hasPairingFile = false
            return
        }

        do {
            try PairingCredentialProtection.apply(to: pairingURL)
            hasPairingFile = true
        } catch {
            // Fail closed: don't use credentials if their at-rest protections cannot be applied.
            hasPairingFile = false
            lastError = "Could not secure the pairing file. Import it again after restarting the app."
        }
    }

    func importPairing(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        // Read at most one byte beyond the limit so a misleading/missing file-size
        // attribute cannot cause an arbitrarily large allocation during import.
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let limit = Self.maximumPairingFileSize
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else {
            throw PairingImportError.fileTooLarge
        }
        try installPairingData(data)
    }

    /// LiveContainer / broken pickers: copy the plist text (or file) then paste here.
    func importPairingFromClipboard() throws {
        let board = UIPasteboard.general

        if let url = board.url ?? board.urls?.first, url.isFileURL {
            try importPairing(from: url)
            return
        }

        // Check one representation at a time. Keeping every clipboard representation
        // in an array can retain several copies of a large payload simultaneously.
        let pasteboardTypes = [
            "com.apple.property-list",
            UTType.propertyList.identifier,
            UTType.xml.identifier,
            UTType.data.identifier
        ]
        for type in pasteboardTypes {
            guard let data = board.data(forPasteboardType: type), !data.isEmpty else {
                continue
            }
            try installPairingData(data)
            return
        }

        if let text = board.string {
            guard text.utf8.count <= Self.maximumPairingFileSize else {
                throw PairingImportError.fileTooLarge
            }
            guard let data = text.data(using: .utf8), !data.isEmpty else {
                throw PairingImportError.emptyClipboard
            }
            try installPairingData(data)
            return
        }

        throw PairingImportError.emptyClipboard
    }

    func removePairing() throws {
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            try FileManager.default.removeItem(at: pairingURL)
        }
        hasPairingFile = false
    }

    private func installPairingData(_ data: Data) throws {
        guard data.count <= Self.maximumPairingFileSize else {
            throw PairingImportError.fileTooLarge
        }
        guard looksLikePairingPlist(data) else {
            throw PairingImportError.invalidContents
        }

        try PairingCredentialProtection.applyDirectory(at: directoryURL)
        // Atomic replacement preserves the previous valid pairing if the new write fails.
        // Do not delete the destination first: that creates an avoidable loss-of-credentials window.
        try data.write(to: pairingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do {
            try PairingCredentialProtection.apply(to: pairingURL)
        } catch {
            try? FileManager.default.removeItem(at: pairingURL)
            hasPairingFile = false
            throw error
        }
        hasPairingFile = true
        lastError = nil
    }

    private func looksLikePairingPlist(_ data: Data) -> Bool {
        guard let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else {
            return false
        }

        // RPPairing files are dictionaries. Reject arrays and arbitrary valid plists,
        // which are not valid pairing credentials for this app.
        return object is [String: Any]
    }
}

enum PairingImportError: LocalizedError {
    case emptyClipboard
    case invalidContents
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "Clipboard is empty. Copy your RPPairing plist text (or the file), then try Paste again."
        case .invalidContents:
            return "That doesn’t look like an RPPairing plist. Copy the full pairing file contents and try again."
        case .fileTooLarge:
            return "The pairing file is too large (maximum 5 MB). Choose the original RPPairing file and try again."
        }
    }
}


/// Shared protection policy for credentials created by either import or on-device pairing.
enum PairingCredentialProtection {
    static func applyDirectory(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                .posixPermissions: 0o700
            ],
            ofItemAtPath: directoryURL.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directoryURL
        try directory.setResourceValues(values)
    }

    static func apply(to fileURL: URL) throws {
        try applyDirectory(at: fileURL.deletingLastPathComponent())
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.setAttributes(
            [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                .posixPermissions: 0o600
            ],
            ofItemAtPath: fileURL.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = fileURL
        try file.setResourceValues(values)
    }
}
