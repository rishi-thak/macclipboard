import Foundation

/// What the focused field asks for, as far as on-device rules can tell.
public enum FieldKind: String, Codable, Sendable, CaseIterable {
    case email
    case phone
    case linkedin
    case github
    case website
    case firstName
    case lastName
    case fullName
    case zip
    case school
    case unknown

    /// How the panel names this kind: "No LinkedIn URL copied yet".
    public var displayName: String {
        switch self {
        case .email: return "email"
        case .phone: return "phone number"
        case .linkedin: return "LinkedIn URL"
        case .github: return "GitHub URL"
        case .website: return "website"
        case .firstName: return "first name"
        case .lastName: return "last name"
        case .fullName: return "name"
        case .zip: return "zip code"
        case .school: return "school"
        case .unknown: return "value"
        }
    }

    /// Clipboard kinds that can fill this field.
    public var itemKinds: Set<ItemKind> {
        switch self {
        case .email: return [.email]
        case .phone: return [.phone]
        case .linkedin: return [.linkedin]
        case .github: return [.github]
        case .website: return [.url]
        case .firstName, .lastName, .fullName, .zip, .school, .unknown: return []
        }
    }
}

/// What we could read about the focused field through Accessibility.
public struct FieldInfo: Sendable, Equatable, Codable {
    public var label: String
    public var placeholder: String
    public var help: String
    /// The web field's id or name attribute, e.g. "first_name" or "urls[LinkedIn]".
    public var identifier: String
    /// Static text just before the field, for forms whose labels aren't linked.
    public var nearbyText: String
    public var pageURL: String
    public var pageTitle: String
    public var appName: String

    public init(label: String = "", placeholder: String = "", help: String = "",
                identifier: String = "", nearbyText: String = "", pageURL: String = "",
                pageTitle: String = "", appName: String = "") {
        self.label = label
        self.placeholder = placeholder
        self.help = help
        self.identifier = identifier
        self.nearbyText = nearbyText
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.appName = appName
    }

    /// True when there's anything a person could use to tell what the field wants.
    public var hasHints: Bool {
        [label, placeholder, help, identifier, nearbyText].contains { !$0.trimmed.isEmpty }
    }
}

public enum FieldClassifier {
    /// Kinds whose words also show up inside longer questions ("What year are you in
    /// school?"), so they only count when the text is short, like a label.
    private static let labelOnly: Set<FieldKind> = [.zip, .school]
    private static let labelMaxWords = 6

    private static let rules: [(kind: FieldKind, pattern: String)] = [
        (.linkedin, #"\blinked ?in\b"#),
        (.github, #"\bgit ?hub\b"#),
        (.email, #"\be ?mail\b"#),
        (.phone, #"\b(phone|mobile|cell|telephone|tel)\b"#),
        (.firstName, #"\b(first|given) ?name\b"#),
        (.lastName, #"\b(last|family|sur) ?name\b"#),
        // "Your name" only as the whole label: "How do you pronounce your name?" isn't a name field.
        (.fullName, #"\b(full|legal|preferred) name\b|^(your |candidate |applicant )?name$"#),
        (.website, #"\b(website|web site|portfolio|personal site|homepage|personal url)\b"#),
        (.zip, #"\b(zip|zip ?code|postal ?code|post ?code|postcode)\b"#),
        (.school, #"\b(school|university|college|institution)\b"#),
    ]

    /// Checks the label first, then the field's id, then nearby text.
    /// Two kinds in the same source ("Website, LinkedIn or GitHub") means unclear.
    public static func classify(_ field: FieldInfo) -> FieldKind {
        let sources = [
            [field.label, field.placeholder, field.help].joined(separator: " "),
            field.identifier,
            field.nearbyText,
        ]
        for source in sources {
            let text = normalize(source)
            guard !text.isEmpty else { continue }
            let isShort = text.split(separator: " ").count <= labelMaxWords
            var kinds = Set(rules.filter { rule in
                (isShort || !labelOnly.contains(rule.kind)) && ItemClassifier.matches(text, rule.pattern)
            }.map(\.kind))
            if kinds.contains(.firstName) || kinds.contains(.lastName) {
                kinds.remove(.fullName)
            }
            // "School email", "University website": the school word only describes the other field.
            if kinds.count > 1 { kinds.remove(.school) }
            if kinds.count == 1, let kind = kinds.first { return kind }
            if kinds.count > 1 { return .unknown }
        }
        let primary = normalize(sources[0] + " " + field.identifier)
        if ItemClassifier.matches(primary, #"\b(urls?|links?)\b"#) { return .website }
        return .unknown
    }

    /// Splits camelCase and punctuation, lowercases, collapses spaces:
    /// "phoneNumber" -> "phone number", "urls[LinkedIn]" -> "urls linked in".
    static func normalize(_ raw: String) -> String {
        var spaced = ""
        var previous: Character?
        for char in raw {
            if char.isUppercase, let prev = previous, prev.isLowercase {
                spaced.append(" ")
            }
            spaced.append(char)
            previous = char
        }
        let separators = CharacterSet(charactersIn: "_-[]().:*?,/|").union(.whitespacesAndNewlines)
        return spaced.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
