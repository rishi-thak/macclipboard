import Foundation
import Testing
@testable import ClipOptCore

@Suite struct TwitterLocationTests {
    @Test(arguments: [
        ("https://x.com/janedoe", ItemKind.twitter), ("twitter.com/janedoe", .twitter),
        ("https://www.x.com/janedoe?s=21", .twitter), ("https://example.dev", .url),
    ])
    func classifiesCopies(_ text: String, _ expected: ItemKind) {
        #expect(ItemClassifier.classify(text) == expected)
    }

    @Test(arguments: [
        ("Twitter", FieldKind.twitter), ("X (formerly Twitter)", .twitter), ("X", .twitter), ("X profile", .twitter),
        ("X.com URL", .twitter), ("LinkedIn, Twitter or Website", .linkedin), ("Box", .unknown),
        ("Any extra info?", .unknown),
    ])
    func classifiesFields(_ label: String, _ expected: FieldKind) {
        #expect(FieldClassifier.classify(FieldInfo(label: label)) == expected)
    }

    @Test func currentLocationCanDifferFromHome() {
        let home = Profile(zip: "62701", street: "1 Example St", city: "Springfield", state: "IL")
        #expect(home.value(for: .location) == "Springfield, IL")
        var moved = home
        moved.location = "Chicago, IL, USA"
        #expect(moved.value(for: .location) == "Chicago, IL, USA")
        #expect(moved.value(for: .city) == "Springfield")
        #expect(moved.value(for: .address) == "1 Example St, Springfield IL 62701")
        #expect(FieldClassifier.classify(FieldInfo(label: "Current location")) == .location)
    }
}
