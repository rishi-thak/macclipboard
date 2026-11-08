import Foundation
import Testing
@testable import ClipOptCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let profile = Profile(email: "me@example.com", linkedin: "linkedin.com/in/janedoe")

private func item(_ text: String, secondsAgo: TimeInterval) -> ClipItem {
    ClipItem(text: text, kind: ItemClassifier.classify(text), copiedAt: now.addingTimeInterval(-secondsAgo))
}

private func input(_ field: FieldInfo, context: JobContext, history: [ClipItem], profile: Profile = profile) -> SmartPasteInput {
    SmartPasteInput(field: field, fieldKind: FieldClassifier.classify(field), context: context,
                    profile: profile, history: history, now: now)
}

@Suite struct SmartPasteEngineTests {
    @Test func jobApplicationUsesProfileOverClipboard() {
        let decision = SmartPasteEngine.decideLocally(input(
            FieldInfo(label: "Email"), context: .jobApplication,
            history: [item("work@company.com", secondsAgo: 600)]))
        #expect(decision == .paste(Candidate(text: "me@example.com", source: .profile(.email))))
    }

    @Test func freshCopyBeatsProfile() {
        let fresh = item("other@school.edu", secondsAgo: 5)
        let decision = SmartPasteEngine.decideLocally(input(FieldInfo(label: "Email"), context: .jobApplication, history: [fresh]))
        #expect(decision == .paste(Candidate(text: fresh.text, source: .history(fresh.id), copiedAt: fresh.copiedAt)))
    }

    @Test func singleMatchPastesWithoutJev() {
        let phone = item("415 555 0134", secondsAgo: 600)
        let decision = SmartPasteEngine.decideLocally(input(
            FieldInfo(label: "Phone"), context: .notJobApplication,
            history: [phone, item("hello", secondsAgo: 10)]))
        #expect(decision == .paste(Candidate(text: phone.text, source: .history(phone.id), copiedAt: phone.copiedAt)))
    }

    @Test func severalMatchesAskJev() {
        let decision = SmartPasteEngine.decideLocally(input(
            FieldInfo(label: "Email"), context: .unknown,
            history: [item("work@company.com", secondsAgo: 600)]))
        guard case .askJev(let plan) = decision else {
            Issue.record("expected askJev, got \(decision)")
            return
        }
        #expect(plan.candidates.map(\.text) == ["work@company.com", "me@example.com"])
        #expect(plan.askJobQuestion)
    }

    @Test func unclearLabelAsksJevWithEverything() {
        let decision = SmartPasteEngine.decideLocally(input(
            FieldInfo(label: "How can we reach you?"), context: .jobApplication,
            history: [item("hello", secondsAgo: 60)]))
        guard case .askJev(let plan) = decision else {
            Issue.record("expected askJev, got \(decision)")
            return
        }
        #expect(plan.candidates.map(\.text) == ["hello", "me@example.com", "linkedin.com/in/janedoe"])
        #expect(!plan.askJobQuestion)
    }

    @Test func fieldWithNoHintsShowsPanel() {
        let decision = SmartPasteEngine.decideLocally(input(FieldInfo(), context: .unknown, history: [item("x", secondsAgo: 1)]))
        guard case .showPanel(nil, _, _) = decision else {
            Issue.record("expected panel, got \(decision)")
            return
        }
    }

    @Test func knownKindWithNothingMatchingShowsPanel() {
        let decision = SmartPasteEngine.decideLocally(input(
            FieldInfo(label: "Phone"), context: .jobApplication,
            history: [item("hello", secondsAgo: 60)]))
        guard case .showPanel(nil, _, _) = decision else {
            Issue.record("expected panel, got \(decision)")
            return
        }
    }

    // MARK: After Jev

    private let plan = JevPlan(candidates: [
        Candidate(text: "a@x.com", source: .profile(.email)),
        Candidate(text: "b@y.com", source: .profile(.email)),
    ], askJobQuestion: false)

    private func answers(_ fits: [Double], anything: Double, job: Double? = nil) -> JevAnswers {
        var nouls = [JevQuestions.ID.anythingFits: anything]
        for (i, value) in fits.enumerated() { nouls[JevQuestions.ID.fits(i)] = value }
        if let job { nouls[JevQuestions.ID.isJobApplication] = job }
        return JevAnswers(nouls: nouls)
    }

    private var emailInput: SmartPasteInput {
        input(FieldInfo(label: "Contact email"), context: .unknown, history: [])
    }

    @Test func oneClearWinnerPastes() {
        let decision = SmartPasteEngine.decide(afterJev: answers([0.9, 0.2], anything: 0.95), plan: plan, input: emailInput)
        #expect(decision == .paste(plan.candidates[0]))
    }

    @Test func twoWinnersShowPanelWithBestFirst() {
        let decision = SmartPasteEngine.decide(afterJev: answers([0.75, 0.85], anything: 0.95), plan: plan, input: emailInput)
        guard case .showPanel(let highlight, _, _) = decision else {
            Issue.record("expected panel, got \(decision)")
            return
        }
        #expect(highlight == plan.candidates[1])
    }

    @Test func oneWinnerPastesEvenWhenAnythingFitsIsUnsettled() {
        let decision = SmartPasteEngine.decide(afterJev: answers([0.9, 0.1], anything: 0.5), plan: plan, input: emailInput)
        #expect(decision == .paste(plan.candidates[0]))
    }

    @Test func noWinnerShowsPanelWithBestGuess() {
        let decision = SmartPasteEngine.decide(afterJev: answers([0.6, 0.1], anything: 0.5), plan: plan, input: emailInput)
        guard case .showPanel(let highlight, _, _) = decision else {
            Issue.record("expected panel, got \(decision)")
            return
        }
        #expect(highlight == plan.candidates[0])
    }

    @Test func nothingFitsShowsPanelWithoutHighlight() {
        let decision = SmartPasteEngine.decide(afterJev: answers([0.9, 0.1], anything: 0.1), plan: plan, input: emailInput)
        guard case .showPanel(nil, _, let note) = decision else {
            Issue.record("expected panel, got \(decision)")
            return
        }
        #expect(note != nil)
    }

    @Test func jobAnswerSwitchesToProfile() {
        let jobPlan = JevPlan(candidates: plan.candidates, askJobQuestion: true)
        let decision = SmartPasteEngine.decide(afterJev: answers([0.5, 0.5], anything: 0.9, job: 0.92), plan: jobPlan, input: emailInput)
        #expect(decision == .paste(Candidate(text: "me@example.com", source: .profile(.email))))
    }
}

@Suite struct JevRequestTests {
    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func buildsOneQuestionPerCandidate() throws {
        let field = FieldInfo(label: "Where can we see your work?", placeholder: "https://",
                              pageURL: "https://acme.com/careers/apply", pageTitle: "Apply · Acme")
        let plan = JevPlan(candidates: [
            Candidate(text: "github.com/janedoe", source: .profile(.github)),
            Candidate(text: "https://example.dev", source: .history(UUID())),
        ], askJobQuestion: true)
        let body = try json(JevRequestBuilder.body(field: field, plan: plan))

        #expect(body["model"] as? String == "jev-latest")
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["candidates"] as? [String] == ["github.com/janedoe", "https://example.dev"])
        let fieldState = try #require(state["field"] as? [String: String])
        #expect(fieldState == ["label": "Where can we see your work?", "placeholder": "https://"])
        #expect((state["page"] as? [String: String])?["url"] == "https://acme.com/careers/apply")

        let questions = try #require(body["questions"] as? [String: [String: String]])
        #expect(Set(questions.keys) == ["fits_0", "fits_1", "anything_fits", "is_job_application"])
        #expect(questions["fits_1"]?["instructions"] == "Does the user want to paste \"https://example.dev\" into `field`?")
        #expect(questions.values.allSatisfy { $0["type"] == "noul" })
    }

    @Test func skipsJobQuestionWithoutAPage() throws {
        let plan = JevPlan(candidates: [Candidate(text: "x", source: .history(UUID()))], askJobQuestion: true)
        let body = try json(JevRequestBuilder.body(field: FieldInfo(label: "Notes", appName: "Notes"), plan: plan))
        let questions = try #require(body["questions"] as? [String: Any])
        #expect(questions["is_job_application"] == nil)
        #expect((body["state"] as? [String: Any])?["app"] as? String == "Notes")
    }

    @Test func clipsLongValues() {
        let long = String(repeating: "a", count: 1000)
        #expect(JevRequestBuilder.clip(long).count == JevQuestions.maxValueLength + 1)
    }

    @Test func decodesResponse() throws {
        let data = Data(#"{"model":"jev-1.14.0","answers":{"fits_0":{"type":"noul","noul":0.91},"anything_fits":{"type":"noul","noul":0.97}},"usage":{"input_tokens":180,"output_tokens":4}}"#.utf8)
        let answers = JevAnswers(try JSONDecoder().decode(JevResponse.self, from: data))
        #expect(answers.noul("fits_0") == 0.91)
        #expect(answers.noul("anything_fits") == 0.97)
    }
}

@Suite struct APIKeyLoaderTests {
    @Test func parsesEnvFiles() {
        #expect(APIKeyLoader.parse("JEV_API_KEY=abc123") == "abc123")
        #expect(APIKeyLoader.parse("# comment\nexport JEV_API_KEY=\"quoted\"\n") == "quoted")
        #expect(APIKeyLoader.parse("TYPESAFE_API_KEY='single'") == "single")
        #expect(APIKeyLoader.parse("OTHER=1\nJEV_API_KEY=") == nil)
    }

    @Test func environmentWins() {
        #expect(APIKeyLoader.load(environment: ["JEV_API_KEY": "env"], envFiles: []) == "env")
        #expect(APIKeyLoader.load(environment: [:], envFiles: []) == nil)
    }
}
