import ApplicationServices
import Carbon
import Foundation

/// Session event tap that catches Cmd+Opt+V, on its own thread (same approach as SSClipboard).
///
/// The callback never checks the focused field itself: Accessibility calls can be slow,
/// and a slow tap gets disabled by macOS. It swallows Cmd+Opt+V and hands off to the main
/// thread, which re-sends the keystroke (`KeyPoster.passThrough`) if no text field is focused.
///
/// Privacy: the tap sees every key in the session. It must never log or store any key
/// other than the one shortcut it matches.
final class HotKeyManager: @unchecked Sendable {
    private let onPress: @Sendable () -> Void

    private var swallowedKeyDown = false  // tap thread only
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private let lock = NSLock()

    init(onPress: @escaping @Sendable () -> Void) {
        self.onPress = onPress
    }

    func start() {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(event: event, type: type)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.error("could not create event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // CF handles aren't marked Sendable; they're only touched by the tap thread here.
        let handles = TapHandles(tap: tap, source: source)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.lock.lock()
            self.tapRunLoop = runLoop
            self.lock.unlock()
            ready.signal()
            CFRunLoopAddSource(runLoop, handles.source, .commonModes)
            CGEvent.tapEnable(tap: handles.tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.rishi.clipboardopt.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)

        lock.lock()
        eventTap = tap
        runLoopSource = source
        lock.unlock()
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Keystrokes we post ourselves (pass-through, Cmd+V, Cmd+Z) go straight on.
        if event.getIntegerValueField(.eventSourceUserData) == KeyPoster.marker {
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V) else {
            return Unmanaged.passUnretained(event)
        }

        let relevant = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        if type == .keyUp {
            if swallowedKeyDown {
                swallowedKeyDown = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard relevant == [.maskCommand, .maskAlternate] else {
            return Unmanaged.passUnretained(event)
        }

        swallowedKeyDown = true
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { [onPress] in onPress() }
        }
        return nil
    }
}

private struct TapHandles: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource?
}

/// Posts keystrokes tagged so our own tap lets them through.
enum KeyPoster {
    static let marker: Int64 = 0x434C4950  // "CLIP"

    static func press(keyCode: Int, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    static func paste() { press(keyCode: kVK_ANSI_V, flags: .maskCommand) }
    static func undo() { press(keyCode: kVK_ANSI_Z, flags: .maskCommand) }
    /// Re-sends Cmd+Opt+V untouched, e.g. Finder's "Move Item Here".
    static func passThrough() { press(keyCode: kVK_ANSI_V, flags: [.maskCommand, .maskAlternate]) }
}
