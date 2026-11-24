import SwiftUI
import DraftCore
import DraftEditor

/// The Format panel's Text Effect section: the text's own color and the effect's colors and
/// strength, edited separately. Live controls fold a drag into one Undo step; colors that fill the
/// letters are kept readable (4.5:1) and the panel says when one was adjusted.
struct TextEffectEditor: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let c: EditorController

    var body: some View {
        let _ = model.editorTick
        let hasText = c.textView.selectedRange().length > 0
        let spec = c.value(of: .draftEffect).flatMap(EffectSpec.init)
        let page = c.theme.pageColor
        PanelSection(title: "Text Effect") {
            if !hasText {
                Text("Select text to give it an effect.").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            } else {
                row("Effect") {
                    Picker("Effect", selection: Binding(get: { spec?.kind ?? "none" }, set: { k in apply(k == "none" ? nil : (k == "spectrum" ? EffectSpec("spectrum") : EffectSpec(kind: k)), live: false) })) {
                        Text("None").tag("none")
                        ForEach(TextEffects.all, id: \.kind) { Text($0.name).tag($0.kind) }
                    }.labelsHidden().frame(maxWidth: 150)
                }
                if c.theme.plainEffects, spec != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Increase Contrast is on in System Settings, so effects show as one still, readable color.", systemImage: "circle.lefthalf.filled")
                            .font(.system(size: DS.caption)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true)
                        Button("Show Full Effects") { model.setSettings { $0.simplifyEffectsWithIncreaseContrast = false } }
                            .buttonStyle(.link).font(.system(size: DS.footnote))
                            .accessibilityHint("Turns off Settings › Appearance › Simplify text effects with Increase Contrast")
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
                }
                if let s = spec { presets(s, page: page) }
                if spec?.kind != "spectrum" { textColorRow(spec) }
                if let s = spec { controls(s, page: page) }
                if spec?.kind == "spectrum" { textColorRow(spec) }
                if let s = spec, s.adjustedForContrast(page: page) {
                    Label("A color was darkened or lightened so the text stays readable (4.5:1).", systemImage: "eye")
                        .font(.system(size: DS.caption)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let s = spec, s != EffectSpec(kind: s.kind), s.spectrum == nil {
                    Button("Reset effect colors") { apply(EffectSpec(kind: s.kind), live: false) }.buttonStyle(.link).font(.system(size: DS.footnote))
                }
            }
        }
    }

    @ViewBuilder func textColorRow(_ spec: EffectSpec?) -> some View {
        let current = c.value(of: .draftTextColor)
        let fillsLetters = ["accent", "gradient", "spectrum"].contains(spec?.kind ?? "")
        row(fillsLetters ? "Plain color (when simplified)" : "Text color") {
            if current != nil { Button("Automatic") { c.setTextColor(nil); model.editorTick &+= 1 }.buttonStyle(.link).font(.system(size: DS.caption)) }
            ColorPicker("Text color", selection: colorBinding(current ?? c.theme.textColor) { hex in c.setTextColor(ColorMath.readable(hex, on: c.theme.pageColor).hex, coalescing: true); model.editorTick &+= 1 }, supportsOpacity: false)
                .labelsHidden().accessibilityLabel("Text color")
        }
        .help(fillsLetters ? "Used when the effect can't be shown, for example with Increase Contrast" : "The letters' color; the effect keeps its own color")
    }

    @ViewBuilder func controls(_ s: EffectSpec, page: String) -> some View {
        let names = ["glow": "Glow color", "shadow": "Shadow color", "outline": "Outline color", "lift": "Offset color", "emboss": "Emboss color", "accent": "Accent color"]
        if let name = names[s.kind] {
            row(name) {
                if s.color != nil { Button("Automatic") { var n = s; n.color = nil; apply(n, live: false) }.buttonStyle(.link).font(.system(size: DS.caption)) }
                ColorPicker(name, selection: colorBinding(s.color ?? defaultColor(s.kind)) { hex in var n = s; n.color = hex; apply(n, live: true) }, supportsOpacity: false)
                    .labelsHidden().accessibilityLabel(name)
            }
        }
        if ["glow", "shadow", "outline", "lift", "emboss"].contains(s.kind) {
            slider("Strength", value: s.intensity ?? 0.6, range: 0...1, shown: "\(Int((s.intensity ?? 0.6) * 100))%") { v in var n = s; n.intensity = (v * 20).rounded() / 20; apply(n, live: true) }
        }
        if s.kind == "gradient" {
            let stops = s.stops ?? EffectSpec(kind: "gradient").fillColors(accent: c.theme.accent, text: c.theme.textColor, page: page)
            ForEach(Array(stops.enumerated()), id: \.offset) { i, hex in
                row("Color \(i + 1)") {
                    if stops.count > 2 { IconButton(symbol: "minus.circle", label: "Remove color \(i + 1)", size: 22) { var n = s; var st = stops; st.remove(at: i); n.stops = st; apply(n, live: false) } }
                    ColorPicker("Color \(i + 1)", selection: colorBinding(hex) { v in var n = s; var st = stops; st[i] = v; n.stops = st; apply(n, live: true) }, supportsOpacity: false)
                        .labelsHidden().accessibilityLabel("Gradient color \(i + 1) of \(stops.count)")
                }
            }
            if stops.count < 5 {
                Button("Add Color") { var n = s; n.stops = stops + [Backdrop.mix(stops.last!, c.theme.accent, 0.5)]; apply(n, live: false) }.buttonStyle(.link).font(.system(size: DS.footnote))
            }
            slider("Direction", value: s.angle ?? 0, range: 0...360, shown: "\(Int(s.angle ?? 0))°") { v in var n = s; n.angle = (v / 15).rounded() * 15; apply(n, live: true) }
        }
        if let sp = s.spectrum {
            // Palettes are shown as their colors, not as one color well: Spectrum is many colors.
            Text("Palette").font(.system(size: DS.footnote)).foregroundStyle(t.text)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Spectrum.palettes, id: \.id) { p in
                    let on = sp.palette == p.id
                    Button { var n = sp; n.palette = p.id; apply(EffectSpec(n.value), live: false) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(LinearGradient(colors: Spectrum(palette: p.id).colors(page: page).map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)).frame(height: 12)
                            Text(p.name).font(.system(size: DS.caption, weight: on ? .semibold : .regular)).foregroundStyle(t.text).lineLimit(1)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: DS.rControl).fill(on ? t.accent.opacity(0.14) : t.hover))
                        .overlay(RoundedRectangle(cornerRadius: DS.rControl).strokeBorder(on ? t.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.name) palette, \(p.colors.count) colors")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            row("Animate") {
                Toggle("Animate", isOn: Binding(get: { sp.speed != "still" }, set: { on in var n = sp; n.speed = on ? "slow" : "still"; apply(EffectSpec(n.value), live: false) }))
                    .labelsHidden().toggleStyle(.draft)
            }
            if sp.speed != "still" {
                row("Speed") {
                    DraftSegmented("Speed", selection: Binding(get: { sp.speed }, set: { v in var n = sp; n.speed = v; apply(EffectSpec(n.value), live: false) }), options: Spectrum.speeds.filter { $0.id != "still" }.map { ($0.id, $0.name) }).fixedSize()
                }
            }
            row("Direction") {
                DraftSegmented("Direction", selection: Binding(get: { sp.direction }, set: { v in var n = sp; n.direction = v; apply(EffectSpec(n.value), live: false) }), options: [("forward", "→"), ("backward", "←")]).fixedSize()
            }
            if !c.theme.animateEffects { Text("Still while Reduce Motion is on.").font(.system(size: DS.caption)).foregroundStyle(t.secondary) }
        }
    }

    /// Curated looks for the chosen effect, grouped by mood; each shows its own result.
    @ViewBuilder func presets(_ s: EffectSpec, page: String) -> some View {
        let list = EffectPresets.text(for: s.kind)
        if !list.isEmpty {
            Text("Presets").font(.system(size: DS.footnote)).foregroundStyle(t.text)
            ForEach(EffectPresets.groups.filter { g in list.contains { $0.group == g } }, id: \.self) { group in
                Text(group.uppercased()).font(.system(size: DS.micro + 1, weight: .semibold)).tracking(0.5).foregroundStyle(t.tertiary).padding(.top, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(list.filter { $0.group == group }, id: \.id) { p in
                        let on = s.value == p.value
                        Button { apply(EffectSpec(p.value), live: false) } label: {
                            HStack(spacing: 6) { sample(p, page: page).frame(width: 34, height: 20); Text(p.name).font(.system(size: DS.caption)).foregroundStyle(t.text).lineLimit(1); Spacer(minLength: 0) }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: DS.rControl).fill(on ? t.accent.opacity(0.14) : t.hover))
                                .overlay(RoundedRectangle(cornerRadius: DS.rControl).strokeBorder(on ? t.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(p.name), \(group) \(s.kind) preset")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// A small preview drawn the way the editor draws the effect.
    @ViewBuilder func sample(_ p: EffectPreset, page: String) -> some View {
        let e = EffectSpec(p.value) ?? EffectSpec(kind: "accent")
        let fills = e.fillColors(accent: c.theme.accent, text: c.theme.textColor, page: page)
        let k = CGFloat(e.intensity ?? 0.6)
        let col = Color(hex: e.color ?? c.theme.accent)
        let text = Color(hex: c.theme.textColor)
        let aa = Text("Aa").font(.system(size: 15, weight: .bold, design: .serif))
        switch e.kind {
        case "gradient", "spectrum":
            Capsule().fill(LinearGradient(colors: fills.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)).frame(height: 10)
        case "accent": aa.foregroundStyle(Color(hex: fills.first ?? c.theme.accent))
        case "glow": aa.foregroundStyle(text).shadow(color: col.opacity(0.9), radius: 1 + 3 * k)
        case "shadow": aa.foregroundStyle(text).shadow(color: col.opacity(0.35 + 0.5 * k), radius: 0.5 + 1.2 * k, y: 0.8 + 1.2 * k)
        case "lift": aa.foregroundStyle(text).shadow(color: col.opacity(0.25 + 0.3 * k), radius: 0, x: 0.5 + 0.8 * k, y: 0.5 + 0.8 * k)
        case "emboss": aa.foregroundStyle(text).shadow(color: col.opacity(0.3 + 0.5 * k), radius: 0, y: -1)
        case "outline": aa.foregroundStyle(text).shadow(color: col, radius: 0, x: 0.8).shadow(color: col, radius: 0, x: -0.8).shadow(color: col, radius: 0, y: 0.8).shadow(color: col, radius: 0, y: -0.8)
        default: aa.foregroundStyle(text)
        }
    }

    func defaultColor(_ kind: String) -> String {
        switch kind {
        case "shadow", "emboss": return "#000000"
        case "outline": return c.theme.accent
        case "lift": return TextEffects.colors(accent: c.theme.accent, text: c.theme.textColor, page: c.theme.pageColor).end
        default: return c.theme.accent
        }
    }

    func apply(_ s: EffectSpec?, live: Bool) { c.setEffect(s?.value, coalescing: live); model.editorTick &+= 1 }

    func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { Text(label).font(.system(size: DS.footnote)).foregroundStyle(t.text); Spacer(); content() }
    }

    func slider(_ title: String, value: Double, range: ClosedRange<Double>, shown: String, _ write: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: DS.footnote)).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { value }, set: write), in: range).controlSize(.small).accessibilityLabel(title).accessibilityValue(shown)
            Text(shown).font(.system(size: DS.caption, design: .monospaced)).frame(width: 40, alignment: .trailing)
        }
    }

    func colorBinding(_ hex: String, _ write: @escaping (String) -> Void) -> Binding<Color> {
        Binding(get: { Color(hex: hex) }, set: { col in
            let n = NSColor(col).usingColorSpace(.sRGB) ?? .black
            write(ColorMath.hex(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)))
        })
    }
}
