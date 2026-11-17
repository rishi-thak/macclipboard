import Foundation
import Testing
@testable import ClipOptCore

@Suite struct MajorTests {
    @Test(arguments: [
        ("What is your field of study/degree program?", FieldKind.major), ("Major", .major),
        ("Field of Study", .major), ("Area of study", .major), ("Concentration", .major),
        ("Degree", .unknown), ("What degree are you pursuing?", .unknown), ("Minor", .unknown),
    ])
    func classifies(_ label: String, _ expected: FieldKind) {
        #expect(FieldClassifier.classify(FieldInfo(label: label)) == expected)
    }

    @Test func fillsFromProfileEvenInEducation() {
        let field = FieldInfo(label: "Field of study", section: "Education")
        let plan = FormFiller.planLocally(fields: [field], profile: Profile(major: "Example Studies"), memory: FieldMemory())
        #expect(plan.fills[0] == Fill(text: "Example Studies", source: .profile(.major)))
    }
}
