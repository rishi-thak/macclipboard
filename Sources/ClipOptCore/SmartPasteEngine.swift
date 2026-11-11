import Foundation

public struct Candidate: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case profile(FieldKind)
        case history(UUID)
        /// Your earlier pick for this same question.
        case remembered
    }

    public let text: String
    public let source: Source
    public let copiedAt: Date?

    public init(text: String, source: Source, copiedAt: Date? = nil) {
        self.text = text
        self.source = source
        self.copiedAt = copiedAt
    }

    init(_ item: ClipItem) {
        self.init(text: item.text, source: .history(item.id), copiedAt: item.copiedAt)
    }
}

/// The candidates sent to Jev, in question order (`fits_0`, `fits_1`, ...).
public struct JevPlan: Sendable, Equatable {
    public let candidates: [Candidate]
    public let askJobQuestion: Bool

    public init(candidates: [Candidate], askJobQuestion: Bool) {
        self.candidates = candidates
        self.askJobQuestion = askJobQuestion
    }
}

public enum PasteDecision: Sendable, Equatable {
    case paste(Candidate)
    case askJev(JevPlan)
    case showPanel(highlight: Candidate?, candidates: [Candidate], note: String?)
}

public struct SmartPasteInput: Sendable {
    public var field: FieldInfo
    public var fieldKind: FieldKind
    public var context: JobContext
    public var profile: Profile
    public var history: [ClipItem]
    /// What you picked last time for this question, if anything.
    public var remembered: String?
    public var now: Date

    public init(field: FieldInfo, fieldKind: FieldKind, context: JobContext,
                profile: Profile, history: [ClipItem], remembered: String? = nil, now: Date = Date()) {
        self.field = field
        self.fieldKind = fieldKind
        self.context = context
        self.profile = profile
        self.history = history
        self.remembered = remembered
        self.now = now
    }
}

/// The decision table. Jev only supplies yes/no probabilities; every rule is here.
public enum SmartPasteEngine {
    /// A copy this recent is treated as "I copied this to paste it here".
    public static let freshCopyWindow: TimeInterval = 30

    /// History (newest first), then profile values not already in history.
    public static func allCandidates(_ input: SmartPasteInput) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        if let remembered = input.remembered, seen.insert(remembered).inserted {
            result.append(Candidate(text: remembered, source: .remembered))
        }
        for item in input.history where seen.insert(item.text).inserted {
            result.append(Candidate(item))
        }
        for entry in input.profile.entries where seen.insert(entry.value).inserted {
            result.append(Candidate(text: entry.value, source: .profile(entry.kind)))
        }
        return result
    }

    /// What the panel lists for this field: only values of the field's kind
    /// (3 emails for an email field, not your links too). Unknown fields, or
    /// fields with nothing of their kind copied, list everything.
    public static func panelCandidates(_ input: SmartPasteInput) -> [Candidate] {
        let all = allCandidates(input)
        let kind = input.fieldKind
        guard kind != .unknown else { return all }
        let filtered = all.filter { candidate in
            if case .profile(let profileKind) = candidate.source {
                return profileKind == kind
            }
            return pickFits(candidate.text, kind: kind)
        }
        return filtered.isEmpty ? all : filtered
    }

    public static func decideLocally(_ input: SmartPasteInput) -> PasteDecision {
        let all = allCandidates(input)
        let kind = input.fieldKind
        let askJob = input.context == .unknown

        if FieldClassifier.isSensitive(input.field) {
            return .showPanel(highlight: nil, candidates: all, note: "Looks like a password field, so pick one yourself")
        }

        guard kind != .unknown else {
            if let remembered = input.remembered {
                return .paste(Candidate(text: remembered, source: .remembered))
            }
            if all.isEmpty || !input.field.hasHints {
                return .showPanel(highlight: nil, candidates: all, note: nil)
            }
            return .askJev(JevPlan(candidates: all, askJobQuestion: askJob))
        }

        let sameKind = input.history.filter { kind.itemKinds.contains($0.kind) }
        if let fresh = sameKind.first(where: { input.now.timeIntervalSince($0.copiedAt) <= freshCopyWindow }) {
            return .paste(Candidate(fresh))
        }

        let profileValue = input.profile.value(for: kind)
        if input.context == .jobApplication, let profileValue {
            return .paste(Candidate(text: profileValue, source: .profile(kind)))
        }

        // Nothing in the profile for this kind, but you answered this exact question before.
        if profileValue == nil, let remembered = input.remembered {
            return .paste(Candidate(text: remembered, source: .remembered))
        }

        var seen = Set<String>()
        var matches = sameKind.filter { seen.insert($0.text).inserted }.map(Candidate.init)
        if let profileValue, seen.insert(profileValue).inserted {
            matches.append(Candidate(text: profileValue, source: .profile(kind)))
        }

        switch matches.count {
        case 0:
            // Names have no clipboard kind; Jev can still spot one among plain text.
            if kind.itemKinds.isEmpty, !all.isEmpty {
                return .askJev(JevPlan(candidates: all, askJobQuestion: askJob))
            }
            return .showPanel(highlight: nil, candidates: all, note: "No \(kind.displayName) copied yet")
        case 1:
            return .paste(matches[0])
        default:
            return .askJev(JevPlan(candidates: matches, askJobQuestion: askJob))
        }
    }

    public static func decide(afterJev answers: JevAnswers, plan: JevPlan, input: SmartPasteInput) -> PasteDecision {
        let yes = JevQuestions.yesThreshold
        let no = JevQuestions.noThreshold

        if plan.askJobQuestion,
           let job = answers.noul(JevQuestions.ID.isJobApplication), job >= yes,
           let profileValue = input.profile.value(for: input.fieldKind) {
            return .paste(Candidate(text: profileValue, source: .profile(input.fieldKind)))
        }

        let scores = plan.candidates.indices.map { answers.noul(JevQuestions.ID.fits($0)) ?? 0 }
        let anything = answers.noul(JevQuestions.ID.anythingFits)

        if let anything, anything < no {
            return .showPanel(highlight: nil, candidates: panelCandidates(input),
                              note: "Nothing copied seems to fit this field")
        }
        // One clear winner is enough; "anything fits" only vetoes when it's a clear no (above).
        let winners = scores.indices.filter { scores[$0] >= yes }
        if winners.count == 1 {
            return .paste(plan.candidates[winners[0]])
        }
        let kind = input.fieldKind
        // Only kinds with a clipboard type (email, phone, links) were filtered before Jev,
        // so only for those does the count mean "N of this kind copied".
        let countable = !kind.itemKinds.isEmpty
        if !countable, kind != .unknown, winners.isEmpty {
            return .showPanel(highlight: nil, candidates: panelCandidates(input),
                              note: "No \(kind.displayName) copied yet")
        }
        let best = scores.indices.max { scores[$0] < scores[$1] }.map { plan.candidates[$0] }
        let note: String
        if countable, plan.candidates.count > 1 {
            note = "\(plan.candidates.count) \(kind.displayName)s copied. Which one?"
        } else {
            note = winners.count > 1 ? "A few of these could fit" : "Not sure which one fits"
        }
        return .showPanel(highlight: best, candidates: panelCandidates(input), note: note)
    }

    /// The field kind a panel pick should be saved as, when the profile has no value for it yet.
    public static func learnableKind(_ input: SmartPasteInput) -> FieldKind? {
        let kind = input.fieldKind
        // Address and location are put together from parts, so a pick can't be saved as one.
        guard ![.unknown, .address, .location].contains(kind), input.profile.value(for: kind) == nil else { return nil }
        return kind
    }

    /// The kind a correction pick (after a double press) is saved as, replacing any saved value.
    public static func correctableKind(_ input: SmartPasteInput) -> FieldKind? {
        input.fieldKind == .unknown ? nil : input.fieldKind
    }

    /// Only saves picks that look like the field: a LinkedIn URL for LinkedIn,
    /// a short single line for a name.
    public static func pickFits(_ text: String, kind: FieldKind) -> Bool {
        let itemKind = ItemClassifier.classify(text)
        if kind.itemKinds.isEmpty {
            return itemKind == .other && !text.contains("\n") && text.trimmed.count <= 60
        }
        return kind.itemKinds.contains(itemKind)
    }

    public static func decideAfterFailure(input: SmartPasteInput, message: String) -> PasteDecision {
        .showPanel(highlight: nil, candidates: panelCandidates(input), note: message)
    }
}
