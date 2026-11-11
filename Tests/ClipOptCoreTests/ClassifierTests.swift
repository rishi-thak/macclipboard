import Testing
@testable import ClipOptCore

@Suite struct ItemClassifierTests {
    @Test(arguments: [
        ("me@example.com", ItemKind.email),
        ("  someone+jobs@company.co.uk \n", .email),
        ("https://www.linkedin.com/in/jane-doe/", .linkedin),
        ("linkedin.com/in/janedoe?utm_source=share", .linkedin),
        ("github.com/janedoe", .github),
        ("https://github.com/janedoe/clipboardopt", .github),
        ("(415) 555-0134", .phone),
        ("+1 415 555 0134", .phone),
        ("4155550134", .phone),
        ("https://example.dev", .url),
        ("example.dev", .url),
        ("www.example.org/about", .url),
        ("notes.txt", .other),
        ("2026-11-02", .other),
        ("Hello there", .other),
        ("line one\nline two", .other),
    ])
    func classifiesCopies(text: String, expected: ItemKind) {
        #expect(ItemClassifier.classify(text) == expected)
    }
}

@Suite struct FieldClassifierTests {
    @Test(arguments: [
        (FieldInfo(label: "Email *"), FieldKind.email),
        (FieldInfo(label: "E-mail address"), .email),
        (FieldInfo(label: "LinkedIn Profile URL"), .linkedin),
        (FieldInfo(label: "GitHub"), .github),
        (FieldInfo(label: "Phone"), .phone),
        (FieldInfo(identifier: "phoneNumber"), .phone),
        (FieldInfo(identifier: "first_name"), .firstName),
        (FieldInfo(label: "Last Name"), .lastName),
        (FieldInfo(label: "Name"), .fullName),
        (FieldInfo(label: "Portfolio"), .website),
        (FieldInfo(identifier: "urls[LinkedIn]"), .linkedin),
        (FieldInfo(identifier: "urls[Other]"), .website),
        (FieldInfo(label: "Website, LinkedIn or GitHub"), .linkedin),
        (FieldInfo(label: "Portfolio or LinkedIn"), .linkedin),
        (FieldInfo(label: "Where can we see your work?", placeholder: "https://"), .website),
        (FieldInfo(label: "Anything we should see?", placeholder: "https://"), .website),
        (FieldInfo(label: "Website or GitHub"), .website),
        (FieldInfo(label: "Website link (github, portfolio, other)", help: "If applicable"), .website),
        (FieldInfo(label: "How can we reach you?"), .email),
        (FieldInfo(nearbyText: "Mobile number"), .phone),
        (FieldInfo(), .unknown),
    ])
    func classifiesFields(field: FieldInfo, expected: FieldKind) {
        #expect(FieldClassifier.classify(field) == expected)
    }

    @Test func labelBeatsNearbyText() {
        let field = FieldInfo(label: "Email", nearbyText: "Phone")
        #expect(FieldClassifier.classify(field) == .email)
    }
}

@Suite struct JobSiteDetectorTests {
    @Test func knownJobSitesNeedNoNetwork() {
        let urls = [
            "https://boards.greenhouse.io/acme/jobs/123",
            "https://jobs.lever.co/acme/abc/apply",
            "https://acme.wd5.myworkdayjobs.com/en-US/careers/job/1",
            "https://jobs.ashbyhq.com/acme/1/application",
        ]
        for url in urls {
            #expect(JobSiteDetector.context(pageURL: url, savedAnswers: [:]) == .jobApplication)
        }
    }

    @Test func otherPagesUseSavedAnswers() {
        let url = "https://acme.com/careers/apply?ref=x"
        #expect(JobSiteDetector.context(pageURL: url, savedAnswers: [:]) == .unknown)
        let key = JobSiteDetector.pageKey(for: url)!
        #expect(key == "acme.com/careers/apply")
        #expect(JobSiteDetector.context(pageURL: url, savedAnswers: [key: true]) == .jobApplication)
        #expect(JobSiteDetector.context(pageURL: url, savedAnswers: [key: false]) == .notJobApplication)
    }

    @Test func lookalikeHostsDontMatch() {
        #expect(JobSiteDetector.context(pageURL: "https://notgreenhouse.io/x", savedAnswers: [:]) == .unknown)
    }

    @Test func nativeAppFieldsAreNotJobApplications() {
        #expect(JobSiteDetector.context(pageURL: "", savedAnswers: [:]) == .notJobApplication)
    }
}
