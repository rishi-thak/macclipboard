import AppKit
import Foundation
import Testing
@testable import ClipOptCore

@Suite struct ClipboardHistoryTests {
    @Test func keepsNewestTenWithoutDuplicates() {
        var history = ClipboardHistory(capacity: 10)
        for i in 0..<15 { history.record("item \(i)") }
        #expect(history.items.count == 10)
        #expect(history.items.first?.text == "item 14")
        #expect(history.items.last?.text == "item 5")
    }

    @Test func copyingAgainMovesToFront() {
        var history = ClipboardHistory()
        let early = Date(timeIntervalSince1970: 0)
        history.record("a@b.com", at: early)
        history.record("other")
        let later = Date(timeIntervalSince1970: 100)
        history.record("a@b.com", at: later)
        #expect(history.items.map(\.text) == ["a@b.com", "other"])
        #expect(history.items[0].copiedAt == later)
        #expect(history.items[0].kind == .email)
    }

    @Test func ignoresBlankCopies() {
        var history = ClipboardHistory()
        #expect(history.record("   \n") == nil)
        #expect(history.items.isEmpty)
    }

    @Test func savesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = ClipboardHistory()
        history.record("one")
        history.record("4155550134")
        try history.save(to: url)
        let loaded = ClipboardHistory.load(from: url)
        #expect(loaded.items.map(\.text) == ["4155550134", "one"])
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}

/// Smart paste swaps the clipboard briefly. These check that whatever was there
/// (an image especially) comes back byte for byte, so a normal Cmd+V is unaffected.
@Suite(.serialized) struct PasteboardSnapshotTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.rishi.clipboardopt.tests.\(UUID().uuidString)"))
    }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func imageSurvivesSmartPasteSwap() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let png = pngData()
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        let snapshot = PasteboardSnapshot.capture(pasteboard)

        // What smart paste does in between.
        pasteboard.clearContents()
        pasteboard.setString("me@example.com", forType: .string)

        snapshot.restore(to: pasteboard)
        #expect(pasteboard.data(forType: .png) == png)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.types?.contains(.png) == true)
    }

    @Test func everyTypeAndItemComesBack() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let png = pngData()
        let first = NSPasteboardItem()
        first.setData(png, forType: .png)
        first.setString("caption", forType: .string)
        first.setData(Data("<b>caption</b>".utf8), forType: .html)
        let second = NSPasteboardItem()
        second.setString("file:///tmp/a.png", forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
        let before = PasteboardSnapshot.capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        before.restore(to: pasteboard)

        #expect(PasteboardSnapshot.capture(pasteboard) == before)
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.data(forType: .png) == png)
    }

    @Test func emptyClipboardStaysEmpty() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.setString("temporary", forType: .string)
        snapshot.restore(to: pasteboard)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
    }
}
