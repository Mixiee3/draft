import SwiftUI
import AppKit
import DraftEditor

/// Help → Keyboard Shortcuts (⌘/): the menu bar's shortcuts plus the editor's typing triggers.
struct ShortcutsSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var query = ""
    @FocusState private var focused: Bool

    static let typing: [MenuShortcut] = [
        MenuShortcut(menu: "Typing", title: "Insert a block (on an empty line)", keys: "/"),
        MenuShortcut(menu: "Typing", title: "Link to a document", keys: "[["),
        MenuShortcut(menu: "Typing", title: "Tag", keys: "#"),
        MenuShortcut(menu: "Typing", title: "Heading 1–4", keys: "# … ####"),
        MenuShortcut(menu: "Typing", title: "Checklist", keys: "[]"),
        MenuShortcut(menu: "Typing", title: "Focus the formatting bar", keys: "⌥F10"),
        MenuShortcut(menu: "Typing", title: "Select the block / leave a picker", keys: "⎋"),
    ]

    var all: [MenuShortcut] { (NSApp.mainMenu.map { menuShortcuts($0) } ?? []) + Self.typing }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = all.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.menu.lowercased().contains(q) || $0.keys.lowercased().contains(q) }
        let groups = Dictionary(grouping: items, by: \.menu)
        let order = all.map(\.menu).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { model.shortcutsSheet = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard").foregroundStyle(t.secondary).accessibilityHidden(true)
                    TextField("Search shortcuts", text: $query).textFieldStyle(.plain).font(.system(size: DS.headline)).focused($focused)
                        .onExitCommand { model.shortcutsSheet = false }
                        .accessibilityLabel("Search keyboard shortcuts")
                    Button { model.shortcutsSheet = false } label: { Image(systemName: "xmark").font(.system(size: DS.footnote, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(t.secondary).accessibilityLabel("Close")
                }.padding(14)
                Divider().opacity(0.5)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.s3) {
                        ForEach(order.filter { groups[$0] != nil }, id: \.self) { menu in
                            Text(menu.uppercased()).font(.system(size: DS.micro + 1, weight: .semibold)).tracking(0.6).foregroundStyle(t.secondary).padding(.horizontal, DS.s3 + 2)
                                .accessibilityAddTraits(.isHeader)
                            ShortcutList(items: groups[menu]!.map { ($0.keys, $0.title) })
                                .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover.opacity(0.5)))
                        }
                        if items.isEmpty { Text("No shortcut matches “\(query)”.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s4) }
                    }.padding(DS.s3)
                }.frame(maxHeight: 480)
            }
            .frame(width: 520)
            .surface(.overlay)
            .padding(.top, 70)
        }
        .onAppear { focused = true }
        .accessibilityAddTraits(.isModal)
    }
}
