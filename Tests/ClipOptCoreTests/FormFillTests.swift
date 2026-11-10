import Foundation
import Testing
@testable import ClipOptCore

@Suite struct FormFillTests {
    private let profile = Profile(email: "me@example.com", linkedin: "https://www.linkedin.com/in/jane-doe",
                                  firstName: "Jane", lastName: "Doe", zip: "12345", school: "Example State University")
    private let grad = FieldInfo(placeholder: "Type your response", nearbyText: "When are you graduating?")
    private let why = FieldInfo(nearbyText: "Why do you want to work here?")
    private let blank = FieldInfo()

    private var fields: [FieldInfo] {
        [FieldInfo(label: "First name"), FieldInfo(label: "Email"), FieldInfo(label: "Phone"),
         FieldInfo(label: "Zip Code"), FieldInfo(label: "School"), grad, why, blank]
    }

    @Test func fillsProfileAndSavedAnswersOnly() {
        var memory = FieldMemory()
        memory.remember("May 2027", for: grad)
        let plan = FormFiller.planLocally(fields: fields, profile: profile, memory: memory)
        #expect(plan.fills[0] == Fill(text: "Jane", source: .profile(.firstName)))
        #expect(plan.fills[1] == Fill(text: "me@example.com", source: .profile(.email)))
        #expect(plan.fills[3]?.text == "12345")
        #expect(plan.fills[4]?.text == "Example State University")
        #expect(plan.fills[5] == Fill(text: "May 2027", source: .remembered))
        // Phone isn't in the profile and "why" has no saved answer: ask Jev. Blank field: leave it.
        #expect(plan.unclear == [2, 6])
        #expect(plan.skipped == [7])
    }

    @Test func jevGetsSavedAnswersThenCopiesButNotValuesAlreadyUsed() {
        var memory = FieldMemory()
        memory.remember("May 2027", for: grad)
        memory.remember("Bay Area", for: FieldInfo(label: "Preferred location"), at: Date(timeIntervalSince1970: 0))
        let plan = FormFiller.planLocally(fields: fields, profile: profile, memory: memory)
        let history = ["(415) 555-0134", "line one\nline two", "Jane"].map { ClipItem(text: $0, kind: ItemClassifier.classify($0), copiedAt: Date()) }
        let jevPlan = FormFiller.jevPlan(plan, memory: memory, history: history)
        #expect(jevPlan?.fields == [2, 6])
        // "May 2027" and "Jane" already fill fields; the multi-line copy is skipped.
        #expect(jevPlan?.candidates == ["Bay Area", "(415) 555-0134"])
    }

    @Test func onlyOneClearWinnerFills() {
        let plan = FormJevPlan(fields: [2, 6], candidates: ["Bay Area", "(415) 555-0134"])
        let answers = JevAnswers(nouls: ["f0_c0": 0.05, "f0_c1": 0.93, "f1_c0": 0.72, "f1_c1": 0.71])
        #expect(FormFiller.fills(afterJev: answers, plan: plan) == [2: Fill(text: "(415) 555-0134", source: .jev)])
    }

    @Test func formRequestHasOneStateKeyPerField() throws {
        let plan = FormJevPlan(fields: [2, 6], candidates: ["Bay Area", "(415) 555-0134"])
        let body = try JevRequestBuilder.formBody(fields: fields, plan: plan)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect((state["field_0"] as? [String: String])?["label"] == "Phone")
        #expect((state["field_1"] as? [String: String])?["text_near_field"] == "Why do you want to work here?")
        let questions = try #require(json["questions"] as? [String: [String: String]])
        #expect(questions.count == 4)
        #expect(questions["f1_c0"]?["instructions"] == "Does the user want to paste \"Bay Area\" into `field_1`?")
    }
}
