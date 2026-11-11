import Foundation
import Testing
@testable import ClipOptCore

@Suite struct SavedFirstTests {
    @Test func unsurePanelListsSavedValuesFirstByScore() {
        let copies = ["some notes", "https://example.dev", "https://other.example/page"]
            .map { ClipItem(text: $0, kind: ItemClassifier.classify($0), copiedAt: Date()) }
        let input = SmartPasteInput(field: FieldInfo(label: "Anything we should look at?"), fieldKind: .unknown,
                                    context: .jobApplication, profile: Profile(email: "me@example.com",
                                    github: "https://github.com/janedoe", website: "https://example.dev"),
                                    history: copies)
        guard case .askJev(let plan) = SmartPasteEngine.decideLocally(input) else { Issue.record("expected Jev"); return }
        var nouls: [String: Double] = [:]
        for (index, candidate) in plan.candidates.enumerated() {
            nouls[JevQuestions.ID.fits(index)] = ["https://github.com/janedoe": 0.6, "https://example.dev": 0.65][candidate.text] ?? 0.1
        }
        nouls[JevQuestions.ID.anythingFits] = 0.6
        guard case .showPanel(let highlight, let candidates, _) =
                SmartPasteEngine.decide(afterJev: JevAnswers(nouls: nouls), plan: plan, input: input) else {
            Issue.record("expected panel"); return
        }
        #expect(highlight?.text == "https://example.dev")
        // Saved values first, best score first; the copied website shows as saved, not twice.
        #expect(candidates.map(\.text) == ["https://example.dev", "https://github.com/janedoe", "me@example.com",
                                           "some notes", "https://other.example/page"])
        #expect(candidates[0].source == .profile(.website))
    }
}
