import SwiftUI
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

// MARK: - Aa Format panel (block structure + marks; never page appearance)

struct FormatPanel: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String

    func cmd(_ id: String) -> (active: Bool, enabled: Bool, run: () -> Void) {
        let _ = model.editorTick
        guard let c = model.editors[docId]?.controller, let k = EditorCommands.command(id) else { return (false, false, {}) }
        return (k.isActive(c), k.isEnabled(c) && k.plannedFor == nil, { k.run(c); model.editorTick &+= 1 })
    }

    func chip(_ id: String, _ title: String, font: Font = .system(size: DS.body, weight: .medium), symbol: String? = nil) -> some View {
        let c = cmd(id)
        let k = EditorCommands.command(id)
        let spoken = k.map { $0.title + ($0.shortcut.map { ", \($0)" } ?? "") }
        return ChipButton(title: title, symbol: symbol, font: font, isActive: c.active, isEnabled: c.enabled, label: title.isEmpty ? spoken : nil, action: c.run)
    }

    var body: some View {
        let _ = model.editorTick
        let c = model.editors[docId]?.controller
        let block = c?.currentBlock
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Format")
                PanelSection(title: "Titles") {
                    HStack(spacing: 6) {
                        chip("block.title", "Title", font: .system(size: DS.headline, weight: .bold))
                        chip("block.subtitle", "Subtitle", font: .system(size: DS.body, weight: .semibold))
                        chip("block.heading", "Heading", font: .system(size: DS.body, weight: .semibold))
                    }
                }
                PanelSection(title: "Content") {
                    HStack(spacing: 6) {
                        chip("block.strong", "Strong", font: .system(size: DS.body, weight: .bold))
                        chip("block.body", "Body", font: .system(size: DS.body))
                        chip("block.caption", "Caption", font: .system(size: DS.footnote))
                    }
                    HStack(spacing: 6) {
                        chip("block.quote", "Quote", symbol: "text.quote")
                        chip("block.callout", "Callout", symbol: "lightbulb")
                        chip("block.code", "Code", symbol: "curlybraces")
                    }
                }
                PanelSection(title: "Block Font") {
                    HStack(spacing: 6) {
                        chip("font.document", "Doc", font: .system(size: DS.body))
                        chip("font.system", "Aa", font: .system(size: DS.body, weight: .medium))
                        chip("font.serif", "Ss", font: .system(size: DS.body, weight: .medium, design: .serif))
                        chip("font.mono", "00", font: .system(size: DS.body, weight: .medium, design: .monospaced))
                        chip("font.rounded", "Rr", font: .system(size: DS.body, weight: .medium, design: .rounded))
                    }
                    Text("Overrides the document font for the selected blocks.").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
                }
                if block?.kind == .page && block?.raw?.attrs?["presentation"]?.string != "page" {
                    PanelSection(title: "Card") {
                        HStack(spacing: 6) {
                            ForEach([("compact", "Compact"), ("medium", "Medium"), ("feature", "Feature")], id: \.0) { k, label in
                                ChipButton(title: label, font: .system(size: DS.footnote, weight: .medium), isActive: (block?.raw?.attrs?["size"]?.string ?? "medium") == k, label: "Card size \(label)") { c?.setCardOption("size", k); model.editorTick &+= 1 }
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach([("standard", "Standard", "rectangle.split.2x1"), ("icon", "Icon", "app"), ("gallery", "Gallery", "photo")], id: \.0) { k, label, sym in
                                ChipButton(title: label, symbol: sym, font: .system(size: DS.footnote, weight: .medium), isActive: (block?.raw?.attrs?["preview"]?.string ?? "standard") == k, label: "Card preview \(label)") { c?.setCardOption("preview", k); model.editorTick &+= 1 }
                            }
                        }
                    }
                }
                PanelSection(title: "Groups") {
                    HStack(spacing: 6) {
                        ChipButton(title: "Page", symbol: "doc.text", isActive: block?.kind == .page && block?.raw?.attrs?["presentation"]?.string == "page") { c?.setPagePresentation("page") }
                        ChipButton(title: "Card", symbol: "rectangle.portrait.on.rectangle.portrait", isActive: block?.kind == .page && block?.raw?.attrs?["presentation"]?.string != "page") { c?.setPagePresentation("card") }
                    }
                    Text(block?.kind == .page ? "Switches how this nested page is presented." : "Creates a nested page here and opens it.").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        chip("mark.bold", "", symbol: "bold"); chip("mark.italic", "", symbol: "italic")
                        chip("mark.underline", "", symbol: "underline"); chip("mark.strike", "", symbol: "strikethrough"); chip("mark.code", "", symbol: "chevron.left.forwardslash.chevron.right")
                    }
                    HStack(spacing: 6) {
                        chip("list.task", "", symbol: "checklist"); chip("list.toggle", "", symbol: "chevron.right.square")
                        chip("list.bullet", "", symbol: "list.bullet"); chip("list.ordered", "", symbol: "list.number")
                    }
                    HStack(spacing: 6) {
                        chip("block.outdent", "", symbol: "decrease.indent"); chip("block.indent", "", symbol: "increase.indent")
                        ForEach([("left", "text.alignleft"), ("center", "text.aligncenter"), ("right", "text.alignright"), ("justify", "text.justify")], id: \.0) { a, s in
                            ChipButton(title: "", symbol: s, isActive: (block?.align ?? "left") == a, isEnabled: !(block?.kind.isAttachment ?? true), label: "Align \(a)") { c?.setAlign(a); model.editorTick &+= 1 }
                        }
                    }
                }
                PanelSection(title: "Decorations") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach([("focus", "rectangle.lefthalf.inset.filled"), ("block", "rectangle.fill"), ("gradient", "square.bottomhalf.filled"), ("glass", "rectangle.on.rectangle"), ("glow", "rays"), ("accent", "rectangle.dashed")], id: \.0) { k, sym in
                            ChipButton(title: BlockEffects.all.first { $0.kind == k }?.name ?? k, symbol: sym, isActive: block?.decoration == k, isEnabled: !(block?.kind.isAttachment ?? true), height: 30) { c?.setDecoration(k); model.editorTick &+= 1 }
                                .help(BlockEffects.all.first { $0.kind == k }?.use ?? "")
                        }
                    }
                }
                PanelSection(title: "Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 6), spacing: 8) {
                        ForEach(DraftPalette.blockColors, id: \.1) { name, hex in
                            Button { c?.setBlockColor(block?.blockColor == hex ? nil : hex); model.editorTick &+= 1 } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(block?.blockColor == hex ? t.text : .clear, lineWidth: 2).padding(-3))
                            }.buttonStyle(.plain).help(name).accessibilityLabel("Block color \(name)")
                        }
                    }
                    Button("Remove block color") { c?.setBlockColor(nil); model.editorTick &+= 1 }.buttonStyle(.link).font(.system(size: DS.footnote)).disabled(block?.blockColor == nil)
                }
                Text("Inline color: select text and use the highlighter in the floating bar. ⌘⇧B reapplies the last color.")
                    .font(.system(size: DS.caption)).foregroundStyle(t.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(16)
        }
    }
}

// MARK: - Style panel (page appearance only)

struct ColorSwatchButton: View {
    @Environment(\.tokens) var t
    var hex: String
    var label: String
    @Binding var isPresented: Bool
    var body: some View {
        Button { isPresented.toggle() } label: {
            RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(Color(hex: hex)).frame(width: 34, height: 24)
                .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(t.line, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

let pageColors = ["#fffdf8", "#ffffff", "#f7f3ea", "#f3f6fb", "#f4f8f1", "#fdf2f0", "#20223a", "#1c1d1f", "#2a2420"]
let textColors = ["#252521", "#1d1f22", "#13272e", "#2a1712", "#1f2a1b", "#3b3355", "#ebe8f6", "#f4f1ea", "#e6efe2"]
let solidBackdrops = ["#e9e6df", "#d9dde3", "#cfe3e9", "#e6d9f2", "#f5d9cf", "#dcebd3", "#f6e7b8", "#2b2d3a", "#141518"]
let gradientBackdrops: [(String, String)] = [("#ffd36e", "#ff8a5c"), ("#8fd3e6", "#5b6cf0"), ("#cfe7c4", "#4f8a44"), ("#f7c6d9", "#9d7bd8"), ("#e9e6df", "#b9b2a3"), ("#151a33", "#5b4b9a")]

struct StylePanel: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @State private var backdropOpen = false
    @State private var pageOpen = false
    @State private var textOpen = false
    @State private var savingStyle = false
    @State private var styleName = ""

    var body: some View {
        let doc = model.docs[docId]
        let a = doc?.appearance ?? DocumentAppearance(styleId: "paper")
        let tok = Styles.resolve(a)
        let style = Styles.style(a.styleId)
        let contrast = ColorMath.contrast(tok.textColor, tok.pageColor)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Style")
                StylePreviewCard(tokens: tok, name: style.name + (a.overrides.isEmpty ? "" : " · tailored"), height: 130)
                ChipButton(title: "All Styles", symbol: "square.grid.2x2", height: 30) { model.styleGallery = true }
                HStack(spacing: 8) {
                    ChipButton(title: "Reset", symbol: "arrow.counterclockwise", isEnabled: !a.overrides.isEmpty, height: 30) {
                        model.updateAppearance(docId) { $0.overrides = StyleOverrides() }
                    }
                    ChipButton(title: "Save", symbol: "square.and.arrow.down", height: 30) { styleName = a.overrides.isEmpty ? style.name + " copy" : style.name + " tailored"; savingStyle = true }
                        .help("Save this look as a style").accessibilityLabel("Save as style")
                }
                .alert("Save Style", isPresented: $savingStyle) {
                    TextField("Name", text: $styleName)
                    Button("Save") { model.saveStyle(from: docId, name: styleName) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Saves the backdrop, colors, font and separator so you can use them in other documents.") }
                PanelSection(title: "Color") {
                    row("Backdrop") {
                        Button { backdropOpen.toggle() } label: {
                            BackdropView(backdrop: tok.backdrop).frame(width: 34, height: 24).clipShape(RoundedRectangle(cornerRadius: DS.rControl))
                                .overlay(RoundedRectangle(cornerRadius: DS.rControl).strokeBorder(t.line, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Backdrop")
                        .popover(isPresented: $backdropOpen, arrowEdge: .leading) { BackdropPicker(docId: docId).environment(model).environment(\.tokens, t) }
                    }
                    row("Document Color") {
                        ColorSwatchButton(hex: tok.pageColor, label: "Document color", isPresented: $pageOpen)
                            .popover(isPresented: $pageOpen, arrowEdge: .leading) {
                                SwatchGrid(colors: pageColors, selected: tok.pageColor) { hex in model.updateAppearance(docId) { $0.overrides.pageColor = hex } }
                            }
                    }
                    row("Text Color") {
                        ColorSwatchButton(hex: tok.textColor, label: "Text color", isPresented: $textOpen)
                            .popover(isPresented: $textOpen, arrowEdge: .leading) {
                                SwatchGrid(colors: textColors, selected: tok.textColor) { hex in model.updateAppearance(docId) { $0.overrides.textColor = hex } }
                            }
                    }
                    if contrast < 4.5 {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "Low contrast (%.1f:1). Text may be hard to read.", contrast)).font(.system(size: DS.footnote)).foregroundStyle(t.text)
                                let fix = ColorMath.readable(tok.textColor, on: tok.pageColor)
                                Text(String(format: "Adjusting keeps the hue and darkens or lightens the text to %.1f:1.", fix.ratio)).font(.system(size: DS.caption)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                                Button(String(format: "Adjust text color (%.1f:1 → %.1f:1)", contrast, fix.ratio)) {
                                    model.updateAppearance(docId) { $0.overrides.textColor = fix.hex }
                                }.buttonStyle(.link).font(.system(size: DS.footnote))
                            }
                        }
                    }
                }
                PanelSection(title: "Cover") {
                    row("Cover Image") {
                        if a.cover != nil {
                            Button("Crop…") { model.coverEditorDoc = docId }.controlSize(.small)
                            Button("Remove") { model.updateAppearance(docId) { $0.cover = nil } }.controlSize(.small)
                        }
                        IconButton(symbol: "plus", label: "Add cover image", size: 26) {
                            model.pickImage { id in if let id { model.updateAppearance(docId) { $0.cover = Cover(assetId: id) } } }
                        }
                    }
                }
                PanelSection(title: "Separator Style") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach([("line", "Line", "minus"), ("dotted", "Dots", "ellipsis"), ("tape", "Tape", "bandage"), ("wave", "Wave", "water.waves")], id: \.0) { k, label, sym in
                            ChipButton(title: label, symbol: sym, font: .system(size: DS.footnote, weight: .medium), isActive: tok.separator == k, height: 30) {
                                model.updateAppearance(docId) { $0.overrides.separator = k }
                            }
                        }
                    }
                }
                PanelSection(title: "Font") {
                    HStack(spacing: 6) {
                        ForEach([("system", "Aa", Font.Design.default, "System"), ("serif", "Ss", .serif, "Serif"), ("mono", "00", .monospaced, "Mono"), ("rounded", "Rr", .rounded, "Rounded")], id: \.0) { k, glyph, design, label in
                            ChipButton(title: tok.font == k ? "\(glyph) \(label)" : glyph, font: .system(size: DS.body, weight: .medium, design: design), isActive: tok.font == k, height: 30) {
                                model.updateAppearance(docId) { $0.overrides.font = k }
                            }
                        }
                    }
                }
                PanelSection(title: "Advanced") {
                    Toggle("Tint the app with document styles", isOn: Binding(get: { model.library.settings.useDocStyleForApp }, set: { v in model.setSettings { $0.useDocStyleForApp = v } }))
                        .font(.system(size: DS.body)).toggleStyle(.switch).controlSize(.small)
                    Button(model.library.settings.defaultStyleId == a.styleId ? "Default style for new documents ✓" : "Use “\(style.name)” for new documents") {
                        model.setSettings { $0.defaultStyleId = a.styleId }
                    }.buttonStyle(.link).font(.system(size: DS.footnote)).disabled(model.library.settings.defaultStyleId == a.styleId)
                }
            }.padding(16)
        }
    }

    func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(label).font(.system(size: DS.body)).foregroundStyle(t.text); Spacer(); c() }
    }
}

struct SwatchGrid: View {
    var colors: [String]
    var selected: String
    var pick: (String) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5), spacing: 8) {
            ForEach(colors, id: \.self) { hex in
                Button { pick(hex) } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected.lowercased() == hex ? 2 : 0).padding(-3))
                }.buttonStyle(.plain).accessibilityLabel("Color \(hex)")
            }
        }.padding(14)
    }
}

struct StylePreviewCard: View {
    var tokens: StyleTokens
    var name: String
    var height: CGFloat
    var body: some View {
        let design: Font.Design = tokens.font == "serif" ? .serif : tokens.font == "mono" ? .monospaced : tokens.font == "rounded" ? .rounded : .default
        ZStack {
            BackdropView(backdrop: tokens.backdrop)
            RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(Color(hex: tokens.pageColor))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: DS.caption, weight: .bold, design: design)).foregroundStyle(Color(hex: tokens.textColor)).lineLimit(2).minimumScaleFactor(0.6)
                        ForEach(0..<3, id: \.self) { i in Capsule().fill(Color(hex: tokens.textColor).opacity(0.18)).frame(width: CGFloat(52 - i * 9), height: 2.5) }
                    }.padding(8)
                }
                .frame(width: height * 0.56, height: height * 0.8)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .offset(y: height * 0.08)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .accessibilityElement().accessibilityLabel("Style preview: \(name)")
    }
}

struct BackdropPicker: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @State private var tab = "image"

    var body: some View {
        let tok = model.docs[docId].map { Styles.resolve($0.appearance) } ?? Styles.builtIn[0].tokens
        let b = tok.backdrop
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text("Backdrop").font(.system(size: DS.headline, weight: .semibold))
            DraftSegmented("Backdrop kind", selection: $tab, symbols: [("none", "None", "nosign"), ("solid", "Solid", "square.fill"), ("gradient", "Gradient", "square.bottomhalf.filled"), ("image", "Image", "photo")], stretch: true, iconOnly: true)
            switch tab {
            case "none":
                Button("Use no backdrop") { set(Backdrop(kind: "none")) }
            case "solid":
                grid(solidBackdrops.map { hex in AnyView(Color(hex: hex)) }, selected: solidBackdrops.firstIndex { b.kind == "solid" && b.color == $0 }) { i in set(Backdrop(kind: "solid", color: solidBackdrops[i])) }
            case "gradient":
                if b.kind == "gradient" || b.kind == "field" {
                    GradientEditor(backdrop: b, original: Styles.style(model.docs[docId]?.appearance.styleId ?? "paper").tokens.backdrop, set: set, reset: { model.updateAppearance(docId) { $0.overrides.backdrop = nil } })
                    Divider()
                }
                grid(gradientBackdrops.map { g in AnyView(LinearGradient(colors: [Color(hex: g.0), Color(hex: g.1)], startPoint: .topLeading, endPoint: .bottomTrailing)) },
                     selected: gradientBackdrops.firstIndex { b.kind == "gradient" && b.from == $0.0 }) { i in set(Backdrop(kind: "gradient", from: gradientBackdrops[i].0, to: gradientBackdrops[i].1, angle: 135)) }
            default:
                Text("LIBRARY · \(Scenes.order.count) ORIGINAL SCENES, OFFLINE").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(.secondary)
                grid(Scenes.order.map { id in AnyView(SceneView(sceneId: id)) }, selected: Scenes.order.firstIndex { b.kind == "image" && b.image == $0 }, names: Scenes.order.map { Scenes.all[$0]?.name ?? $0 }) { i in
                    set(Backdrop(kind: "image", image: Scenes.order[i], blur: b.blur, effect: b.effect))
                }
                HStack(spacing: 8) {
                    ChipButton(title: "Shuffle", symbol: "shuffle", height: 30) {
                        let others = Scenes.order.filter { $0 != b.image }
                        set(Backdrop(kind: "image", image: others.randomElement(), blur: b.blur, effect: b.effect))
                    }
                    ChipButton(title: "Upload", symbol: "square.and.arrow.up", height: 30) {
                        model.pickImage { id in if let id { set(Backdrop(kind: "image", image: "asset:" + id, blur: b.blur, effect: b.effect)) } }
                    }
                }
                OnlineImagePicker { id in set(Backdrop(kind: "image", image: "asset:" + id, blur: b.blur, effect: b.effect)) }
            }
            if b.kind != "none" {
                Divider()
                Text("EFFECTS").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(.secondary)
                Toggle("Blur", isOn: Binding(get: { b.blur ?? false }, set: { v in var n = b; n.blur = v; set(n) })).toggleStyle(.switch).controlSize(.small)
                DraftSegmented("Effect", selection: Binding(get: { b.effect ?? "immersive" }, set: { v in var n = b; n.effect = v; set(n) }), options: [("immersive", "Immersive"), ("faded", "Faded")], stretch: true)
            }
        }
        .padding(16) }.frame(width: 290).frame(maxHeight: 640)
        .onAppear { tab = b.kind == "field" ? "gradient" : b.kind }
    }

    func set(_ b: Backdrop) { model.updateAppearance(docId) { $0.overrides.backdrop = b } }

    func colorBinding(_ hex: String, _ write: @escaping (String) -> Void) -> Binding<Color> {
        Binding(get: { Color(hex: hex) }, set: { c in
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            write(ColorMath.hex(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)))
        })
    }

    func grid(_ items: [AnyView], selected: Int?, names: [String]? = nil, pick: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    items[i].frame(height: 46).clipShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(selected == i ? Color.accentColor : Color.black.opacity(0.08), lineWidth: selected == i ? 2.5 : 0.5))
                }.buttonStyle(.plain).accessibilityLabel(names.map { "Backdrop \($0[i])" } ?? "Backdrop option \(i + 1)").help(names?[i] ?? "")
            }
        }
    }
}

/// Stops, direction or focal point of a gradient or field backdrop. Every change goes through
/// `updateAppearance`, which folds a drag into one Undo step.
struct GradientEditor: View {
    @Environment(\.tokens) var t
    var backdrop: Backdrop
    var original: Backdrop
    var set: (Backdrop) -> Void
    var reset: () -> Void

    var body: some View {
        let b = backdrop
        let stops = b.editableStops
        VStack(alignment: .leading, spacing: 10) {
            BackdropView(backdrop: b).frame(height: 54).clipShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(t.line, lineWidth: 1))
                .accessibilityLabel("Gradient preview, \(stops.count) colors")
            DraftSegmented("Gradient type", selection: Binding(get: { b.radial == true ? "radial" : "linear" }, set: { v in edit { $0.radial = v == "radial" ? true : nil } }), options: [("linear", "Linear"), ("radial", "Radial")], stretch: true)
            if b.radial == true {
                slider("Focus across", value: b.focusX ?? 0.5, in: 0...1, step: 0.05, shown: "\(Int((b.focusX ?? 0.5) * 100))%") { v in edit { $0.focusX = v } }
                slider("Focus down", value: b.focusY ?? 0.5, in: 0...1, step: 0.05, shown: "\(Int((b.focusY ?? 0.5) * 100))%") { v in edit { $0.focusY = v } }
            } else {
                slider("Angle", value: b.angle ?? 135, in: 0...360, step: 5, shown: "\(Int(b.angle ?? 135))°") { v in edit { $0.angle = v.rounded() } }
            }
            Text("COLORS").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(stops.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ColorPicker("Color \(i + 1)", selection: colorBinding(s.color) { hex in edit { $0.updateStop(i) { $0.color = hex } } }, supportsOpacity: false)
                            .labelsHidden().accessibilityLabel("Color \(i + 1) of \(stops.count)")
                        Text("Color \(i + 1)").font(.system(size: DS.footnote))
                        Spacer()
                        IconButton(symbol: "chevron.up", label: "Move color \(i + 1) earlier", size: 22) { edit { $0.moveStop(i, by: -1) } }.disabled(i == 0)
                        IconButton(symbol: "chevron.down", label: "Move color \(i + 1) later", size: 22) { edit { $0.moveStop(i, by: 1) } }.disabled(i == stops.count - 1)
                        IconButton(symbol: "minus.circle", label: "Remove color \(i + 1)", size: 22) { edit { $0.removeStop(i) } }.disabled(stops.count <= 2)
                    }
                    slider("Position", value: s.at, in: 0...1, step: 0.01, shown: "\(Int(s.at * 100))%", label: "Color \(i + 1) position") { v in edit { $0.updateStop(i) { $0.at = v } } }
                    slider("Opacity", value: s.opacity ?? 1, in: 0...1, step: 0.05, shown: "\(Int((s.opacity ?? 1) * 100))%", label: "Color \(i + 1) opacity") { v in edit { $0.updateStop(i) { $0.opacity = v } } }
                }
            }
            HStack(spacing: 8) {
                ChipButton(title: "Add Color", symbol: "plus", isEnabled: stops.count < 8, height: 28) { edit { $0.addStop() } }
                ChipButton(title: "Reset", symbol: "arrow.counterclockwise", isEnabled: b != original, height: 28) { reset() }
                    .help("Back to the style's own backdrop")
            }
            if b.stopContrast > 4.5 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Strong contrast across the backdrop (%.1f:1). Toolbar buttons can be hard to see on part of it.", b.stopContrast))
                            .font(.system(size: DS.footnote)).fixedSize(horizontal: false, vertical: true)
                        Button("Use Calmer Colors") { set(b.softened()) }.buttonStyle(.link).font(.system(size: DS.footnote))
                    }
                }
            }
        }
    }

    func edit(_ f: (inout Backdrop) -> Void) { var n = backdrop; n.stops = n.editableStops; n.from = nil; n.to = nil; f(&n); set(n) }

    func slider(_ title: String, value: Double, in r: ClosedRange<Double>, step: Double, shown: String, label: String? = nil, _ write: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: DS.footnote)).frame(width: 78, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { write(($0 / step).rounded() * step) }), in: r).controlSize(.small)
                .accessibilityLabel(label ?? title).accessibilityValue(shown)
            Text(shown).font(.system(size: DS.caption, design: .monospaced)).frame(width: 38, alignment: .trailing)
        }
    }

    func colorBinding(_ hex: String, _ write: @escaping (String) -> Void) -> Binding<Color> {
        Binding(get: { Color(hex: hex) }, set: { c in
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            write(ColorMath.hex(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)))
        })
    }
}

// MARK: - Info panel

struct InfoPanel: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @Binding var tab: String
    @State private var savingTemplate = false
    @State private var templateCategory = "General"

    var body: some View {
        let m = model.library.docs[docId]
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Info")
                .alert("Save as Template", isPresented: $savingTemplate) {
                    TextField("Category", text: $templateCategory)
                    Button("Save") { model.saveAsTemplate(docId, category: templateCategory) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("A copy becomes a template in New → From Template. Later edits to either don't change the other.") }
            DraftSegmented("Info", selection: $tab, options: [("info", "Page Info"), ("actions", "Actions")], stretch: true)
            ScrollView {
                if tab == "info", let m {
                    VStack(alignment: .leading, spacing: 14) {
                        PanelSection(title: "Properties") {
                            prop("calendar", "Created", relative(m.createdAt))
                            prop("clock", "Updated", relative(m.updatedAt))
                            let stats = model.liveStats(docId)
                            prop("text.word.spacing", "Words", "\(stats?.words ?? m.words)")
                            prop("square.stack", "Blocks", "\(stats?.blocks ?? m.blocks)")
                            prop("folder", "Location", model.folderName(m.folderId))
                        }
                        PanelSection(title: "Actions") {
                            action("play.rectangle", "Present") { model.present(docId) }
                            Menu {
                                Button("Unsorted") { model.move(docId, to: nil) }
                                ForEach(model.library.spaceFolders) { f in Button(f.name) { model.move(docId, to: f.id) } }
                            } label: {
                                HStack { Image(systemName: "arrow.turn.up.right").frame(width: 18); Text("Move to…"); Spacer() }
                                    .font(.system(size: DS.body)).padding(.horizontal, 10).frame(height: 30)
                                    .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover)).contentShape(Rectangle())
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).foregroundStyle(t.text)
                            action(m.starred ? "star.slash" : "star", m.starred ? "Unstar Document" : "Star Document") { model.toggleStar(docId) }
                            action("plus.square.on.square", "Duplicate") { model.duplicate(docId) }
                            action("doc.badge.gearshape", model.library.docs[docId]?.template != nil ? "This is a template" : "Save as Template…", enabled: model.library.docs[docId]?.template == nil) { templateCategory = "General"; savingTemplate = true }
                            action("square.and.arrow.up", "Export as Markdown…") { model.exportDoc(docId) }
                            action("clock.arrow.circlepath", "View Backups (\(model.snapshots(docId).count))") { tab = "backups" }
                            action("trash", "Move to Recently Deleted", destructive: true) { model.requestDelete(docId) }
                        }
                    }
                } else if tab == "backups" {
                    BackupsList(docId: docId) { tab = "info" }
                } else {
                    ActionsList(docId: docId)
                }
            }
        }.padding(16)
    }

    func prop(_ icon: String, _ k: String, _ v: String) -> some View {
        HStack { Image(systemName: icon).frame(width: 18).foregroundStyle(t.secondary); Text(k).foregroundStyle(t.secondary); Spacer(); Text(v).foregroundStyle(t.text) }.font(.system(size: DS.body))
    }

    func action(_ icon: String, _ title: String, enabled: Bool = true, destructive: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                .font(.system(size: DS.body)).padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: DS.rControl).fill(destructive ? Color.red.opacity(0.08) : t.hover))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(destructive ? Color.red : t.text).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

struct ActionsList: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String

    /// A row backed by a shared editor command (same enablement and behavior as the menu bar).
    func cmdRow(_ id: String) -> (String, String, String?, Bool, () -> Void) {
        let cmd = EditorCommands.command(id)!
        let c = model.editors[docId]?.controller
        return (cmd.symbol, cmd.title, cmd.shortcut, c.map { cmd.isEnabled($0) } ?? false, { if let c { cmd.run(c) } })
    }

    var body: some View {
        let _ = model.editorTick
        let c = model.editors[docId]?.controller
        let rows: [(String, String, String?, Bool, () -> Void)] = [
            ("doc.text.magnifyingglass", "Find in Page", "⌘F", true, { model.docRailTab = .find; model.railShowsFolders = false; model.findFocusNonce += 1 }),
            ("magnifyingglass", "Quick Open", "⌘O", true, { model.quickOpen = true }),
            ("arrow.uturn.backward", "Undo", "⌘Z", c?.textView.undoManager?.canUndo ?? false, { c?.textView.undoManager?.undo() }),
            ("arrow.uturn.forward", "Redo", "⇧⌘Z", c?.textView.undoManager?.canRedo ?? false, { c?.textView.undoManager?.redo() }),
            cmdRow("block.group"), cmdRow("block.ungroup"), cmdRow("block.duplicate"), cmdRow("block.copyLink"),
            cmdRow("block.moveUp"), cmdRow("block.moveDown"),
            ("doc.on.clipboard", "Copy as Markdown", nil, true, { model.copyMarkdown(docId) }),
            ("printer", "Print", "⌘P", true, { c?.textView.printView(nil) }),
        ]
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                Button(action: r.4) {
                    HStack { Image(systemName: r.0).frame(width: 18); Text(r.1); Spacer(); if let s = r.2 { Text(s).foregroundStyle(t.tertiary) } }
                        .font(.system(size: DS.body)).padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(t.text).disabled(!r.3).opacity(r.3 ? 1 : 0.4)
            }
        }
    }
}

// MARK: - Share panel

struct SharePanel: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @State private var tab = "export"
    @State private var useStyle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DraftSegmented("Share", selection: $tab, options: [("share", "Share"), ("publish", "Publish"), ("export", "Export"), ("transfer", "Transfer")], stretch: true)
            switch tab {
            case "share":
                card(icon: "person.2", title: "Local-only for now", text: "Draft keeps this document on your Mac. Inviting collaborators needs sync, which is planned for v1.x, and real-time collaboration for v2.0.")
                exportRow("doc.on.clipboard", "Copy as Markdown") { model.copyMarkdown(docId) }
            case "publish":
                if let m = model.library.docs[docId] { DocPreview(meta: m, height: 170) }
                card(icon: "globe", title: "Publish to the web", text: "Hosted publishing is planned for v1.x and will be optional and self-hostable. Until then, Export As → Website writes an offline site you can host anywhere.")
                Button("Create Link") {}.disabled(true).frame(maxWidth: .infinity).controlSize(.large)
            case "transfer":
                card(icon: "arrow.left.arrow.right", title: "Send to other apps", text: "Transfer to other writing and task apps is planned for v1.x. Until then, Markdown export works with nearly every app.")
            default:
                VStack(spacing: 6) {
                    exportRow("doc.richtext", "Markdown + assets folder…") { model.exportDoc(docId) }
                    exportRow("doc.on.clipboard", "Copy as Markdown") { model.copyMarkdown(docId) }
                    exportRow("printer", "Print…") { model.editors[docId]?.controller.textView.printView(nil) }
                        .help("Print, or save as PDF from the print dialog")
                    exportRow("plus.square.on.square", "Duplicate") { model.duplicate(docId) }
                    HStack {
                        Text("Use document style").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                        Spacer()
                        Toggle("Use document style", isOn: $useStyle).toggleStyle(.switch).controlSize(.small).labelsHidden()
                            .accessibilityLabel("Use document style in PDF, HTML and image export")
                    }.padding(.horizontal, DS.s3).padding(.top, DS.s1)
                    exportRow("doc", "PDF…") { model.exportStyled(docId, as: "pdf", useStyle: useStyle) }
                    exportRow("globe", "Web page (HTML)…") { model.exportStyled(docId, as: "html", useStyle: useStyle) }
                    exportRow("photo", "Image (PNG)…") { model.exportStyled(docId, as: "png", useStyle: useStyle) }
                    exportRow("square.grid.3x1.below.line.grid.1x2", "Website of all documents…") { model.exportSite(useStyle: useStyle) }
                    exportRow("doc.text", "Word — later", enabled: false) {}
                    exportRow("envelope", "E-mail — v1.x", enabled: false) {}
                }
                Text("Exports include a lossless draft-export.json next to the Markdown.").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
            }
        }.padding(16)
    }

    func card(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
            Text(text).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: DS.rCard).fill(t.hover))
    }

    func exportRow(_ icon: String, _ title: String, enabled: Bool = true, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                .font(.system(size: DS.body)).padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover)).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(t.text).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

/// Automatic local backups of one document (taken at most every 10 minutes while editing).
struct BackupsList: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    var back: () -> Void
    var body: some View {
        let _ = model.editorTick
        let snaps = model.snapshots(docId)
        VStack(alignment: .leading, spacing: 8) {
            Button { back() } label: { Label("Page Info", systemImage: "chevron.left") }.buttonStyle(.link).font(.system(size: DS.footnote))
            Text("Backups").font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
            Text("Draft keeps up to \(Vault.snapshotsKept) automatic backups per document on this Mac, one every 10 minutes while you edit.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            if snaps.isEmpty { Text("No backups yet. The first one is made the next time this document is saved.").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary) }
            ForEach(snaps) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Date(timeIntervalSince1970: s.savedAt / 1000).formatted(date: .abbreviated, time: .shortened)).font(.system(size: DS.body)).foregroundStyle(t.text)
                        Text(relative(s.savedAt)).font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
                    }
                    Spacer()
                    Button("Restore") {
                        model.confirm = ConfirmRequest(title: "Restore this backup?", detail: "The document returns to how it was \(relative(s.savedAt)). The current version is backed up first, so you can switch back.",
                                                       confirmLabel: "Restore", destructive: false) { model.restoreSnapshot(docId, s) }
                    }.controlSize(.small)
                }.padding(8).background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
            }
        }
    }
}

/// Online image search for backdrops: only when turned on in Settings, and it asks before the
/// first request of each session.
struct OnlineImagePicker: View {
    @Environment(AppModel.self) var model
    var choose: (String) -> Void
    @State private var query = ""
    @State private var results: [WebImage] = []
    @State private var status = ""
    @State private var confirming = false
    static var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("ONLINE (OPENVERSE)").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(.secondary)
            if !model.settings.onlineImageSearch {
                Text("Off. Turn on in Settings → Advanced → Online to search openly licensed images.").font(.system(size: DS.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { model.openView(ViewRef(kind: "settings", section: "advanced")) }.controlSize(.small)
            } else {
                HStack {
                    TextField("Search images", text: $query).textFieldStyle(.roundedBorder).onSubmit(search).accessibilityLabel("Search online images")
                    Button("Search", action: search).controlSize(.small).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !status.isEmpty { Text(status).font(.system(size: DS.caption)).foregroundStyle(.secondary) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(results) { r in
                        Button { pick(r) } label: {
                            AsyncImage(url: URL(string: r.thumbnail ?? r.url)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.gray.opacity(0.15) }
                                .frame(height: 46).clipShape(RoundedRectangle(cornerRadius: DS.rControl))
                        }.buttonStyle(.plain).help([r.title, r.creator.map { "by " + $0 }, r.license.map { "CC " + $0.uppercased() }].compactMap { $0 }.joined(separator: " · "))
                        .accessibilityLabel("Image \(r.title ?? "")")
                    }
                }
            }
        }
        .alert("Search online?", isPresented: $confirming) {
            Button("Search Openverse") { Self.confirmed = true; search() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Draft will send “\(query)” to api.openverse.org and load image previews from it. Nothing else is sent.") }
    }

    func search() {
        guard Self.confirmed else { confirming = true; return }
        status = "Searching…"
        model.online.searchImages(query, enabled: model.settings.onlineImageSearch) { r in
            switch r {
            case .success(let imgs): results = imgs; status = imgs.isEmpty ? "No images found." : "Openly licensed images from Openverse."
            case .failure(let e): results = []; status = e.localizedDescription
            }
        }
    }

    func pick(_ r: WebImage) {
        status = "Downloading…"
        model.online.download(r.url, enabled: model.settings.onlineImageSearch) { d in
            guard let d, let img = NSImage(data: d), let png = img.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) }),
                  let id = model.storeImage(data: png, ext: "jpg") else { status = "Could not download that image."; return }
            status = ""
            choose(id)
        }
    }
}
