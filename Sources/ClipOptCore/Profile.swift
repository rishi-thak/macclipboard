import Foundation

/// Your preset values. Lives in ~/Library/Application Support/ClipboardOpt/profile.json,
/// never in the source code. Empty strings are treated as "not set".
public struct Profile: Codable, Sendable, Equatable {
    public var email: String?
    public var phone: String?
    public var linkedin: String?
    public var github: String?
    public var website: String?
    public var firstName: String?
    public var lastName: String?
    public var fullName: String?
    public var zip: String?
    public var school: String?

    public init(email: String? = nil, phone: String? = nil, linkedin: String? = nil,
                github: String? = nil, website: String? = nil, firstName: String? = nil,
                lastName: String? = nil, fullName: String? = nil, zip: String? = nil, school: String? = nil) {
        self.email = email
        self.phone = phone
        self.linkedin = linkedin
        self.github = github
        self.website = website
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.zip = zip
        self.school = school
    }

    public func value(for kind: FieldKind) -> String? {
        let raw: String?
        switch kind {
        case .email: raw = email
        case .phone: raw = phone
        case .linkedin: raw = linkedin
        case .github: raw = github
        case .website: raw = website
        case .firstName: raw = firstName
        case .lastName: raw = lastName
        case .fullName:
            raw = nonEmpty(fullName) ?? [firstName, lastName].compactMap(nonEmpty).joined(separator: " ")
        case .zip: raw = zip
        case .school: raw = school
        case .unknown: raw = nil
        }
        return nonEmpty(raw)
    }

    public mutating func set(_ value: String, for kind: FieldKind) {
        switch kind {
        case .email: email = value
        case .phone: phone = value
        case .linkedin: linkedin = value
        case .github: github = value
        case .website: website = value
        case .firstName: firstName = value
        case .lastName: lastName = value
        case .fullName: fullName = value
        case .zip: zip = value
        case .school: school = value
        case .unknown: break
        }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Every value that's set, in a fixed order.
    public var entries: [(kind: FieldKind, value: String)] {
        let kinds: [FieldKind] = [.email, .phone, .linkedin, .github, .website, .fullName, .firstName, .lastName,
                                .zip, .school]
        return kinds.compactMap { kind in value(for: kind).map { (kind, $0) } }
    }

    public static func load(from url: URL) -> Profile {
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
            return Profile()
        }
        return profile
    }

    /// Writes an empty template the first time, so there's a file to fill in.
    public static func writeTemplateIfMissing(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let template = Profile(email: "", phone: "", linkedin: "", github: "", website: "",
                               firstName: "", lastName: "", fullName: "", zip: "", school: "")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(template).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}
