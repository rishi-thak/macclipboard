import Foundation
import Testing
@testable import ClipOptCore

@Suite struct PanelFilterTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func input(kind: FieldKind, label: String, history texts: [String], profile: Profile = Profile()) -> SmartPasteInput {
        let items = texts.map { ClipItem(text: $0, kind: ItemClassifier.classify($0), copiedAt: now.addingTimeInterval(-600)) }
        return SmartPasteInput(field: FieldInfo(label: label), fieldKind: kind, context: .notJobApplication,
                               profile: profile, history: items, now: now)
    }

    private let mixed = [
        "a@example.com", "https://www.linkedin.com/in/jane-doe", "b@example.com",
        "https://github.com/janedoe", "c@example.com", "some notes",
    ]

    @Test func emailFieldListsOnlyEmails() {
        let texts = SmartPasteEngine.panelCandidates(
            input(kind: .email, label: "Email", history: mixed, profile: Profile(linkedin: "https://www.linkedin.com/in/x"))
        ).map(\.text)
        #expect(texts == ["a@example.com", "b@example.com", "c@example.com"])
    }

    @Test func afterJevPanelMatchesItsNote() {
        let inp = input(kind: .email, label: "Email", history: mixed)
        guard case .askJev(let plan) = SmartPasteEngine.decideLocally(inp) else {
            Issue.record("expected Jev for 3 emails"); return
        }
        let answers = JevAnswers(nouls: ["fits_0": 0.6, "fits_1": 0.5, "fits_2": 0.4, "anything_fits": 0.6])
        guard case .showPanel(_, let candidates, let note) = SmartPasteEngine.decide(afterJev: answers, plan: plan, input: inp) else {
            Issue.record("expected panel"); return
        }
        #expect(note == "3 emails copied. Which one?")
        #expect(candidates.map(\.text) == ["a@example.com", "b@example.com", "c@example.com"])
    }

    @Test func nameFieldDropsLinksAndEmails() {
        let texts = SmartPasteEngine.panelCandidates(input(kind: .firstName, label: "First name", history: mixed)).map(\.text)
        #expect(texts == ["some notes"])
    }

    @Test func unknownOrEmptyKindListsEverything() {
        #expect(SmartPasteEngine.panelCandidates(input(kind: .unknown, label: "Notes", history: mixed)).count == mixed.count)
        #expect(SmartPasteEngine.panelCandidates(input(kind: .phone, label: "Phone", history: mixed)).count == mixed.count)
    }
}
