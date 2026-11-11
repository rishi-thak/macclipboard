import AppKit

/// Borderless panel that takes keys without pulling focus away from Safari,
/// so the field you were in stays focused for the paste.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class KeyCatcherView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

private final class RowView: NSView {
    let index: Int
    var onClick: ((Int) -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let number = NSTextField(labelWithString: "")

    init(index: Int, text: String, detailText: String, saved: Bool = false) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        number.stringValue = index < 9 ? "\(index + 1)" : (index == 9 ? "0" : "")
        number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        number.textColor = .tertiaryLabelColor
        number.setContentHuggingPriority(.required, for: .horizontal)

        title.stringValue = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detail.stringValue = detailText
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = saved ? .controlAccentColor : .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let row = NSStackView(views: [number, texts])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    struct Entry {
        let text: String
        let detail: String
        /// Your saved value or earlier answer: its detail line is drawn in the accent color.
        var saved = false
    }

    private var panel: KeyPanel?
    private var entries: [Entry] = []
    private var rows: [RowView] = []
    private var selected = 0
    private var onPick: ((Entry) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameter anchor: the field's frame in Accessibility (top-left) coordinates.
    func show(entries: [Entry], selected: Int?, note: String?, anchor: CGRect?, onPick: @escaping (Entry) -> Void) {
        close()
        self.entries = entries
        self.onPick = onPick
        self.selected = selected ?? 0

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: note ?? (entries.isEmpty ? "Nothing copied yet" : "Clipboard"))
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(6, after: header)

        rows = entries.enumerated().map { index, entry in
            let row = RowView(index: index, text: entry.text, detailText: entry.detail, saved: entry.saved)
            row.onClick = { [weak self] index in self?.pick(index) }
            return row
        }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
        }
        updateSelection()

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        let root = KeyCatcherView()
        root.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        root.addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            effect.topAnchor.constraint(equalTo: root.topAnchor),
            effect.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 380),
        ])
        root.layoutSubtreeIfNeeded()
        let size = root.fittingSize

        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = root
        panel.setFrameOrigin(origin(for: size, anchor: anchor))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(root)
        self.panel = panel
    }

    func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        rows = []
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 125: move(1); return true            // down
        case 126: move(-1); return true           // up
        case 36, 76: pick(selected); return true  // return, enter
        case 53: close(); return true             // escape
        default: break
        }
        if let char = event.charactersIgnoringModifiers?.first, let digit = char.wholeNumberValue {
            pick(digit == 0 ? 9 : digit - 1)
            return true
        }
        return false
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = (selected + delta + rows.count) % rows.count
        updateSelection()
    }

    private func updateSelection() {
        for row in rows { row.isSelected = row.index == selected }
    }

    private func pick(_ index: Int) {
        guard entries.indices.contains(index) else {
            if entries.isEmpty { close() }
            return
        }
        let entry = entries[index]
        let callback = onPick
        close()
        callback?(entry)
    }

    // MARK: - Placement

    private func origin(for size: NSSize, anchor: CGRect?) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var origin: NSPoint
        var fieldTop: CGFloat?
        if let anchor {
            let fieldBottom = primaryHeight - anchor.maxY  // AppKit y of the field's bottom edge
            fieldTop = primaryHeight - anchor.minY
            origin = NSPoint(x: anchor.minX, y: fieldBottom - size.height - 6)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        }
        let probe = NSPoint(x: origin.x + 1, y: origin.y + size.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(probe) }) ?? NSScreen.main else {
            return origin
        }
        let visible = screen.visibleFrame
        if origin.y < visible.minY, let fieldTop {
            origin.y = fieldTop + 6  // no room below the field: open above it
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }
}
