import Foundation
import Testing
@testable import ClipOptCore

@Suite struct LearningTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func linkedinInput(profile: Profile) -> SmartPasteInput {
        let items = ["https://www.linkedin.com/in/jane-doe", "https://www.linkedin.com/in/someone-else"].map {
            ClipItem(text: $0, kind: ItemClassifier.classify($0), copiedAt: now.addingTimeInterval(-600))
        }
        return SmartPasteInput(field: FieldInfo(label: "LinkedIn Profile URL"), fieldKind: .linkedin,
                               context: .unknown, profile: profile, history: items, now: now)
    }

    @Test func blankProfileFieldIsLearnable() {
        #expect(SmartPasteEngine.learnableKind(linkedinInput(profile: Profile())) == .linkedin)
        #expect(SmartPasteEngine.learnableKind(linkedinInput(profile: Profile(linkedin: "linkedin.com/in/x"))) == nil)
    }

    @Test func onlyMatchingPicksAreSaved() {
        #expect(SmartPasteEngine.pickFits("https://www.linkedin.com/in/jane-doe", kind: .linkedin))
        #expect(!SmartPasteEngine.pickFits("me@example.com", kind: .linkedin))
        #expect(SmartPasteEngine.pickFits("Jane", kind: .firstName))
        #expect(!SmartPasteEngine.pickFits("https://example.dev", kind: .firstName))
        #expect(!SmartPasteEngine.pickFits("line one\nline two", kind: .fullName))
    }

    @Test func savedPickFillsNextTimeWithoutPanel() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var profile = Profile()
        profile.set("https://www.linkedin.com/in/jane-doe", for: .linkedin)
        try profile.save(to: url)

        var input = linkedinInput(profile: Profile.load(from: url))
        input.context = .jobApplication
        #expect(SmartPasteEngine.decideLocally(input)
                == .paste(Candidate(text: "https://www.linkedin.com/in/jane-doe", source: .profile(.linkedin))))
    }

    @Test func unsurePanelSaysWhy() {
        let input = linkedinInput(profile: Profile())
        guard case .askJev(let plan) = SmartPasteEngine.decideLocally(input) else {
            Issue.record("expected askJev")
            return
        }
        let answers = JevAnswers(nouls: ["fits_0": 0.71, "fits_1": 0.39, "anything_fits": 0.67])
        guard case .showPanel(let highlight, _, let note) = SmartPasteEngine.decide(afterJev: answers, plan: plan, input: input) else {
            Issue.record("expected panel")
            return
        }
        #expect(highlight?.text == "https://www.linkedin.com/in/jane-doe")
        #expect(note == "2 LinkedIn URLs copied. Which one?")
    }

    @Test func localTestPagesGetTheJobQuestion() {
        let url = "file:///Users/me/testpage/index.html"
        #expect(JobSiteDetector.context(pageURL: url, savedAnswers: [:]) == .unknown)
        #expect(JobSiteDetector.pageKey(for: url) == "file:///Users/me/testpage/index.html")
    }
}

@Suite struct CorrectionTests {
    @Test func knownFieldsCanBeCorrectedEvenWhenSaved() {
        let input = SmartPasteInput(field: FieldInfo(label: "LinkedIn"), fieldKind: .linkedin, context: .jobApplication,
                                    profile: Profile(linkedin: "https://www.linkedin.com/in/someone-else"), history: [])
        #expect(SmartPasteEngine.learnableKind(input) == nil)
        #expect(SmartPasteEngine.correctableKind(input) == .linkedin)
        var unknown = input
        unknown.fieldKind = .unknown
        #expect(SmartPasteEngine.correctableKind(unknown) == nil)
    }
}
