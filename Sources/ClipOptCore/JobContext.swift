import Foundation

public enum JobContext: Sendable, Equatable {
    case jobApplication
    case notJobApplication
    case unknown
}

public enum JobSiteDetector {
    /// Applicant-tracking systems that host job applications. Matched as the
    /// host itself or any subdomain of it.
    public static let knownHosts: [String] = [
        "greenhouse.io",
        "lever.co",
        "myworkdayjobs.com",
        "myworkdaysite.com",
        "ashbyhq.com",
        "smartrecruiters.com",
        "icims.com",
        "jobvite.com",
        "workable.com",
        "bamboohr.com",
        "breezy.hr",
        "recruitee.com",
        "teamtailor.com",
        "ats.rippling.com",
        "applytojob.com",
        "jazzhr.com",
        "pinpointhq.com",
        "successfactors.com",
        "taleo.net",
        "dover.com",
        "gem.com",
        "wellfound.com",
    ]

    /// Saved answers are keyed by host + path, so each application page is asked about once.
    public static func pageKey(for urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if url.isFileURL { return "file://" + url.path }
        guard let host = url.host?.lowercased() else { return nil }
        return host + url.path
    }

    public static func context(pageURL: String, savedAnswers: [String: Bool]) -> JobContext {
        guard let url = URL(string: pageURL), url.isFileURL || url.host != nil else {
            // Not a web page (a native app's field): the job question doesn't apply.
            return .notJobApplication
        }
        let host = url.host?.lowercased() ?? ""
        if knownHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .jobApplication
        }
        if let key = pageKey(for: pageURL), let saved = savedAnswers[key] {
            return saved ? .jobApplication : .notJobApplication
        }
        return .unknown
    }
}
