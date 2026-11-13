import Foundation
import CryptoKit

/// The update feed (see docs/UPDATES.md). Published as JSON:
///
///     { "payload": "<base64 of the items JSON>", "signature": "<base64 Ed25519 signature of payload bytes>" }
///
/// Every item's archive carries its own Ed25519 signature, size and SHA-256. The app holds only the
/// public key (Info.plist `DraftUpdatePublicKey`, set when a release is built); the private key never
/// enters the repository.
public struct UpdateItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(version)-\(build)" }
    public var version: String
    public var build: Int
    public var channel: String          // stable | beta | development
    public var date: String             // yyyy-MM-dd
    public var notes: [String]          // short lines, shown as a list
    public var url: String              // HTTPS (file:// only in test mode)
    public var size: Int64
    public var sha256: String
    public var signature: String        // base64 Ed25519 over the archive bytes
    public var minimumSystem: String    // e.g. "14.0"
    public var librarySchema: Int
    public var docSchema: Int
    public init(version: String, build: Int, channel: String, date: String, notes: [String], url: String, size: Int64, sha256: String, signature: String, minimumSystem: String, librarySchema: Int, docSchema: Int) {
        self.version = version; self.build = build; self.channel = channel; self.date = date; self.notes = notes; self.url = url
        self.size = size; self.sha256 = sha256; self.signature = signature; self.minimumSystem = minimumSystem
        self.librarySchema = librarySchema; self.docSchema = docSchema
    }
}

public struct SignedFeed: Codable, Sendable {
    public var payload: String
    public var signature: String
    public init(payload: String, signature: String) { self.payload = payload; self.signature = signature }
}

public enum UpdateError: LocalizedError, Equatable {
    case notHTTPS, badFeedSignature, badFeed, sizeMismatch, checksumMismatch, badArchiveSignature, noPublicKey
    public var errorDescription: String? {
        switch self {
        case .notHTTPS: return String(localized: "Updates are only downloaded over HTTPS.")
        case .badFeedSignature: return String(localized: "The update list isn't signed by Draft's release key, so it was ignored.")
        case .badFeed: return String(localized: "The update list couldn't be read.")
        case .sizeMismatch: return String(localized: "The download has the wrong size, so it was discarded.")
        case .checksumMismatch: return String(localized: "The download doesn't match its checksum, so it was discarded.")
        case .badArchiveSignature: return String(localized: "The download isn't signed by Draft's release key, so it was discarded.")
        case .noPublicKey: return String(localized: "This build of Draft can't verify updates (no release key), so updates are off.")
        }
    }
}

public enum Updates {
    public enum Compatibility: Equatable, Sendable { case ok, migration(fromLibrary: Int, toLibrary: Int), needsNewerSystem(String) }

    /// Which channels a person on `channel` is offered: stable sees stable; beta sees beta and stable;
    /// development sees everything.
    public static func offered(_ item: UpdateItem, to channel: String) -> Bool {
        switch channel {
        case "development": return true
        case "beta": return item.channel == "stable" || item.channel == "beta"
        default: return item.channel == "stable"
        }
    }

    /// The newest item newer than the running build, or nil.
    public static func newest(in items: [UpdateItem], channel: String, currentBuild: Int, skipped: String? = nil) -> UpdateItem? {
        items.filter { offered($0, to: channel) && $0.build > currentBuild && $0.id != skipped }.max { $0.build < $1.build }
    }

    public static func compatibility(_ item: UpdateItem, system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Compatibility {
        var need = item.minimumSystem.split(separator: ".").compactMap { Int($0) }
        need += Array(repeating: 0, count: max(0, 3 - need.count))
        let have = [system.majorVersion, system.minorVersion, system.patchVersion]
        if have.lexicographicallyPrecedes(need.prefix(3)) { return .needsNewerSystem(item.minimumSystem) }
        if item.librarySchema > librarySchemaVersion || item.docSchema > docSchemaVersion { return .migration(fromLibrary: librarySchemaVersion, toLibrary: item.librarySchema) }
        return .ok
    }

    public static func publicKey(base64: String?) throws -> Curve25519.Signing.PublicKey {
        guard let b = base64, let d = Data(base64Encoded: b), let k = try? Curve25519.Signing.PublicKey(rawRepresentation: d) else { throw UpdateError.noPublicKey }
        return k
    }

    /// Checks the feed's signature and decodes its items.
    public static func items(fromFeed data: Data, key: Curve25519.Signing.PublicKey) throws -> [UpdateItem] {
        guard let feed = try? JSONDecoder().decode(SignedFeed.self, from: data), let payload = Data(base64Encoded: feed.payload),
              let sig = Data(base64Encoded: feed.signature) else { throw UpdateError.badFeed }
        guard key.isValidSignature(sig, for: payload) else { throw UpdateError.badFeedSignature }
        guard let items = try? JSONDecoder().decode([UpdateItem].self, from: payload) else { throw UpdateError.badFeed }
        return items
    }

    /// Size, SHA-256 and Ed25519 signature of a downloaded archive.
    public static func verifyArchive(_ data: Data, item: UpdateItem, key: Curve25519.Signing.PublicKey) throws {
        guard Int64(data.count) == item.size else { throw UpdateError.sizeMismatch }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item.sha256.lowercased() else { throw UpdateError.checksumMismatch }
        guard let sig = Data(base64Encoded: item.signature), key.isValidSignature(sig, for: data) else { throw UpdateError.badArchiveSignature }
    }

    /// Only HTTPS, except file:// in test mode.
    public static func allowed(_ url: URL, testMode: Bool) -> Bool {
        url.scheme == "https" || (testMode && url.isFileURL)
    }

    // MARK: Publishing (used by scripts/sign-update.swift and tests)

    public static func signFeed(_ items: [UpdateItem], key: Curve25519.Signing.PrivateKey) throws -> Data {
        let payload = try DraftJSON.encode(items)
        let sig = try key.signature(for: payload)
        return try DraftJSON.encode(SignedFeed(payload: payload.base64EncodedString(), signature: sig.base64EncodedString()), pretty: true)
    }

    public static func describe(archive data: Data, key: Curve25519.Signing.PrivateKey) throws -> (size: Int64, sha256: String, signature: String) {
        (Int64(data.count), SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), try key.signature(for: data).base64EncodedString())
    }
}
