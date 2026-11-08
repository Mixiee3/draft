import XCTest
@testable import DraftCore

final class WindowFitTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testTallRestoredFrameIsShortenedAndKeptOnScreen() {
        let f = fitWindowFrame(CGRect(x: 1100, y: -300, width: 400, height: 1284), in: screen)
        XCTAssertLessThanOrEqual(f.height, 875 * 0.85 + 1)
        XCTAssertTrue(screen.contains(f), "\(f)")
    }

    func testFrameThatFitsIsUnchanged() {
        let r = CGRect(x: 900, y: 120, width: 400, height: 640)
        XCTAssertEqual(fitWindowFrame(r, in: screen), r)
    }

    func testOffscreenFrameMovesBack() {
        let f = fitWindowFrame(CGRect(x: 2000, y: 900, width: 400, height: 600), in: screen)
        XCTAssertTrue(screen.contains(f), "\(f)")
    }
}
