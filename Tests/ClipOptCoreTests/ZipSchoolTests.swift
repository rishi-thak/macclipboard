import Foundation
import Testing
@testable import ClipOptCore

@Suite struct ZipSchoolTests {
    @Test(arguments: [
        (FieldInfo(label: "Zip Code"), FieldKind.zip),
        (FieldInfo(label: "Postal code"), .zip),
        (FieldInfo(identifier: "postalCode"), .zip),
        (FieldInfo(label: "School"), .school),
        (FieldInfo(label: "School or University"), .school),
        (FieldInfo(label: "College name"), .school),
        (FieldInfo(label: "School email"), .email),
        (FieldInfo(nearbyText: "What year are you in school? Please include your expected graduation term."), .unknown),
    ])
    func classifies(_ field: FieldInfo, _ expected: FieldKind) {
        #expect(FieldClassifier.classify(field) == expected)
    }

    @Test func profileValuesPasteDirectly() {
        let profile = Profile(zip: "12345", school: "Example State University")
        for (label, kind, value) in [("Zip", FieldKind.zip, "12345"), ("School", .school, "Example State University")] {
            let input = SmartPasteInput(field: FieldInfo(label: label), fieldKind: kind, context: .notJobApplication,
                                        profile: profile, history: [])
            #expect(SmartPasteEngine.decideLocally(input) == .paste(Candidate(text: value, source: .profile(kind))))
        }
    }

    @Test func oldProfileFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("old-profile-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"email":"me@example.com"}"#.utf8).write(to: url)
        let profile = Profile.load(from: url)
        #expect(profile.email == "me@example.com")
        #expect(profile.value(for: .zip) == nil)
    }
}
