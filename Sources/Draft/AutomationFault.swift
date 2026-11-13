import AppKit
import DraftCore

/// Fault injection (scripts/fault-test.sh), throwaway vault:
/// - `fault-write`: keeps typing into a note and saving every 20 ms until the script kills the process (SIGKILL).
/// - `fault-read`: after the kill, reports whether the crash was noticed and whether the vault is intact.
extension Automation {
    static func faultWrite() async {
        let id = m.library.liveDocs.first(where: { $0.title == "Fault test" })?.id ?? m.createDoc(title: "Fault test")
        guard let id else { return }
        await wait()
        guard let ed = m.editors[id] else { return }
        ed.focusBody(atStart: false)
        writeResult(["ready": true], "fault-ready.json")
        for i in 0..<100_000 {
            ed.controller.pastePlainForAutomation("line \(i) of the fault test\n")
            m.flushAll()
            await wait(0.02)
        }
    }

    static func faultRead() async {
        let v = m.vault
        let report = VaultCheck.run(v)
        let doc = m.library.liveDocs.first(where: { $0.title == "Fault test" })
        var docOK = false
        if let doc, let d = try? Data(contentsOf: v.dir.appendingPathComponent("docs/\(doc.id).json")), (try? JSONSerialization.jsonObject(with: d)) != nil { docOK = true } // VaultCheck (critical == 0) covers the schema
        let temps = (FileManager.default.enumerator(atPath: v.dir.path)?.allObjects as? [String] ?? []).filter { $0.contains(".tmp") || $0.contains("~") }
        writeResult(["crashNoticed": m.recovery.crash != nil, "critical": report.count(.critical), "issues": report.issues.map(\.id).prefix(5).map { $0 },
                     "docDecodes": docOK, "docFound": doc != nil, "words": doc?.words ?? -1, "temps": temps.count], "fault-read.json")
    }
}
