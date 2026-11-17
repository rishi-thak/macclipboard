import Foundation
import Testing
@testable import ClipOptCore

@Suite struct MajorTests {
    @Test(arguments: [
        ("What is your field of study/degree program?", FieldKind.major), ("Major", .major),
        ("Field of Study", .major), ("Area of study", .major), ("Concentration", .major),
        ("Degree", .degree), ("What degree are you pursuing?", .degree), ("Degree type", .degreeLevel),
        ("Highest level of education", .degreeLevel), ("Minor", .minor), ("Minor (if applicable)", .minor),
        ("Are you a minor?", .unknown), ("Are you under 18 years of age?", .unknown),
        ("Do you have a bachelor's degree?", .unknown),
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

@Suite struct DegreeTests {
    @Test func levelFallsBackToFullDegree() {
        #expect(Profile(degree: "Bachelor of Arts").value(for: .degreeLevel) == "Bachelor of Arts")
        #expect(Profile(degree: "Bachelor of Arts", degreeLevel: "Bachelor").value(for: .degreeLevel) == "Bachelor")
    }
}
