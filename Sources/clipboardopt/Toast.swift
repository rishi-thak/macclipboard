import AppKit

/// A small message near the top of the screen that fades on its own: "Filled 9 fields · 3 left for you".
/// Never takes focus, never blocks clicks.
@MainActor
final class Toast {
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, for duration: Duration = .milliseconds(2600)) {
        hideTask?.cancel()
        let panel = window ?? makeWindow()
        window = panel
        guard let label = panel.contentView?.subviews.first(where: { $0 is NSTextField }) as? NSTextField else { return }
        label.stringValue = message
        label.sizeToFit()

        let size = NSSize(width: label.frame.width + 32, height: label.frame.height + 18)
        label.frame.origin = NSPoint(x: 16, y: 9)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 24,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let panel = self?.window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor

        let content = NSView()
        background.frame = content.bounds
        content.addSubview(background)
        content.addSubview(label)
        panel.contentView = content
        return panel
    }
}
