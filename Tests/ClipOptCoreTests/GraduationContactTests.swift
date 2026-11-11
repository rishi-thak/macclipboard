import Foundation
import Testing
@testable import ClipOptCore

@Suite struct GraduationContactTests {
    @Test(arguments: [
        ("When are you graduating? Please list the full month and year (e.g. December 2025).", FieldKind.graduation),
        ("Expected graduation date", .graduation),
        ("When do you graduate?", .graduation),
        ("Graduation year", .graduationYear),
        ("Expected graduation month and year", .graduation),
        ("Are you a recent graduate?", .unknown),
        ("How can we reach you?", .email),
        ("Contact information", .email),
        ("Best contact number", .phone),
        ("Email or phone", .unknown),
    ])
    func classifies(_ label: String, _ expected: FieldKind) {
        #expect(FieldClassifier.classify(FieldInfo(label: label)) == expected)
    }

    @Test func yearFieldGetsJustTheYear() {
        let profile = Profile(graduation: "May 2030")
        #expect(profile.value(for: .graduation) == "May 2030")
        #expect(profile.value(for: .graduationYear) == "2030")
        #expect(Profile().value(for: .graduationYear) == nil)
    }
}
