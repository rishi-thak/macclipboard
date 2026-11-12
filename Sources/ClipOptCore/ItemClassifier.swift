import Foundation

/// What a copied piece of text is, decided on-device at copy time.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case email
    case phone
    case linkedin
    case github
    case twitter
    case url
    case other
}

/// Fast regex tagging so Cmd+Opt+V never waits on it.
public enum ItemClassifier {
    private static let commonTLDs: Set<String> = [
        "com", "dev", "io", "co", "me", "ai", "app", "org", "net", "xyz",
        "site", "page", "so", "us", "edu", "tech", "design", "info", "ca", "uk"
    ]

    public static func classify(_ raw: String) -> ItemKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500, !text.contains("\n") else { return .other }
        let lower = text.lowercased()

        if matches(lower, #"^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$"#) { return .email }
        if matches(lower, #"^(https?://)?([a-z]{2,3}\.)?linkedin\.com/in/[^\s/?#]+/?([?#]\S*)?$"#) { return .linkedin }
        if matches(lower, #"^(https?://)?(www\.)?github\.com/[a-z0-9\-]+(/\S*)?$"#) { return .github }
        if matches(lower, #"^(https?://)?(www\.|mobile\.)?(twitter|x)\.com/[a-z0-9_]+/?([?#]\S*)?$"#) { return .twitter }
        if isPhone(text) { return .phone }
        if isURL(lower) { return .url }
        return .other
    }

    private static func isPhone(_ text: String) -> Bool {
        guard matches(text, #"^\+?[\d\s().\-]+$"#) else { return false }
        let digits = text.filter(\.isNumber).count
        return (10...15).contains(digits)
    }

    private static func isURL(_ lower: String) -> Bool {
        guard !lower.contains(" ") else { return false }
        if matches(lower, #"^https?://[^\s]+\.[^\s]+$"#) { return true }
        if matches(lower, #"^www\.[^\s]+\.[a-z]{2,}(/\S*)?$"#) { return true }
        // Bare domains like example.dev, only for common TLDs so "notes.txt" isn't a URL.
        guard matches(lower, #"^([a-z0-9\-]+\.)+[a-z]{2,}(/\S*)?$"#) else { return false }
        let host = lower.split(separator: "/").first.map(String.init) ?? lower
        guard let tld = host.split(separator: ".").last else { return false }
        return commonTLDs.contains(String(tld))
    }

    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
