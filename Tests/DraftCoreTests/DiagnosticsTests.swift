import XCTest
@testable import DraftCore

final class DiagnosticsTests: XCTestCase {
    func testReportHasNoNoteContentTitlesOrPaths() {
        let secretTitle = "Medical results Q3", secretText = "blood pressure 140/90"
        let i = Diagnostics.Input(description: "The app froze when I opened a long note.", appVersion: "0.10.0", build: "321", channel: "stable", commit: "abc1234",
                                  system: "27.0.1", machine: "Mac16,12", displays: ["2560×1600 Retina"],
                                  counts: ["notes": 42, "attachments": 7], switches: ["updateChecks": "off", "telemetry": "none"],
                                  performance: ["keystroke p95 17 ms"],
                                  log: ["2026-11-13 save failed for d_abc: NSCocoaErrorDomain 640", "opened /Users/daniel/Library/Application Support/Draft/Vault/docs/d_abc.json",
                                        "renamed to Medical results Q3"], includeLog: true)
        let r = Diagnostics.report(i, titles: [secretTitle])
        XCTAssertTrue(r.contains("The app froze"), "the person's own description is kept")
        XCTAssertFalse(r.contains(secretTitle), "titles are redacted even if a log line had one")
        XCTAssertFalse(r.contains(secretText))
        XCTAssertFalse(r.contains("/Users/"), "no personal paths")
        XCTAssertTrue(r.contains("~/Library"))
        XCTAssertTrue(r.contains("notes: 42"))
        XCTAssertFalse(Diagnostics.report({ var x = i; x.includeLog = false; return x }(), titles: [secretTitle]).contains("save failed"), "the log is only there when chosen")
    }
}
