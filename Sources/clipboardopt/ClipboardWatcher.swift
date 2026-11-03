import AppKit
import ClipOptCore

/// macOS sends no "copied" event, so this checks the pasteboard's change counter
/// four times a second. It only reads; it never changes what's on the clipboard.
@MainActor
final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var ignoredChangeCounts = Set<Int>()
    private var timer: Timer?
    private let onText: (String) -> Void

    static let maxTextLength = 20_000

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.05
    }

    /// Changes we made ourselves (temporary paste, restore) aren't new copies.
    func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if ignoredChangeCounts.remove(count) != nil { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if !types.isDisjoint(with: PasteboardMarkers.skip) {
            Log.watcher.debug("skipped concealed or transient copy")
            return
        }
        // Text only for now. Images and files are left alone.
        guard types.isDisjoint(with: PasteboardMarkers.nonText),
              let text = pasteboard.string(forType: .string),
              !text.isEmpty, text.count <= Self.maxTextLength else { return }
        onText(text)
    }
}
