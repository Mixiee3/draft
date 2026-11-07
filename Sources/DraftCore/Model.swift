import Foundation

public let librarySchemaVersion = 1
public let docSchemaVersion = 1

public struct Space: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
}

public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var color: String?
    public var order: Double
    public var createdAt: Double
    public init(id: String = newId("f_"), name: String, parentId: String? = nil, color: String? = nil, order: Double = 0, createdAt: Double = nowMs()) {
        self.id = id; self.name = name; self.parentId = parentId; self.color = color; self.order = order; self.createdAt = createdAt
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
    }
}

public struct Library: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var space: Space
    public var folders: [Folder]
    public var docs: [String: DocMeta]
    public var settings: Settings
    public var tabs: [Tab]
    public var activeTabId: String?
    public var expandedFolders: [String]
    /// Unknown top-level fields, preserved verbatim.
    public var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, space, folders, docs, settings, tabs, activeTabId, expandedFolders
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
        extra = try d.unknownFields(known: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to e: Encoder) throws {
        try e.encodeUnknown(extra)
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(space, forKey: .space)
        try c.encode(folders, forKey: .folders)
        try c.encode(docs, forKey: .docs)
        try c.encode(settings, forKey: .settings)
        try c.encode(tabs, forKey: .tabs)
        try c.encodeIfPresent(activeTabId, forKey: .activeTabId)
        try c.encode(expandedFolders, forKey: .expandedFolders)
    }

    public static func empty() -> Library {
        let home = Tab(view: .all)
        return Library(schemaVersion: librarySchemaVersion, space: Space(id: newId("s_"), name: "My Space"), folders: [], docs: [:], settings: Settings(), tabs: [home], activeTabId: home.id, expandedFolders: [])
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
    /// 0…1 focal point. The crop UI lands later; the data is stored now.
    public var focalY: Double
    public init(assetId: String, focalY: Double = 0.5) { self.assetId = assetId; self.focalY = focalY }
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
