import Foundation

/// Where a form-fill value came from.
public enum FillSource: Sendable, Equatable {
    case profile(FieldKind)
    case remembered
    case jev
}

public struct Fill: Sendable, Equatable {
    public let text: String
    public let source: FillSource

    public init(text: String, source: FillSource) {
        self.text = text
        self.source = source
    }
}

/// What a double tap will do with each empty field, by index into the field list.
public struct FormFillPlan: Sendable, Equatable {
    public var fills: [Int: Fill] = [:]
    /// Fields that describe themselves but have no saved value: worth asking Jev about.
    public var unclear: [Int] = []
    /// Fields left alone: nothing to go on.
    public var skipped: [Int] = []

    public init() {}
}

/// The candidates and field order in one form-fill Jev request.
public struct FormJevPlan: Sendable, Equatable {
    public let fields: [Int]
    public let candidates: [String]

    public init(fields: [Int], candidates: [String]) {
        self.fields = fields
        self.candidates = candidates
    }
}

/// Fill-the-whole-form rules. Only sure values are filled: your profile, your saved
/// answers, and Jev picks with one clear winner. Everything else is left for you.
public enum FormFiller {
    public static let maxJevFields = 8
    public static let maxJevCandidates = 12

    public static func planLocally(fields: [FieldInfo], profile: Profile, memory: FieldMemory) -> FormFillPlan {
        var plan = FormFillPlan()
        for (index, field) in fields.enumerated() {
            let kind = FieldClassifier.classify(field)
            if let value = profile.value(for: kind) {
                plan.fills[index] = Fill(text: value, source: .profile(kind))
            } else if let answer = memory.answer(for: field) {
                plan.fills[index] = Fill(text: answer, source: .remembered)
            } else if FieldMemory.key(for: field) != nil {
                plan.unclear.append(index)
            } else {
                plan.skipped.append(index)
            }
        }
        return plan
    }

    /// Your saved answers first (they're answers to questions like these), then your
    /// profile values ("How can we reach you?" wants your email even if the Email field
    /// already has it), then recent single-line copies.
    public static func jevPlan(_ plan: FormFillPlan, memory: FieldMemory, profile: Profile,
                               history: [ClipItem]) -> FormJevPlan? {
        let fields = Array(plan.unclear.prefix(maxJevFields))
        guard !fields.isEmpty else { return nil }

        var seen = Set<String>()
        var candidates: [String] = []
        let saved = memory.answers.values.sorted { $0.savedAt > $1.savedAt }.map(\.text)
        let mine = profile.entries.filter { $0.kind != .firstName && $0.kind != .lastName }.map(\.value)
        let copied = history.map(\.text).filter { !$0.contains("\n") && $0.trimmed.count <= 120 }
        for text in saved + mine + copied where candidates.count < maxJevCandidates {
            let value = text.trimmed
            if !value.isEmpty, seen.insert(value).inserted { candidates.append(value) }
        }
        guard !candidates.isEmpty else { return nil }
        return FormJevPlan(fields: fields, candidates: candidates)
    }

    /// A field is filled only when exactly one candidate clears the yes bar.
    public static func fills(afterJev answers: JevAnswers, plan: FormJevPlan) -> [Int: Fill] {
        var result: [Int: Fill] = [:]
        for (fieldPosition, fieldIndex) in plan.fields.enumerated() {
            let winners = plan.candidates.indices.filter {
                (answers.noul(JevQuestions.ID.formFits(field: fieldPosition, candidate: $0)) ?? 0) >= JevQuestions.yesThreshold
            }
            if winners.count == 1 {
                result[fieldIndex] = Fill(text: plan.candidates[winners[0]], source: .jev)
            }
        }
        return result
    }
}
