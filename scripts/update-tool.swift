// Release-side update tool (the app only verifies). Usage:
//   swift scripts/update-tool.swift keygen <private-key-file>        # once; keep the file out of git
//   swift scripts/update-tool.swift pubkey <private-key-file>        # base64 public key for the build
//   swift scripts/update-tool.swift item <private-key-file> <archive.zip> <version> <build> <channel> <url> <notes.md> <library-schema> <doc-schema> [min-macOS]
//       → prints one feed item (JSON) for the archive
//   swift scripts/update-tool.swift feed <private-key-file> <items.json>  → signed feed on stdout
// The feed and item formats are documented in docs/UPDATES.md and match DraftCore/Updates.swift.
import CryptoKit
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
let a = CommandLine.arguments
guard a.count >= 3 else { fail("see the usage at the top of this file") }
func key(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let d = FileManager.default.contents(atPath: path), let raw = Data(base64Encoded: String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("can't read the private key at \(path)") }
    return k
}
let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
switch a[1] {
case "keygen":
    guard !FileManager.default.fileExists(atPath: a[2]) else { fail("\(a[2]) exists; refusing to overwrite a key") }
    let k = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: a[2], contents: k.rawRepresentation.base64EncodedString().data(using: .utf8), attributes: [.posixPermissions: 0o600])
    print(k.publicKey.rawRepresentation.base64EncodedString())
case "pubkey":
    print(key(a[2]).publicKey.rawRepresentation.base64EncodedString())
case "item":
    guard a.count >= 11 else { fail("item needs: key archive version build channel url notes.md library-schema doc-schema [min-macOS]") }
    guard let data = FileManager.default.contents(atPath: a[3]) else { fail("can't read \(a[3])") }
    let notes = (try? String(contentsOfFile: a[8], encoding: .utf8)).map { $0.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")) }.filter { !$0.isEmpty && !$0.hasPrefix("#") } } ?? []
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    let item: [String: Any] = ["version": a[4], "build": Int(a[5]) ?? 0, "channel": a[6], "url": a[7], "notes": notes, "date": f.string(from: Date()),
                               "size": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                               "signature": try! key(a[2]).signature(for: data).base64EncodedString(),
                               "librarySchema": Int(a[9]) ?? 0, "docSchema": Int(a[10]) ?? 0, "minimumSystem": a.count > 11 ? a[11] : "14.0"]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]), as: UTF8.self))
case "feed":
    guard a.count >= 4, let items = FileManager.default.contents(atPath: a[3]), let arr = try? JSONSerialization.jsonObject(with: items) as? [Any] else { fail("feed needs: key items.json (a JSON array of items)") }
    let payload = try! JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys, .withoutEscapingSlashes])
    let sig = try! key(a[2]).signature(for: payload)
    print(String(decoding: try! JSONSerialization.data(withJSONObject: ["payload": payload.base64EncodedString(), "signature": sig.base64EncodedString()], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
default: fail("unknown command \(a[1])")
}
