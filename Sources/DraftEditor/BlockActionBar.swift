import AppKit
import DraftCore

/// A small, viewport-anchored entry point for the block under the caret. Text selections
/// continue to use SelectionToolbar; this bar expands only for whole-block selection.
final class BlockActionBar: NSView {
    weak var owner: DocumentEditorView?
    /// Native Liquid Glass on macOS 26+, the vibrancy material before; the button row is its content.
    private let material: NSView = {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .regular
            view.cornerRadius = 20
            return view
        }
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }()
    private let stack = NSStackView()
    private var expanded = false
    private var shown = false
    private var darkPage: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.contentView = stack
        } else {
            material.addSubview(stack)
        }
        addSubview(material)
        alphaValue = 0
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(loc("Block actions"))
        rebuild(expanded: false)
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { shown ? super.hitTest(point) : nil }
    /// The bar is exactly as wide as its buttons; the editor centres it.
    override var fittingSize: NSSize { stack.fittingSize }

    override func layout() {
        super.layout()
        material.frame = bounds
        stack.frame = material.bounds
    }

    private func button(_ symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: loc(label))!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!
        let b = NSButton(image: image, target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.toolTip = loc(label)
        b.setAccessibilityLabel(loc(label))
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }

    private func rebuild(expanded: Bool) {
        self.expanded = expanded
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        if expanded {
            stack.addArrangedSubview(button("arrow.triangle.2.circlepath", label: "Turn block into…", action: #selector(turnInto)))
            stack.addArrangedSubview(button("paintbrush", label: "Style block", action: #selector(styleBlock)))
            stack.addArrangedSubview(button("link", label: "Copy link to block", action: #selector(copyLink)))
        } else {
            stack.addArrangedSubview(button("square.dashed", label: "Select block", action: #selector(selectBlock)))
        }
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(button("ellipsis", label: "More block actions", action: #selector(more)))
        applyInk()
        owner?.placeBlockActions()
    }

    /// Page-matched ink: the window's appearance can be dark while the page is light.
    private func applyInk() {
        let ink = darkPage == true ? NSColor.white : NSColor.black.withAlphaComponent(0.82)
        for case let b as NSButton in stack.arrangedSubviews { b.contentTintColor = ink }
    }

    func update() {
        guard let owner, let window = owner.window else { return }
        let c = owner.controller
        if darkPage != c.theme.isDarkPage {
            darkPage = c.theme.isDarkPage
            ContextBarGlass.apply(to: material, darkPage: c.theme.isDarkPage)
            applyInk()
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
        // Open above the bar: it sits at the bottom of the editor.
        menu.popUp(positioning: nil, at: NSPoint(x: sender.convert(NSPoint.zero, to: self).x, y: bounds.maxY + 6), in: self)
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
