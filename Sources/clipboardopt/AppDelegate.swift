import AppKit
import ApplicationServices
import ClipOptCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var watcher: ClipboardWatcher?
    private var coordinator: SmartPasteCoordinator?
    private var hotKeys: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPaths.prepare()
        try? Profile.writeTemplateIfMissing(at: AppPaths.profile)

        let key = APIKeyLoader.load(
            environment: ProcessInfo.processInfo.environment,
            envFiles: [AppPaths.envFile, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")]
        )
        let jev = key.map { JevClient(apiKey: $0) }
        Log.app.info("started jev_key=\(key != nil, privacy: .public)")

        // The watcher and paster need each other: the paster tells the watcher to
        // ignore its own temporary clipboard writes.
        var coordinatorRef: SmartPasteCoordinator?
        let watcher = ClipboardWatcher { text in coordinatorRef?.record(text) }
        let coordinator = SmartPasteCoordinator(
            history: ClipboardHistory.load(from: AppPaths.history),
            paster: Paster(watcher: watcher),
            jev: jev
        )
        coordinatorRef = coordinator
        self.watcher = watcher
        self.coordinator = coordinator
        watcher.start()

        setUpStatusItem(hasJev: jev != nil)
        startHotKeysWhenTrusted()
    }

    // MARK: - Accessibility

    private func startHotKeysWhenTrusted() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startHotKeys()
            return
        }
        Log.app.info("waiting for Accessibility permission")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.startHotKeys()
            }
        }
    }

    private func startHotKeys() {
        let manager = HotKeyManager { [weak self] in
            Task { @MainActor in self?.coordinator?.handleHotKey() }
        }
        manager.start()
        hotKeys = manager
        rebuildMenu()
    }

    // MARK: - Menu bar

    private func setUpStatusItem(hasJev: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipboardOpt")
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = hotKeys == nil ? "Needs Accessibility permission" : "Cmd+Opt+V smart paste is on"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        let jevStatus = (coordinator?.hasJev ?? false) ? "Jev: ready" : "Jev: no API key found"
        menu.addItem(withTitle: jevStatus, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show History", action: #selector(showHistory), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Edit Profile…", action: #selector(editProfile), keyEquivalent: "").target = self
        if hotKeys == nil {
            menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipboardOpt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func showHistory() { coordinator?.showHistory() }

    @objc private func editProfile() {
        NSWorkspace.shared.open(AppPaths.profile)
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
