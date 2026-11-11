import Foundation
import Testing
@testable import ClipOptCore

@Suite struct SensitiveFieldTests {
    @Test(arguments: [
        "Portfolio, Video, or Website Password", "Portfolio passcode", "PIN", "Verification code",
        "Security question answer", "Card number", "API key",
    ])
    func neverFilled(_ label: String) {
        let field = FieldInfo(label: label)
        #expect(FieldClassifier.isSensitive(field))
        #expect(FieldClassifier.classify(field) == .unknown)
        #expect(FieldMemory.key(for: field) == nil)
        let plan = FormFiller.planLocally(fields: [field], profile: Profile(website: "https://example.dev"),
                                          memory: FieldMemory())
        #expect(plan.fills.isEmpty && plan.unclear.isEmpty && plan.skipped == [0])
        let input = SmartPasteInput(field: field, fieldKind: .unknown, context: .jobApplication,
                                    profile: Profile(website: "https://example.dev"), history: [])
        guard case .showPanel(_, _, let note) = SmartPasteEngine.decideLocally(input) else {
            Issue.record("expected panel"); return
        }
        #expect(note == "Looks like a password field, so pick one yourself")
    }

    @Test(arguments: ["Portfolio", "Pinterest profile", "Website", "Expected graduation date"])
    func ordinaryFieldsAreNotSensitive(_ label: String) {
        #expect(!FieldClassifier.isSensitive(FieldInfo(label: label)))
    }
}
