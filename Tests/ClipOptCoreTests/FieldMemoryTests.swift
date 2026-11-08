import Foundation
import Testing
@testable import ClipOptCore

@Suite struct FieldMemoryTests {
    private let grad = FieldInfo(placeholder: "Type your response",
                                 nearbyText: "When are you graduating? Please list the full month and year (e.g. December 2025). ✱")

    @Test func keyUsesTheQuestionNotTheGenericPlaceholder() {
        #expect(FieldMemory.key(for: grad)?.hasPrefix("when are you graduating") == true)
        #expect(FieldMemory.key(for: FieldInfo(placeholder: "Type your response")) == nil)
        #expect(FieldMemory.key(for: FieldInfo()) == nil)
    }

    @Test func rememberedAnswerPastesWithoutJev() throws {
        var memory = FieldMemory()
        memory.remember("May 2027", for: grad)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("answers-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try memory.save(to: url)

        // Same question on another site, different spacing and punctuation.
        let elsewhere = FieldInfo(label: "When are you graduating?  Please list the full month and year (e.g. December 2025)")
        #expect(FieldMemory.key(for: elsewhere) == FieldMemory.key(for: grad))
        let input = SmartPasteInput(field: grad, fieldKind: .unknown, context: .jobApplication, profile: Profile(),
                                    history: [], remembered: FieldMemory.load(from: url).answer(for: grad))
        #expect(SmartPasteEngine.decideLocally(input) == .paste(Candidate(text: "May 2027", source: .remembered)))
    }

    @Test func oneClearWinnerPastesEvenIfAnythingFitsIsBorderline() {
        let items = ["May 2027", "Software engineer"].map { ClipItem(text: $0, kind: .other, copiedAt: Date()) }
        let input = SmartPasteInput(field: grad, fieldKind: .unknown, context: .jobApplication,
                                    profile: Profile(), history: items)
        guard case .askJev(let plan) = SmartPasteEngine.decideLocally(input) else { Issue.record("expected Jev"); return }
        let answers = JevAnswers(nouls: ["fits_0": 0.76, "fits_1": 0.10, "anything_fits": 0.68])
        guard case .paste(let candidate) = SmartPasteEngine.decide(afterJev: answers, plan: plan, input: input) else {
            Issue.record("expected paste"); return
        }
        #expect(candidate.text == "May 2027")
    }
}
