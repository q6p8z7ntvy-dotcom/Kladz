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
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        applyDataProtection()
        hasPairingFile = FileManager.default.fileExists(atPath: pairingURL.path)
    }

    /// Apply credential protections to the pairing directory and, when present, file.
    private func applyDataProtection() {
        try? PairingCredentialProtection.apply(to: pairingURL)
    }

    func importPairing(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attributes[.size] as? NSNumber,
           size.uint64Value > UInt64(Self.maximumPairingFileSize) {
            throw PairingImportError.fileTooLarge
        }
        let data = try Data(contentsOf: sourceURL)
        try installPairingData(data)
    }

    /// LiveContainer / broken pickers: copy the plist text (or file) then paste here.
    func importPairingFromClipboard() throws {
        let board = UIPasteboard.general

        if let url = board.url ?? board.urls?.first {
            if url.isFileURL {
                try importPairing(from: url)
                return
            }
        }

        let candidates: [Data?] = [
            board.data(forPasteboardType: "com.apple.property-list"),
            board.data(forPasteboardType: UTType.propertyList.identifier),
            board.data(forPasteboardType: UTType.xml.identifier),
            board.data(forPasteboardType: UTType.data.identifier),
            board.string?.data(using: .utf8),
        ]

        guard let data = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw PairingImportError.emptyClipboard
        }
        try installPairingData(data)
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
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            try FileManager.default.removeItem(at: pairingURL)
        }
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

        // Pairing files must be a valid property-list collection, not arbitrary XML/text.
        return object is [AnyHashable: Any] || object is [Any]
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
