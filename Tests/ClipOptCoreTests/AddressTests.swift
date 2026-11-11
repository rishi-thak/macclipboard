import Foundation
import Testing
@testable import ClipOptCore

@Suite struct AddressTests {
    private let profile = Profile(zip: "62701", street: "1 Example St", city: "Springfield", state: "IL")

    @Test(arguments: [
        ("Legal Address", FieldKind.address), ("Address", .address), ("Mailing address", .address),
        ("Please provide your current home address", .address),
        ("Street address", .street), ("Address line 1", .street),
        ("Address line 2", .unknown), ("Apt / Suite", .unknown),
        ("Email address", .email), ("E-mail Address", .email), ("Web address", .unknown),
        ("City", .city), ("State", .state), ("State/Province", .state),
        ("City, State", .location), ("Location", .location), ("Current location", .location),
        ("Preferred location", .unknown), ("Office location", .unknown),
        ("Are you legally authorized to work in the United States?", .unknown),
    ])
    func classifies(_ label: String, _ expected: FieldKind) {
        #expect(FieldClassifier.classify(FieldInfo(label: label)) == expected)
    }

    @Test func addressIsBuiltFromParts() {
        #expect(profile.value(for: .address) == "1 Example St, Springfield IL 62701")
        #expect(profile.value(for: .street) == "1 Example St")
        #expect(profile.value(for: .location) == "Springfield, IL")
        #expect(Profile(city: "Springfield").value(for: .address) == nil)
    }

    @Test func formFillUsesEachPart() {
        let fields = ["Legal Address", "City", "State", "Zip Code"].map { FieldInfo(label: $0) }
        let plan = FormFiller.planLocally(fields: fields, profile: profile, memory: FieldMemory())
        #expect(plan.fills.mapValues(\.text) == [0: "1 Example St, Springfield IL 62701", 1: "Springfield", 2: "IL", 3: "62701"])
    }
}
