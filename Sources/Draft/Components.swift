import SwiftUI
import AppKit
import DraftCore

// MARK: - Buttons

/// Draft's button: one shape and size family for every action in panels, sheets and Settings.
struct DraftButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive, quiet }
    var role: Role = .secondary
    var compact = false
    @Environment(\.tokens) var t
    @Environment(\.isEnabled) var enabled
    @Environment(\.isFocused) var focused

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: compact ? DS.footnote : DS.body, weight: role == .primary ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, compact ? DS.s2 + 2 : DS.s3 + 2)
            .frame(minHeight: compact ? DS.controlSmall : DS.control)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(background(pressed)))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(role == .secondary ? t.line : .clear, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
            // Keyboard navigation: the same accent ring as Draft's text fields, outside the control.
            .overlay(RoundedRectangle(cornerRadius: DS.rControl + 3, style: .continuous).strokeBorder(t.accent.opacity(focused ? 0.75 : 0), lineWidth: 2.5).padding(-3.5))
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.quick(false), value: pressed)
    }

    var foreground: Color {
        switch role {
        case .primary: return .white
        case .destructive: return Color(hex: "#d24b4b")
        case .secondary, .quiet: return t.text
        }
    }

    func background(_ pressed: Bool) -> Color {
        switch role {
        case .primary: return t.accent.opacity(pressed ? 0.8 : 1)
        case .destructive: return Color(hex: "#d24b4b").opacity(pressed ? 0.18 : 0.1)
        case .secondary: return pressed ? t.selected : t.hover.opacity(1.6)
        case .quiet: return pressed ? t.selected : .clear
        }
    }
}

extension ButtonStyle where Self == DraftButtonStyle {
    static var draft: DraftButtonStyle { DraftButtonStyle() }
    static var draftPrimary: DraftButtonStyle { DraftButtonStyle(role: .primary) }
    static var draftDestructive: DraftButtonStyle { DraftButtonStyle(role: .destructive) }
    static var draftQuiet: DraftButtonStyle { DraftButtonStyle(role: .quiet) }
}

/// A square icon that opens a menu. Plain-button menus draw the label as-is, so the glyph is
/// centred by layout; the borderless pop-up style kept space for a hidden arrow and sat off-centre.
struct DraftIconMenu<Content: View>: View {
    @Environment(\.tokens) var t
    var symbol: String
    var label: LocalizedStringKey
    var size: CGFloat = DS.control
    var onPill = true
    var color: Color? = nil
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Menu { content } label: {
            Image(systemName: symbol)
                .font(.system(size: DS.body, weight: .semibold))
                .foregroundStyle(color ?? (onPill ? t.pillText : t.secondary))
                .frame(width: size, height: size)
                .background(Circle().fill(hover ? t.hover : .clear))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Fields

/// Text field with Draft's fill and an accent focus ring.
struct DraftTextField: View {
    @Environment(\.tokens) var t
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: DS.body))
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, DS.s3).frame(height: DS.control)
            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(focused ? t.accent.opacity(0.6) : t.line, lineWidth: focused ? 1.5 : 0.5))
            .animation(Motion.quick(false), value: focused)
    }
}

// MARK: - Settings rows

/// A grouped card of rows separated by hairlines (Settings, Info).
struct SettingsSection<Content: View>: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            if let title { Text(title).font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary).textCase(.uppercase).accessibilityAddTraits(.isHeader) }
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedLayout(line: t.line)) { content }
            }
            .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card.opacity(t.dark ? 0.55 : 1)))
            .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
            if let footer { Text(footer).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, DS.s1) }
        }
    }
}

/// Puts a hairline between the rows of a section.
struct DividedLayout: _VariadicView_MultiViewRoot {
    var line: Color
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            child
            if child.id != children.last?.id { Rectangle().fill(line).frame(height: 0.5).padding(.leading, DS.s3 + 2) }
        }
    }
}

/// One Settings row: a title (and optional explanation) with its control on the trailing side.
struct SettingsRow<Trailing: View>: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: DS.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: DS.body)).foregroundStyle(t.text)
                if let detail { Text(detail).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: DS.s3)
            trailing
        }
        .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2 + 2)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsSwitchRow: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @Binding var isOn: Bool
    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(t.accent)
        }
    }
}

/// A row whose value is chosen from a menu: shows the current choice with a quiet chevron.
struct SettingsMenuRow<V: Hashable>: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @Binding var selection: V
    var options: [(V, String)]
    var disabled = false

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    Button { selection = o.0 } label: { if o.0 == selection { Label(o.1, systemImage: "checkmark") } else { Text(o.1) } }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(options.first { $0.0 == selection }?.1 ?? "—").font(.system(size: DS.body)).foregroundStyle(t.text).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: DS.micro, weight: .semibold)).foregroundStyle(t.tertiary)
                }
                .padding(.horizontal, DS.s3).frame(height: DS.controlSmall + 4)
                .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(disabled).opacity(disabled ? 0.45 : 1)
            .accessibilityLabel(title)
            .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
        }
    }
}

/// Keyboard shortcuts as a readable two-column list.
struct ShortcutList: View {
    @Environment(\.tokens) var t
    let items: [(String, String)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack {
                    Text(item.1).font(.system(size: DS.body)).foregroundStyle(t.text)
                    Spacer()
                    Text(item.0).font(.system(size: DS.body, design: .rounded).weight(.medium)).foregroundStyle(t.secondary)
                        .padding(.horizontal, DS.s2).frame(height: DS.controlSmall)
                        .background(RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous).fill(t.hover))
                }
                .padding(.horizontal, DS.s3 + 2).frame(height: 38)
                .accessibilityElement(children: .combine)
                if i < items.count - 1 { Rectangle().fill(t.line).frame(height: 0.5).padding(.leading, DS.s3 + 2) }
            }
        }
    }
}

// MARK: - Empty states

struct EmptyState<Action: View>: View {
    @Environment(\.tokens) var t
    var symbol: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: DS.s3) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(t.tertiary)
                .frame(width: 56, height: 56).background(Circle().fill(t.hover))
            Text(title).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
            Text(message).font(.system(size: DS.body)).foregroundStyle(t.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.s6)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Action == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) { self.init(symbol: symbol, title: title, message: message) { EmptyView() } }
}

// MARK: - Surfaces

/// A native material behind SwiftUI content (vibrancy follows the window's appearance).
struct MaterialBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .withinWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Draft's three surface levels. Floating panels and overlays sit on a translucent native
/// material tinted with the theme, so text keeps its contrast whatever is behind them.
enum SurfaceLevel { case floating, overlay }

struct Surface: ViewModifier {
    @Environment(\.tokens) var t
    var level: SurfaceLevel
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let s = DS.floatingShadow(dark: t.dark)
        content
            .background(shape.fill((t.dark ? Color(hex: "#26262a") : Color(hex: "#fbfaf8")).opacity(level == .overlay ? 0.78 : 0.82)))
            .background(MaterialBackground(material: level == .overlay ? .hudWindow : .popover).clipShape(shape))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(t.dark ? 0.16 : 0.75), Color.white.opacity(t.dark ? 0.04 : 0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.strokeBorder(Color.black.opacity(t.dark ? 0.5 : 0.07), lineWidth: 0.5).padding(-0.5))
            .shadow(color: s.0, radius: s.1, y: s.2)
    }
}

extension View {
    func surface(_ level: SurfaceLevel = .floating, radius: CGFloat = DS.rPanel) -> some View { modifier(Surface(level: level, radius: radius)) }

    /// Panels, popovers and the pinned Assistant: in with a spring, out faster; a fade only when
    /// motion is reduced.
    func panelTransition(edge: Edge = .trailing, reduce: Bool) -> some View {
        transition(Motion.reduced(reduce)
            ? .opacity
            : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .move(edge: edge).combined(with: .opacity)))
    }

}

/// Screens replacing each other (library ↔ document, a new note, a Space switch): the new
/// screen settles in from 35 % opacity and 6 pt lower, so its caret and text show from the first
/// frame; the old one leaves at once, so two screens are never rendered together.
struct ArrivalEffect: ViewModifier {
    var opacity: Double
    var y: CGFloat
    func body(content: Content) -> some View { content.opacity(opacity).offset(y: y) }
}

extension AnyTransition {
    static var screenArrival: AnyTransition {
        .asymmetric(insertion: .modifier(active: ArrivalEffect(opacity: Motion.reduced(false) ? 0.6 : 0.35, y: Motion.reduced(false) ? 0 : 6), identity: ArrivalEffect(opacity: 1, y: 0)),
                    removal: .identity)
    }
}

extension AnyTransition {
    /// Quick Open, the template picker and dialogs: a short fade with a slight lift, gone quickly.
    static var overlayPop: AnyTransition {
        Motion.systemReduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)), removal: .opacity)
    }
}
