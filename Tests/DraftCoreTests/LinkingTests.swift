import XCTest
@testable import DraftCore

final class LinkingTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Prague")!; c.firstWeekday = 2; return c }()

    func link(_ t: String, _ doc: String, _ block: String? = nil) -> Node {
        var a: [String: JSONValue] = ["docId": .string(doc)]
        if let block { a["blockId"] = .string(block) }
        return .text(t, marks: [Mark("docLink", attrs: a)])
    }

    func sampleDoc(_ id: String = "d_a", updated: Double = 1) -> DocFile {
        var d = DocFile.empty(id: id, title: "A")
        d.updatedAt = updated
        d.content = Node("doc", content: [
            Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Plan")]),
            Node("paragraph", attrs: ["id": "b_p"], content: [.text("See "), link("B", "d_b"), .text(" and "), link("Goal", "d_b", "b_goal"),
                                                                .text(" #Work #fff #123 #ok-2 C#x "), .text("#code", marks: [Mark("code")])]),
            Node("taskList", attrs: ["id": "b_l"], content: [
                Node("taskItem", attrs: ["id": "b_t1", "checked": false], content: [Node("paragraph", attrs: ["id": "b_t1p"], content: [.text("call "), .text("Fri", marks: [Mark("date", attrs: ["date": "2026-11-13"])])])]),
                Node("taskItem", attrs: ["id": "b_t2", "checked": true, "due": "2026-11-01"], content: [Node("paragraph", attrs: ["id": "b_t2p"], content: [.text("done")])]),
                Node("taskItem", attrs: ["id": "b_t3"], content: [Node("paragraph", attrs: ["id": "b_t3p"], content: [.text("someday #work")])]),
            ]),
            Node("codeBlock", attrs: ["id": "b_c"], content: [.text("#notatag")]),
        ])
        return d
    }

    func testEntryExtractsLinksTagsTasksAndBlocks() {
        let e = VaultIndex.entry(for: sampleDoc(), daily: nil, rules: TagRules())
        XCTAssertEqual(e.links.map(\.doc), ["d_b", "d_b"])
        XCTAssertEqual(e.links.map(\.target), [nil, "b_goal"])
        XCTAssertEqual(e.links.first?.block, "b_p")
        XCTAssertEqual(e.tags.map(\.tag), ["Work", "ok-2", "work"], "hex, numeric, code, code blocks and C# are not tags")
        XCTAssertEqual(e.tasks.map(\.block), ["b_t1", "b_t2", "b_t3"], "tasks are addressed by their item id")
        XCTAssertEqual(e.tasks.map(\.due), ["2026-11-13", "2026-11-01", nil])
        XCTAssertEqual(e.blocks.map(\.id), ["b_h", "b_p", "b_t1", "b_t2", "b_t3", "b_c"])
        let daily = VaultIndex.entry(for: sampleDoc(), daily: "2026-11-07", rules: TagRules())
        XCTAssertEqual(daily.tasks[2].due, "2026-11-07", "tasks in a daily note are due that day")
    }

    func testSettingTask() {
        let d = sampleDoc().content
        let done = d.settingTask("b_t1", checked: true)!
        XCTAssertEqual(VaultIndex.entry(for: DocFile(id: "x", title: "", content: done, appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), daily: nil, rules: TagRules()).tasks[0].checked, true)
        XCTAssertNil(d.settingTask("b_p", checked: true), "only tasks can be checked")
        XCTAssertEqual(done.settingTask("b_t1", checked: false), d)
    }

    func testTimesAndChipLabelsAndDueEditing() {
        let today = "2026-11-07"
        func p(_ s: String) -> String? { DateParse.parse(s, today: today, weekStart: 2, cal: cal) }
        XCTAssertEqual(p("tomorrow 3pm"), "2026-11-08T15:00")
        XCTAssertEqual(p("fri at 14:30"), "2026-11-13T14:30")
        XCTAssertEqual(p("nov 12 9:05"), "2026-11-12T09:05")
        XCTAssertEqual(p("12am"), "2026-11-07T00:00")
        XCTAssertEqual(p("nov 12"), "2026-11-12", "a bare number is a day, not a time")
        XCTAssertNil(p("tomorrow 25:00")); XCTAssertNil(p("13pm"))
        XCTAssertTrue(Day.chipLabel("2026-11-09", today: today, cal: cal).contains("9"))
        XCTAssertTrue(Day.chipLabel("2026-11-09T14:30", today: today, cal: cal).hasSuffix("14:30"))
        XCTAssertTrue(Day.chipLabel("2027-01-03", today: today, cal: cal).contains("2027"))
        XCTAssertEqual(Day.chipLabel("2026-11-09", today: today, cal: cal), Day.chipLabel("2026-11-09", today: "2026-11-09", cal: cal), "the stored label doesn't change with the day")
        let d = sampleDoc().content
        let due = d.settingTaskDue("b_t3", due: "2026-11-09T09:00", label: "Mon 9 Nov 09:00")!
        let e = VaultIndex.entry(for: DocFile(id: "x", title: "", content: due, appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), daily: nil, rules: TagRules())
        XCTAssertEqual(e.tasks[2].due, "2026-11-09T09:00")
        let moved = due.settingTaskDue("b_t3", due: "2026-11-10", label: "Tue 10 Nov")!
        XCTAssertEqual(VaultIndex.entry(for: DocFile(id: "x", title: "", content: moved, appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), daily: nil, rules: TagRules()).tasks[2].due, "2026-11-10", "replaces, never adds a second date")
        XCTAssertEqual(moved.settingTaskDue("b_t3", due: nil, label: ""), d, "clearing restores the original task")
        XCTAssertNil(d.settingTaskDue("b_p", due: nil, label: ""))
    }

    func testTagRules() {
        let r = TagRules(custom: ["#todo"])
        XCTAssertFalse(r.allows("fff")); XCTAssertFalse(r.allows("A1B2C3")); XCTAssertFalse(r.allows("42")); XCTAssertFalse(r.allows("TODO"))
        XCTAssertTrue(r.allows("face1")); XCTAssertTrue(r.allows("q4"))
        XCTAssertTrue(TagRules(ignoreHex: false, ignoreNumeric: false).allows("fff"))
        XCTAssertEqual(Tags.find(in: "a #x/y. url.com/#frag &#38; #ünï", rules: TagRules()).map(\.name), ["x/y", "ünï"])
    }

    func testRefreshIsIncrementalAndRebuildIsEquivalent() {
        var store: [String: DocFile] = ["d_a": sampleDoc(), "d_b": sampleDoc("d_b", updated: 2)]
        var metas: [String: DocMeta] = ["d_a": DocMeta(id: "d_a", updatedAt: 1), "d_b": DocMeta(id: "d_b", updatedAt: 2)]
        var loads = 0
        let load: (String) -> DocFile? = { loads += 1; return store[$0] }
        var idx = VaultIndex()
        XCTAssertEqual(idx.refresh(docs: metas, rules: TagRules(), load: load), 2)
        XCTAssertEqual(idx.refresh(docs: metas, rules: TagRules(), load: load), 0, "unchanged documents are not re-read")
        store["d_b"]!.content.content!.removeLast(); store["d_b"]!.updatedAt = 3; metas["d_b"]!.updatedAt = 3
        metas["d_c"] = nil
        loads = 0
        XCTAssertEqual(idx.refresh(docs: metas, rules: TagRules(), load: load), 1)
        XCTAssertEqual(loads, 1)
        var fresh = VaultIndex()
        fresh.refresh(docs: metas, rules: TagRules(), load: load)
        XCTAssertEqual(idx, fresh, "incremental == rebuilt from scratch")
        XCTAssertEqual(idx.refresh(docs: metas, rules: TagRules(custom: ["work"]), load: load), 2, "changing tag rules re-indexes everything")
        // Encodes and decodes losslessly (index/index.json).
        let back = try! JSONDecoder().decode(VaultIndex.self, from: JSONEncoder().encode(idx))
        XCTAssertEqual(back, idx)
    }

    func testBacklinksBlockLocationsTagsAndQuickOpenBlocks() {
        var idx = VaultIndex()
        var b = DocFile.empty(id: "d_b", title: "B")
        b.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_goal"], content: [.text("Goal: ship")])])
        let store = ["d_a": sampleDoc(), "d_b": b]
        idx.refresh(docs: ["d_a": DocMeta(id: "d_a", updatedAt: 1), "d_b": DocMeta(id: "d_b", updatedAt: b.updatedAt)], rules: TagRules()) { store[$0] }
        let live: Set<String> = ["d_a", "d_b"]
        XCTAssertEqual(idx.backlinks(to: "d_b", live: live).count, 2)
        XCTAssertEqual(idx.backlinks(to: "d_b", live: ["d_b"]).count, 0, "links from deleted documents are not shown")
        XCTAssertEqual(idx.blockLocations()["b_goal"], "d_b")
        XCTAssertEqual(idx.tagCounts(live: live).map(\.count), [1, 2])
        XCTAssertEqual(idx.tagged("WORK", live: live).count, 2)
        XCTAssertEqual(idx.blockHits("ship goal", live: live).map(\.block.id), ["b_goal"])
    }

    func testDatesAndWeekStartAndStartOfDay() {
        let today = "2026-11-07" // a Saturday
        func p(_ s: String) -> String? { DateParse.parse(s, today: today, weekStart: 2, cal: cal) }
        XCTAssertEqual(p("today"), today); XCTAssertEqual(p("tomorr"), "2026-11-08"); XCTAssertEqual(p("yest"), "2026-11-06"); XCTAssertNil(p("to"))
        XCTAssertEqual(p("Tomorrow"), "2026-11-08"); XCTAssertEqual(p("yesterday"), "2026-11-06")
        XCTAssertEqual(p("monday"), "2026-11-09"); XCTAssertEqual(p("sat"), "2026-11-14", "a bare weekday is the next one")
        XCTAssertEqual(p("this monday"), "2026-11-02"); XCTAssertEqual(p("next monday"), "2026-11-09")
        XCTAssertEqual(DateParse.parse("next monday", today: today, weekStart: 1, cal: cal), "2026-11-09")
        XCTAssertEqual(p("next week"), "2026-11-09"); XCTAssertEqual(p("next month"), "2026-12-01")
        XCTAssertEqual(p("in 3 days"), "2026-11-10"); XCTAssertEqual(p("in 2 weeks"), "2026-11-21")
        XCTAssertEqual(p("nov 12"), "2026-11-12"); XCTAssertEqual(p("12 November 2027"), "2027-11-12"); XCTAssertEqual(p("jan 3"), "2027-01-03")
        XCTAssertEqual(p("2026-02-28"), "2026-02-28"); XCTAssertNil(p("feb 30")); XCTAssertNil(p("banana")); XCTAssertNil(p("2026-13-01"))
        XCTAssertEqual(Day.startOfWeek(today, weekStart: 1, cal: cal), "2026-11-01")
        XCTAssertEqual(Day.startOfWeek(today, weekStart: 2, cal: cal), "2026-11-02")
        let at3am = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 3))!
        XCTAssertEqual(Day.today(now: at3am, startHour: 4, cal: cal), "2026-11-07", "before the day starts it is still yesterday")
        XCTAssertEqual(Day.today(now: at3am, startHour: 0, cal: cal), "2026-11-08")
        XCTAssertEqual(DateParse.suggestions("", today: today, weekStart: 2, cal: cal), [today, "2026-11-08", "2026-11-09"])
        XCTAssertEqual(DateParse.suggestions("nex", today: today, weekStart: 2, cal: cal).prefix(2), ["2026-11-09", "2026-12-01"], "partly typed words still suggest dates")
        XCTAssertEqual(DateParse.suggestions("fr", today: today, weekStart: 2, cal: cal).first, "2026-11-13")
    }

    func testTaskBucketsAndReminderPlan() {
        let t = { (due: String?, checked: Bool) in IndexedTask(block: "b", text: "x", checked: checked, due: due) }
        let today = "2026-11-07"
        XCTAssertEqual(t(nil, false).bucket(today: today), .inbox)
        XCTAssertEqual(t("2026-11-07T10:00", false).bucket(today: today), .today)
        XCTAssertEqual(t("2026-11-08", false).bucket(today: today), .upcoming)
        XCTAssertEqual(t("2026-11-01", false).bucket(today: today), .overdue)
        XCTAssertEqual(t("2026-11-01", true).bucket(today: today), .completed)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
        let tasks = [IndexedTask(block: "b1", text: "a", checked: false, due: "2026-11-08"),
                     IndexedTask(block: "b2", text: "b", checked: false, due: "2026-11-07T18:30"),
                     IndexedTask(block: "b3", text: "c", checked: false, due: "2026-11-07"), // 9:00 today: past
                     IndexedTask(block: "b4", text: "d", checked: true, due: "2026-11-09"),
                     IndexedTask(block: "b5", text: "e", checked: false, due: nil)]
        let plan = Reminders.plan(tasks, now: now, hour: 9, cal: cal)
        XCTAssertEqual(plan.map(\.id), ["task-b2", "task-b1"], "one per open future task, soonest first")
        XCTAssertEqual(cal.component(.hour, from: plan[1].fire), 9)
    }

    func testSearchOptions() throws {
        var a = DocMeta(id: "d_a", title: "Trip"); a.searchText = "Trip\nPack the red bag. Book train to Vienna."
        var b = DocMeta(id: "d_b", title: "Notes"); b.searchText = "Notes\nred train set and a bag"
        func ids(_ q: String, regex: Bool = false) throws -> [String] { Search.hits(try Search.parse(q, regex: regex), in: [a, b]).map(\.meta.id) }
        XCTAssertEqual(Set(try ids("red bag")), ["d_a", "d_b"])
        XCTAssertEqual(try ids("\"red bag\""), ["d_a"], "phrases match exactly")
        XCTAssertEqual(try ids("train -vienna"), ["d_b"], "a minus excludes")
        XCTAssertEqual(try ids(#"book\s+train"#, regex: true), ["d_a"])
        XCTAssertThrowsError(try Search.parse("(unclosed", regex: true)) { XCTAssertEqual($0 as? Search.QueryError, Search.QueryError(message: "Invalid regular expression")) }
        XCTAssertEqual(try Search.parse("-").include, ["-"])
    }

    func testIndexing10kBlockVaultIsFast() {
        var store: [String: DocFile] = [:], metas: [String: DocMeta] = [:]
        for d in 0..<100 {
            var doc = DocFile.empty(id: "d_\(d)", title: "Doc \(d)")
            doc.content = Node("doc", content: (0..<100).map { i in
                Node("paragraph", attrs: ["id": .string("b_\(d)_\(i)")], content: [.text("Paragraph \(i) with #tag\(i % 7) and some words "), link("x", "d_\((d + 1) % 100)")])
            })
            store[doc.id] = doc; metas[doc.id] = DocMeta(id: doc.id, updatedAt: doc.updatedAt)
        }
        let t0 = Date()
        var idx = VaultIndex()
        idx.refresh(docs: metas, rules: TagRules()) { store[$0] }
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 3, "10,000 blocks index in under 3 s (took \(dt))")
        XCTAssertEqual(idx.blockLocations().count, 10_000)
        print("index-10k-seconds: \(String(format: "%.3f", dt))")
    }
}
