import Foundation

public let librarySchemaVersion = 2
public let docSchemaVersion = 1

public struct Space: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Tabs of this Space while another Space is active.
    public var tabs: [Tab]?
    public var activeTabId: String?
    /// This Space's own theme, daily-note and tag settings while another Space is active.
    public var settings: SpaceSettings?
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// The settings each Space keeps for itself; everything else in `Settings` is app-wide.
public struct SpaceSettings: Codable, Hashable, Sendable {
    public var theme: String?
    public var accent: String?
    public var showDailyNotes: Bool?
    public var dailyTemplateId: String?
    public var dayStartHour: Int?
    public var tagRules: TagRules?
    public var tagColors: [String: String]?
    public init() {}
}

extension Settings {
    public var spaceScoped: SpaceSettings {
        var s = SpaceSettings()
        s.theme = theme; s.accent = accent; s.showDailyNotes = showDailyNotes; s.dailyTemplateId = dailyTemplateId
        s.dayStartHour = dayStartHour; s.tagRules = tagRules; s.tagColors = tagColors
        return s
    }

    public mutating func apply(_ s: SpaceSettings) {
        if let v = s.theme { theme = v }
        if let v = s.accent { accent = v }
        if let v = s.showDailyNotes { showDailyNotes = v }
        dailyTemplateId = s.dailyTemplateId
        if let v = s.dayStartHour { dayStartHour = v }
        if let v = s.tagRules { tagRules = v }
        if let v = s.tagColors { tagColors = v }
    }
}

public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var color: String?
    public var order: Double
    public var createdAt: Double
    public var spaceId: String?
    public init(id: String = newId("f_"), name: String, parentId: String? = nil, color: String? = nil, order: Double = 0, createdAt: Double = nowMs(), spaceId: String? = nil) {
        self.id = id; self.name = name; self.parentId = parentId; self.color = color; self.order = order; self.createdAt = createdAt; self.spaceId = spaceId
    }
}

/// Index entry for a document. Derived fields (excerpt, searchText, counts, tint) are rebuildable
/// from the document file and are never the source of truth.
public struct DocMeta: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var folderId: String?
    /// For nested pages: the document that contains the page card.
    public var parentDocId: String?
    public var createdAt: Double
    public var updatedAt: Double
    public var viewedAt: Double
    public var starred: Bool
    public var styleId: String
    public var excerpt: String
    public var searchText: String
    public var words: Int
    public var blocks: Int
    public var tint: String
    /// Set while the document is in Recently Deleted (its file stays on disk until purged).
    public var deletedAt: Double?
    /// Set on daily notes: the day (`yyyy-MM-dd`) the note belongs to.
    public var dailyDate: String?
    /// The Space the document belongs to (schema 2).
    public var spaceId: String?
    /// Saved as a template: hidden from the library, offered by New → From Template.
    public var template: String?

    public init(id: String, title: String = "", folderId: String? = nil, parentDocId: String? = nil, createdAt: Double = nowMs(), updatedAt: Double = nowMs(), viewedAt: Double = nowMs(), starred: Bool = false, styleId: String = "paper", excerpt: String = "", searchText: String = "", words: Int = 0, blocks: Int = 0, tint: String = "#d9d4ca") {
        self.id = id; self.title = title; self.folderId = folderId; self.parentDocId = parentDocId
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.viewedAt = viewedAt; self.starred = starred
        self.styleId = styleId; self.excerpt = excerpt; self.searchText = searchText; self.words = words; self.blocks = blocks; self.tint = tint
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        parentDocId = try c.decodeIfPresent(String.self, forKey: .parentDocId)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? nowMs()
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? createdAt
        viewedAt = try c.decodeIfPresent(Double.self, forKey: .viewedAt) ?? updatedAt
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        styleId = try c.decodeIfPresent(String.self, forKey: .styleId) ?? "paper"
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        searchText = try c.decodeIfPresent(String.self, forKey: .searchText) ?? ""
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
        blocks = try c.decodeIfPresent(Int.self, forKey: .blocks) ?? 0
        tint = try c.decodeIfPresent(String.self, forKey: .tint) ?? "#d9d4ca"
        deletedAt = try c.decodeIfPresent(Double.self, forKey: .deletedAt)
        dailyDate = try c.decodeIfPresent(String.self, forKey: .dailyDate)
        spaceId = try c.decodeIfPresent(String.self, forKey: .spaceId)
        template = try c.decodeIfPresent(String.self, forKey: .template)
    }
}

public enum LibraryLayout: String, Codable, CaseIterable, Sendable { case gallery, grid, list }
public enum SortKey: String, Codable, CaseIterable, Sendable { case name, updatedAt, createdAt, viewedAt }

public struct SortSpec: Codable, Hashable, Sendable {
    public var key: SortKey
    public var dir: String // "asc" | "desc"
    public init(key: SortKey, dir: String) { self.key = key; self.dir = dir }
}

public struct ViewRef: Codable, Hashable, Sendable {
    public var kind: String // all | unsorted | starred | shared | folder | doc | settings
    public var folderId: String?
    public var docId: String?
    public var section: String?
    public init(kind: String, folderId: String? = nil, docId: String? = nil, section: String? = nil) {
        self.kind = kind; self.folderId = folderId; self.docId = docId; self.section = section
    }
    public static let all = ViewRef(kind: "all")
    public static func doc(_ id: String) -> ViewRef { ViewRef(kind: "doc", docId: id) }
    public static func folder(_ id: String) -> ViewRef { ViewRef(kind: "folder", folderId: id) }
}

public struct Tab: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var view: ViewRef
    /// Where the user was in a document tab (restored after relaunch).
    public var scrollY: Double?
    public var selStart: Int?
    public var selLength: Int?
    public init(id: String = newId("t_"), view: ViewRef) { self.id = id; self.view = view }
}

public struct Settings: Codable, Hashable, Sendable {
    public var theme: String = "system" // system | light | dark
    public var accent: String = "#5b6cf0"
    public var useDocStyleForApp: Bool = true
    public var reduceMotion: Bool = false
    public var completedTasks: String = "strike" // strike | dim | none
    public var libraryView: LibraryLayout = .gallery
    public var sort = SortSpec(key: .updatedAt, dir: "desc")
    public var railCollapsed: Bool = false
    public var defaultStyleId: String = "paper"
    /// 0 = the system calendar's, 1 = Sunday, 2 = Monday.
    public var weekStart: Int = 0
    /// Hour (0–23) at which a new day starts for Today and daily notes.
    public var dayStartHour: Int = 0
    public var showDailyNotes: Bool = true
    public var dailyTemplateId: String?
    public var tagColors: [String: String] = [:]
    public var tagRules = TagRules()
    public var reminders: Bool = false
    public var reminderHour: Int = 9
    public var calendarEvents: Bool = false
    /// "chip" or "text": how date mentions look in documents.
    public var dateStyle: String = "chip"
    public var calendarFilter: String = "all" // all | tasks | notes
    public var calendarShowCompleted: Bool = false
    /// Network features; both off unless the user turns them on.
    public var onlineImageSearch: Bool = false
    public var linkPreviews: Bool = false
    /// The local model the Assistant uses (an id from the model catalog); nil until one is chosen.
    public var assistantModel: String?
    /// Cloud inference is optional; existing vaults continue to use the local model.
    public var assistantProvider: AssistantProvider = .local
    public var openAIModel: String = "gpt-6.1-sol"
    /// The Assistant as a panel pinned to the right of the window (true) or a floating window.
    public var assistantPinned: Bool = true
    /// Documents in the Paper style turn dark with the app (display only; exports keep the page).
    public var paperFollowsAppearance: Bool = true
    /// The welcome screen and tour version the user has seen (0 = never).
    public var onboardingSeen: Int = 0
    /// Sidebar sections the user hid, and the order of the movable ones.
    public var sidebarHidden: [String] = []
    public var sidebarOrder: [String] = Settings.sidebarSections
    public static let sidebarSections = ["starred", "folders", "tags"]

    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Settings()
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? def.theme
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? def.accent
        useDocStyleForApp = try c.decodeIfPresent(Bool.self, forKey: .useDocStyleForApp) ?? def.useDocStyleForApp
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? def.reduceMotion
        completedTasks = try c.decodeIfPresent(String.self, forKey: .completedTasks) ?? def.completedTasks
        libraryView = (try? c.decodeIfPresent(LibraryLayout.self, forKey: .libraryView)) ?? def.libraryView
        sort = (try? c.decodeIfPresent(SortSpec.self, forKey: .sort)) ?? def.sort
        railCollapsed = try c.decodeIfPresent(Bool.self, forKey: .railCollapsed) ?? def.railCollapsed
        defaultStyleId = try c.decodeIfPresent(String.self, forKey: .defaultStyleId) ?? def.defaultStyleId
        weekStart = try c.decodeIfPresent(Int.self, forKey: .weekStart) ?? def.weekStart
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? def.dayStartHour
        showDailyNotes = try c.decodeIfPresent(Bool.self, forKey: .showDailyNotes) ?? def.showDailyNotes
        dailyTemplateId = try c.decodeIfPresent(String.self, forKey: .dailyTemplateId)
        tagColors = (try? c.decodeIfPresent([String: String].self, forKey: .tagColors)) ?? [:]
        tagRules = (try? c.decodeIfPresent(TagRules.self, forKey: .tagRules)) ?? def.tagRules
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? def.reminders
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? def.reminderHour
        calendarEvents = try c.decodeIfPresent(Bool.self, forKey: .calendarEvents) ?? def.calendarEvents
        dateStyle = try c.decodeIfPresent(String.self, forKey: .dateStyle) ?? def.dateStyle
        calendarFilter = try c.decodeIfPresent(String.self, forKey: .calendarFilter) ?? def.calendarFilter
        calendarShowCompleted = try c.decodeIfPresent(Bool.self, forKey: .calendarShowCompleted) ?? def.calendarShowCompleted
        onlineImageSearch = try c.decodeIfPresent(Bool.self, forKey: .onlineImageSearch) ?? def.onlineImageSearch
        linkPreviews = try c.decodeIfPresent(Bool.self, forKey: .linkPreviews) ?? def.linkPreviews
        assistantModel = try c.decodeIfPresent(String.self, forKey: .assistantModel)
        assistantProvider = (try? c.decodeIfPresent(AssistantProvider.self, forKey: .assistantProvider)) ?? .local
        openAIModel = (try? c.decodeIfPresent(String.self, forKey: .openAIModel)) ?? "gpt-6.1-sol"
        assistantPinned = try c.decodeIfPresent(Bool.self, forKey: .assistantPinned) ?? def.assistantPinned
        paperFollowsAppearance = try c.decodeIfPresent(Bool.self, forKey: .paperFollowsAppearance) ?? def.paperFollowsAppearance
        onboardingSeen = try c.decodeIfPresent(Int.self, forKey: .onboardingSeen) ?? def.onboardingSeen
        sidebarHidden = try c.decodeIfPresent([String].self, forKey: .sidebarHidden) ?? def.sidebarHidden
        let order = try c.decodeIfPresent([String].self, forKey: .sidebarOrder) ?? def.sidebarOrder
        // Keep every known section exactly once, whatever an older or edited file says.
        sidebarOrder = order.filter(Settings.sidebarSections.contains).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            + Settings.sidebarSections.filter { !order.contains($0) }
    }
}

public struct Library: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    /// The active Space (also listed in `spaces`).
    public var space: Space
    public var spaces: [Space] = []
    public var folders: [Folder]
    public var docs: [String: DocMeta]
    public var settings: Settings
    public var tabs: [Tab]
    public var activeTabId: String?
    public var expandedFolders: [String]
    public var userStyles: [UserStyle] = []
    /// Unknown top-level fields, preserved verbatim.
    public var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, space, spaces, folders, docs, settings, tabs, activeTabId, expandedFolders, userStyles
    }

    public init(schemaVersion: Int, space: Space, folders: [Folder], docs: [String: DocMeta], settings: Settings, tabs: [Tab], activeTabId: String?, expandedFolders: [String]) {
        self.schemaVersion = schemaVersion; self.space = space; self.folders = folders; self.docs = docs
        self.settings = settings; self.tabs = tabs; self.activeTabId = activeTabId; self.expandedFolders = expandedFolders
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        space = try c.decode(Space.self, forKey: .space)
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        docs = try c.decodeIfPresent([String: DocMeta].self, forKey: .docs) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        tabs = try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        activeTabId = try c.decodeIfPresent(String.self, forKey: .activeTabId)
        expandedFolders = try c.decodeIfPresent([String].self, forKey: .expandedFolders) ?? []
        userStyles = (try? c.decodeIfPresent([UserStyle].self, forKey: .userStyles)) ?? []
        spaces = try c.decodeIfPresent([Space].self, forKey: .spaces) ?? [space]
        if !spaces.contains(where: { $0.id == space.id }) { spaces.insert(space, at: 0) }
        extra = try d.unknownFields(known: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to e: Encoder) throws {
        try e.encodeUnknown(extra)
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(space, forKey: .space)
        try c.encode(spaces, forKey: .spaces)
        try c.encode(folders, forKey: .folders)
        try c.encode(docs, forKey: .docs)
        try c.encode(settings, forKey: .settings)
        try c.encode(tabs, forKey: .tabs)
        try c.encodeIfPresent(activeTabId, forKey: .activeTabId)
        try c.encode(expandedFolders, forKey: .expandedFolders)
        if !userStyles.isEmpty { try c.encode(userStyles, forKey: .userStyles) }
    }

    public static func empty() -> Library {
        let home = Tab(view: .all)
        let s = Space(id: newId("s_"), name: "My Space")
        var lib = Library(schemaVersion: librarySchemaVersion, space: s, folders: [], docs: [:], settings: Settings(), tabs: [home], activeTabId: home.id, expandedFolders: [])
        lib.spaces = [s]
        return lib
    }
}

/* ---------------- Document appearance ---------------- */

public struct Backdrop: Codable, Hashable, Sendable {
    public var kind: String // none | solid | gradient | image
    public var color: String?
    public var from: String?
    public var to: String?
    public var angle: Double?
    /// Built-in scene id (original Draft artwork) or "asset:<file>".
    public var image: String?
    public var blur: Bool?
    public var effect: String? // immersive | faded
    public init(kind: String, color: String? = nil, from: String? = nil, to: String? = nil, angle: Double? = nil, image: String? = nil, blur: Bool? = nil, effect: String? = nil) {
        self.kind = kind; self.color = color; self.from = from; self.to = to; self.angle = angle; self.image = image; self.blur = blur; self.effect = effect
    }
}

/// Document-level visual tokens. Never stored inside content.
public struct StyleTokens: Codable, Hashable, Sendable {
    public var backdrop: Backdrop
    public var pageColor: String
    public var textColor: String
    public var accent: String
    public var font: String // system | serif | mono | rounded
    public var separator: String // line | dotted | tape | wave
    public var shellTint: String
}

/// Sparse overrides on top of a style. Every field optional.
public struct StyleOverrides: Codable, Hashable, Sendable {
    public var backdrop: Backdrop?
    public var pageColor: String?
    public var textColor: String?
    public var accent: String?
    public var font: String?
    public var separator: String?
    public var shellTint: String?
    public init() {}
    public var isEmpty: Bool { self == StyleOverrides() }
}

public struct Cover: Codable, Hashable, Sendable {
    public var assetId: String
    /// 0…1 vertical focal point, used when there is no explicit crop.
    public var focalY: Double
    /// Visible part of the image, normalized to 0…1 of its width/height.
    public var crop: CropRect?
    /// "original", "16:9", "2:1", "3:1", "4:3" or "free".
    public var ratio: String?
    public init(assetId: String, focalY: Double = 0.5, crop: CropRect? = nil, ratio: String? = nil) {
        self.assetId = assetId; self.focalY = focalY; self.crop = crop; self.ratio = ratio
    }
}

public struct CropRect: Codable, Hashable, Sendable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// Cover crop geometry. Image aspect = pixel width / height; ratios are width / height.
public enum CoverCrop {
    public static let ratios: [(id: String, label: String, value: Double?)] = [
        ("original", "Original", nil), ("16:9", "16:9", 16.0 / 9), ("2:1", "2:1", 2), ("3:1", "3:1", 3), ("4:3", "4:3", 4.0 / 3), ("free", "Free", nil),
    ]
    public static let defaultRatio = 3.0

    public static func value(of id: String?) -> Double? { ratios.first { $0.id == id }?.value }

    /// Largest crop of the given ratio that fits the image, centered on (cx, cy) as far as possible.
    public static func fitted(ratio: Double?, imageAspect a: Double, cx: Double = 0.5, cy: Double = 0.5) -> CropRect {
        guard let r = ratio, a > 0 else { return CropRect(x: 0, y: 0, w: 1, h: 1) }
        var w = 1.0, h = a / r
        if h > 1 { h = 1; w = r / a }
        return clamped(CropRect(x: cx - w / 2, y: cy - h / 2, w: w, h: h))
    }

    /// Keep the rect inside the image (and at least 5% in each direction).
    public static func clamped(_ c: CropRect) -> CropRect {
        let w = min(1, max(0.05, c.w)), h = min(1, max(0.05, c.h))
        return CropRect(x: min(max(0, c.x), 1 - w), y: min(max(0, c.y), 1 - h), w: w, h: h)
    }

    /// The crop actually shown: the stored one, or the default 3:1 band around the focal point.
    public static func effective(_ cover: Cover, imageAspect a: Double) -> CropRect {
        cover.crop.map(clamped) ?? fitted(ratio: defaultRatio, imageAspect: a, cy: cover.focalY)
    }

    /// Pixel aspect (width / height) of a crop of an image with aspect `a`.
    public static func aspect(of c: CropRect, imageAspect a: Double) -> Double { (c.w * a) / max(0.0001, c.h) }
}

public struct DocumentAppearance: Codable, Hashable, Sendable {
    public var styleId: String
    public var overrides: StyleOverrides
    public var cover: Cover?
    public init(styleId: String, overrides: StyleOverrides = StyleOverrides(), cover: Cover? = nil) {
        self.styleId = styleId; self.overrides = overrides; self.cover = cover
    }
}

public struct DocFile: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var title: String
    public var content: Node // type "doc"
    public var appearance: DocumentAppearance
    public var createdAt: Double
    public var updatedAt: Double
    public var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, title, content, appearance, createdAt, updatedAt }

    public init(schemaVersion: Int = docSchemaVersion, id: String, title: String, content: Node, appearance: DocumentAppearance, createdAt: Double, updatedAt: Double) {
        self.schemaVersion = schemaVersion; self.id = id; self.title = title; self.content = content
        self.appearance = appearance; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decode(Node.self, forKey: .content)
        appearance = try c.decode(DocumentAppearance.self, forKey: .appearance)
        createdAt = try c.decode(Double.self, forKey: .createdAt)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
        extra = try d.unknownFields(known: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to e: Encoder) throws {
        try e.encodeUnknown(extra)
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public static func empty(id: String, title: String = "", styleId: String = "paper") -> DocFile {
        let now = nowMs()
        return DocFile(id: id, title: title, content: Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])]), appearance: DocumentAppearance(styleId: styleId), createdAt: now, updatedAt: now)
    }
}
