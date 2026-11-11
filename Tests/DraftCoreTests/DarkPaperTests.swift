import XCTest
@testable import DraftCore

final class DarkPaperTests: XCTestCase {
    func testUntouchedPaperTurnsDarkOnlyForDisplay() {
        let a = DocumentAppearance(styleId: "paper")
        XCTAssertTrue(ColorMath.isDark(Styles.forDisplay(a, dark: true).pageColor))
        XCTAssertEqual(Styles.forDisplay(a, dark: false), Styles.resolve(a))
    }

    func testChosenColorsAndOtherStylesAreKept() {
        var custom = DocumentAppearance(styleId: "paper")
        custom.overrides.pageColor = "#fff0f0"
        XCTAssertEqual(Styles.forDisplay(custom, dark: true), Styles.resolve(custom))
        let ember = DocumentAppearance(styleId: "ember")
        XCTAssertEqual(Styles.forDisplay(ember, dark: true), Styles.resolve(ember))
    }
}
