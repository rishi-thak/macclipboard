import Foundation

/// Your answers to questions that aren't profile fields ("When are you graduating?"),
/// keyed by the question's wording so the same question fills itself next time,
/// on any site. Lives in ~/Library/Application Support/ClipboardOpt/answers.json.
public struct FieldMemory: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var text: String
        public var savedAt: Date
    }

    public static let capacity = 200
    public private(set) var answers: [String: Entry] = [:]

    public init() {}

    /// The question's wording, lowercased, letters and digits only. Nil when the
    /// field says nothing about itself, since then there's nothing to match on.
    public static func key(for field: FieldInfo) -> String? {
        // Past-job fields ("Description", "Location") repeat per entry: an answer for one isn't for the next.
        guard !FieldClassifier.isSensitive(field), !field.isInHistorySection else { return nil }
        let question = [field.label, field.nearbyText, field.placeholder, field.help]
            .map(\.trimmed)
            .first { !$0.isEmpty && !genericPrompts.contains(words($0)) }
        guard let question else { return nil }
        let key = words(question)
        return key.isEmpty ? nil : String(key.prefix(200))
    }

    /// Placeholders that every free-text box uses; they don't identify a question.
    static let genericPrompts: Set<String> = [
        "type your response", "type here", "your answer", "enter your answer", "answer",
        "start typing", "type your answer", "enter text",
    ]

    static func words(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public func answer(for field: FieldInfo) -> String? {
        Self.key(for: field).flatMap { answers[$0]?.text }
    }

    public mutating func remember(_ text: String, for field: FieldInfo, at date: Date = Date()) {
        guard let key = Self.key(for: field) else { return }
        answers[key] = Entry(text: text.trimmed, savedAt: date)
        if answers.count > Self.capacity,
           let oldest = answers.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            answers.removeValue(forKey: oldest)
        }
    }

    public static func load(from url: URL) -> FieldMemory {
        guard let data = try? Data(contentsOf: url),
              let memory = try? JSONDecoder.iso.decode(FieldMemory.self, from: data) else { return FieldMemory() }
        return memory
    }

    public func save(to url: URL) throws {
        try JSONEncoder.iso.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
