import Foundation
import Testing
@testable import ClipOptCore

@Suite struct HistorySectionTests {
    private let profile = Profile(email: "me@example.com", zip: "62701", school: "Example State University",
                                  street: "1 Example St", city: "Springfield", state: "IL")

    @Test(arguments: ["Work experience", "Work Experience 2", "Employment history", "Education", "References",
                      "Experience"])
    func historyHeadings(_ heading: String) {
        #expect(FieldInfo(section: heading).isInHistorySection)
    }

    @Test(arguments: ["", "Personal information", "Apply: Experience Designer Internship", "Contact",
                      "Software Engineer Intern, Summer 2027"])
    func otherHeadings(_ heading: String) {
        #expect(!FieldInfo(section: heading).isInHistorySection)
    }

    @Test func pastJobLocationIsNotYourHome() {
        let job = FieldInfo(label: "Location", section: "Work experience")
        #expect(FieldClassifier.classify(job) == .unknown)
        #expect(FieldClassifier.classify(FieldInfo(label: "Location", section: "Personal information")) == .location)
        #expect(FieldMemory.key(for: FieldInfo(label: "Description", section: "Work experience")) == nil)
    }

    @Test func formFillSkipsPastJobFieldsButKeepsSchool() {
        let fields = [
            FieldInfo(label: "Location", section: "Personal information"),
            FieldInfo(label: "Job Title", section: "Work experience"),
            FieldInfo(label: "Location", section: "Work experience"),
            FieldInfo(label: "School", section: "Education"),
            FieldInfo(label: "Email", section: "Work experience"),
        ]
        let plan = FormFiller.planLocally(fields: fields, profile: profile, memory: FieldMemory())
        #expect(plan.fills.mapValues(\.text) == [0: "Springfield, IL", 3: "Example State University", 4: "me@example.com"])
        #expect(plan.skipped == [1, 2])
        #expect(plan.unclear.isEmpty)
    }
}
