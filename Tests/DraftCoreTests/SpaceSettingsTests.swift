import XCTest
@testable import DraftCore

final class SpaceSettingsTests: XCTestCase {
    func testEachSpaceKeepsItsOwnThemeDailyAndTags() throws {
        var work = Settings(); work.theme = "dark"; work.showDailyNotes = false; work.tagColors = ["urgent": "#ff0000"]
        var home = Settings(); home.theme = "light"; home.showDailyNotes = true
        var live = home
        live.apply(work.spaceScoped)
        XCTAssertEqual(live.theme, "dark"); XCTAssertFalse(live.showDailyNotes); XCTAssertEqual(live.tagColors["urgent"], "#ff0000")
        live.apply(home.spaceScoped)
        XCTAssertEqual(live.theme, "light"); XCTAssertTrue(live.showDailyNotes); XCTAssertNil(live.tagColors["urgent"])
    }

    func testOlderFilesDecodeAndSidebarOrderIsRepaired() throws {
        let space = try JSONDecoder().decode(Space.self, from: Data(#"{"id":"s","name":"Home"}"#.utf8))
        XCTAssertNil(space.settings)
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"sidebarOrder":["tags","bogus","tags"]}"#.utf8))
        XCTAssertEqual(s.sidebarOrder, ["tags", "starred", "folders"])
        var round = Settings(); round.sidebarHidden = ["tags"]
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(round)).sidebarHidden, ["tags"])
    }
}
