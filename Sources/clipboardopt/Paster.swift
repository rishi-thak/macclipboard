import AppKit
import ClipOptCore

/// Pastes a chosen value by briefly swapping the clipboard and sending Cmd+V,
/// then puts back exactly what was there before (images and files included).
@MainActor
final class Paster {
    private let pasteboard = NSPasteboard.general
    private let watcher: ClipboardWatcher
    /// The user's real clipboard, held while our temporary text is on it.
    private var pendingSnapshot: PasteboardSnapshot?
    private var restoreTask: Task<Void, Never>?

    /// Long enough for the target app to read the pasteboard after Cmd+V.
    static let restoreDelay: Duration = .milliseconds(400)

    init(watcher: ClipboardWatcher) {
        self.watcher = watcher
    }

    func paste(_ text: String) {
        // A second paste before the restore ran must not snapshot our own temporary text.
        let snapshot = pendingSnapshot ?? PasteboardSnapshot.capture(pasteboard)
        pendingSnapshot = snapshot
        restoreTask?.cancel()

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardMarkers.transient))
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount
        watcher.ignore(changeCount: ourChangeCount)

        KeyPoster.paste()

        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.restoreDelay)
            guard !Task.isCancelled, let self else { return }
            self.restore(ifStill: ourChangeCount)
        }
    }

    private func restore(ifStill changeCount: Int) {
        defer { pendingSnapshot = nil }
        // If you copied something in the meantime, keep that instead.
        guard pasteboard.changeCount == changeCount, let snapshot = pendingSnapshot else { return }
        let newCount = snapshot.restore(to: pasteboard)
        watcher.ignore(changeCount: newCount)
    }
}
