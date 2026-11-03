import Foundation

public struct ClipItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var kind: ItemKind
    public var copiedAt: Date

    public init(id: UUID = UUID(), text: String, kind: ItemKind, copiedAt: Date) {
        self.id = id
        self.text = text
        self.kind = kind
        self.copiedAt = copiedAt
    }
}

/// The last few text copies, newest first, with no duplicates.
/// At this size a plain array beats any ring buffer or linked list.
public struct ClipboardHistory: Codable, Sendable, Equatable {
    public private(set) var items: [ClipItem]
    public let capacity: Int

    public init(capacity: Int = 10, items: [ClipItem] = []) {
        self.capacity = capacity
        self.items = Array(items.prefix(capacity))
    }

    /// Adds a copy. Copying something already in history moves it to the front.
    @discardableResult
    public mutating func record(_ text: String, at date: Date = Date()) -> ClipItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
            return existing
        }
        let item = ClipItem(text: text, kind: ItemClassifier.classify(text), copiedAt: date)
        items.insert(item, at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
        return item
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    // MARK: - Disk

    public static func load(from url: URL, capacity: Int = 10) -> ClipboardHistory {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.iso.decode(ClipboardHistory.self, from: data) else {
            return ClipboardHistory(capacity: capacity)
        }
        return ClipboardHistory(capacity: capacity, items: decoded.items)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder.iso.encode(self)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
