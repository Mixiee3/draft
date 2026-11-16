import AppKit
import DraftCore

/// A small, viewport-anchored entry point for the block under the caret. Text selections
/// continue to use SelectionToolbar; this bar expands only for whole-block selection.
final class BlockActionBar: NSView {
    weak var owner: DocumentEditorView?
    private let material: NSView = {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            // The action bar needs the standard glass plate so its controls stay
            // legible over bright document backgrounds.  This is still native
            // Liquid Glass (not a hand-painted translucent rectangle), but has
            // enough surface contrast for the compact controls.
            view.style = .regular
            view.cornerRadius = 17
            if #available(macOS 27.0, *) { view.effectIsInteractive = true }
            return view
        }
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }()
    private let glassContainer: NSView = {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectContainerView()
            view.spacing = 0
            return view
        }
        return NSView()
    }()
    private let glassContainerContent = NSView()
    private let stack = NSStackView()
    private let glassContent = NSView()
    private var expanded = false
    private var shown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        if #available(macOS 26.0, *), material is NSGlassEffectView {
        } else {
            material.wantsLayer = true
            material.layer?.cornerRadius = 17
            material.layer?.cornerCurve = .continuous
            material.layer?.masksToBounds = true
        }
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.wantsLayer = false
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            // Put the controls directly in contentView. AppKit only guarantees
            // correct z-order/elevation for this view, while an extra wrapper
            // can flatten the buttons into an invisible layer.
            glass.contentView = stack
        } else {
            material.addSubview(stack)
        }
        if #available(macOS 26.0, *), let container = glassContainer as? NSGlassEffectContainerView {
            container.contentView = glassContainerContent
            glassContainerContent.wantsLayer = false
        } else {
            glassContainer.addSubview(glassContainerContent)
        }
        glassContainerContent.addSubview(material)
        addSubview(glassContainer)
        alphaValue = 0
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(loc("Block actions"))
        rebuild(expanded: false)
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { shown ? super.hitTest(point) : nil }

    override func layout() {
        super.layout()
        glassContainer.frame = bounds
        glassContainerContent.frame = glassContainer.bounds
        material.frame = glassContainerContent.bounds
        stack.frame = material.bounds.insetBy(dx: 9, dy: 5)
    }

    private func button(_ symbol: String, label: String, action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.contentTintColor = .controlTextColor
        b.imageScaling = .scaleProportionallyUpOrDown
        b.image?.isTemplate = true
        b.wantsLayer = false
        b.imagePosition = .imageOnly
        b.toolTip = loc(label)
        b.setAccessibilityLabel(loc(label))
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    private func rebuild(expanded: Bool) {
        self.expanded = expanded
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        if expanded {
            stack.addArrangedSubview(button("arrow.triangle.2.circlepath", label: "Turn block into…", action: #selector(turnInto)))
            stack.addArrangedSubview(button("paintbrush", label: "Style block", action: #selector(styleBlock)))
            stack.addArrangedSubview(button("link", label: "Copy link to block", action: #selector(copyLink)))
            stack.addArrangedSubview(separator())
        } else {
            stack.addArrangedSubview(button("arrow.right.circle.fill", label: "Select block", action: #selector(selectBlock)))
            stack.addArrangedSubview(separator())
        }
        stack.addArrangedSubview(button("ellipsis", label: "More block actions", action: #selector(more)))
        owner?.needsLayout = true
    }

    func update() {
        guard let owner, let window = owner.window else { return }
        let c = owner.controller
        if #available(macOS 26.0, *), material is NSGlassEffectView {
            // Keep the system refraction, but give this compact control a subtle
            // adaptive tint so it remains a readable surface over light and
            // dark document pages instead of vanishing into the backdrop.
            if let glass = material as? NSGlassEffectView {
                glass.appearance = NSAppearance(named: c.theme.isDarkPage ? .darkAqua : .aqua)
                glass.tintColor = c.theme.isDarkPage
                    ? NSColor.black.withAlphaComponent(0.18)
                    : NSColor.white.withAlphaComponent(0.56)
            }
        } else {
            material.appearance = NSAppearance(named: c.theme.isDarkPage ? .darkAqua : .aqua)
        }
        // Buttons inherit the host window's dark appearance unless explicitly
        // corrected.  Keep the symbols readable while the glass surface stays
        // translucent and refractive.
        let ink = c.theme.isDarkPage ? NSColor.white : NSColor.black.withAlphaComponent(0.82)
        for view in stack.arrangedSubviews {
            (view as? NSButton)?.contentTintColor = ink
        }
        if #unavailable(macOS 26.0) {
            layer?.borderWidth = 0.5
            layer?.borderColor = (c.theme.isDarkPage ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.09)).cgColor
        }
        let selectedText = c.textView.selectedRange().length > 0 && !c.isBlockMode
        let visible = !selectedText && (window.firstResponder === c.textView || c.isBlockMode)
        if c.isBlockMode != expanded { rebuild(expanded: c.isBlockMode) }
        if visible != shown {
            shown = visible
            NSAnimationContext.runAnimationGroup { ctx in
                ContextBarMotion.configure(ctx)
                animator().alphaValue = visible ? 1 : 0
            }
        }
    }

    private func pop(_ menu: NSMenu, sender: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: sender.frame.minX, y: bounds.maxY + 5), in: self)
    }

    @objc private func selectBlock(_ sender: NSButton) {
        guard let c = owner?.controller else { return }
        owner?.window?.makeFirstResponder(c.textView)
        c.enterBlockMode()
        update()
    }

    @objc private func more(_ sender: NSButton) {
        guard let c = owner?.controller else { return }
        if !c.isBlockMode { c.enterBlockMode() }
        update()
        pop(c.blockMenu(), sender: sender)
    }

    @objc private func copyLink(_ sender: NSButton) {
        owner?.controller.copyLinkToBlock()
        update()
    }

    @objc private func turnInto(_ sender: NSButton) {
        guard let c = owner?.controller, let turn = c.blockMenu().items.first?.submenu else { return }
        pop(turn, sender: sender)
    }

    @objc private func styleBlock(_ sender: NSButton) {
        guard let c = owner?.controller else { return }
        let menu = NSMenu(title: loc("Style block"))
        for (title, kind) in [("None", ""), ("Focus", "focus"), ("Block", "block"), ("Gradient", "gradient"), ("Glass", "glass"), ("Glow", "glow"), ("Accent", "accent")] {
            let item = ClosureMenuItem(title: title) { [weak c] in c?.setDecoration(kind.isEmpty ? nil : kind) }
            item.state = c.currentBlock.decoration == (kind.isEmpty ? nil : kind) ? .on : .off
            menu.addItem(item)
        }
        pop(menu, sender: sender)
    }
}
