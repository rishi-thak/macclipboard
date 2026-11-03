import Foundation

/// All Jev question wording, thresholds and model choice, in one place to audit and tune.
public enum JevQuestions {
    public static let model = "jev-latest"
    public static let yesThreshold = 0.7
    public static let noThreshold = 0.3
    public static let maxValueLength = 300

    public enum ID {
        public static func fits(_ index: Int) -> String { "fits_\(index)" }
        public static let anythingFits = "anything_fits"
        public static let isJobApplication = "is_job_application"
    }

    static func fits(_ value: String) -> String {
        "Does the user want to paste \"\(value)\" into `field`?"
    }
    static let anythingFits = "Does the user want to paste any value in `candidates` into `field`?"
    static let isJobApplication = "Is `page` a job application form?"
}

public enum JevRequestBuilder {
    /// Builds the exact JSON body for one smart-paste request.
    public static func body(field: FieldInfo, plan: JevPlan, model: String = JevQuestions.model) throws -> Data {
        var fieldState: [String: String] = [:]
        put(&fieldState, "label", field.label)
        put(&fieldState, "placeholder", field.placeholder)
        put(&fieldState, "help_text", field.help)
        put(&fieldState, "html_id", field.identifier)
        put(&fieldState, "text_near_field", field.nearbyText)

        var page: [String: String] = [:]
        put(&page, "url", field.pageURL)
        put(&page, "title", field.pageTitle)

        let values = plan.candidates.map { clip($0.text) }
        var state: [String: Any] = ["field": fieldState, "candidates": values]
        if !page.isEmpty {
            state["page"] = page
        } else if !field.appName.trimmed.isEmpty {
            state["app"] = field.appName
        }

        var questions: [String: Any] = [:]
        for (index, value) in values.enumerated() {
            questions[JevQuestions.ID.fits(index)] = ["type": "noul", "instructions": JevQuestions.fits(value)]
        }
        questions[JevQuestions.ID.anythingFits] = ["type": "noul", "instructions": JevQuestions.anythingFits]
        if plan.askJobQuestion, !page.isEmpty {
            questions[JevQuestions.ID.isJobApplication] = ["type": "noul", "instructions": JevQuestions.isJobApplication]
        }

        let body: [String: Any] = ["model": model, "state": state, "questions": questions]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func put(_ dict: inout [String: String], _ key: String, _ value: String) {
        let text = value.trimmed
        if !text.isEmpty { dict[key] = String(text.prefix(JevQuestions.maxValueLength)) }
    }

    static func clip(_ text: String) -> String {
        let flat = text.trimmed
        guard flat.count > JevQuestions.maxValueLength else { return flat }
        return String(flat.prefix(JevQuestions.maxValueLength)) + "…"
    }
}

// MARK: - Response

public struct JevResponse: Decodable, Sendable {
    public struct Answer: Decodable, Sendable {
        public let type: String
        public let noul: Double?
    }
    public struct Usage: Decodable, Sendable {
        public let input_tokens: Int?
        public let output_tokens: Int?
    }

    public let model: String
    public let answers: [String: Answer]
    public let usage: Usage?
}

public struct JevAnswers: Sendable, Equatable {
    public var nouls: [String: Double]

    public init(nouls: [String: Double]) {
        self.nouls = nouls
    }

    public init(_ response: JevResponse) {
        self.nouls = response.answers.compactMapValues(\.noul)
    }

    public func noul(_ id: String) -> Double? { nouls[id] }
}

// MARK: - Client

public enum JevError: Error, Sendable, CustomStringConvertible {
    case badResponse
    case http(status: Int, message: String)

    public var description: String {
        switch self {
        case .badResponse: return "Jev sent an unreadable response"
        case .http(let status, let message):
            switch status {
            case 401: return "Jev rejected the API key (401)"
            case 429: return "Jev rate limit hit (429)"
            default: return "Jev error \(status): \(message)"
            }
        }
    }
}

public struct JevClient: Sendable {
    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    public let apiKey: String
    public let timeout: TimeInterval

    public init(apiKey: String, timeout: TimeInterval = 3) {
        self.apiKey = apiKey
        self.timeout = timeout
    }

    public func ask(_ body: Data) async throws -> JevResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JevError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(300), as: UTF8.self)
            throw JevError.http(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(JevResponse.self, from: data)
        } catch {
            throw JevError.badResponse
        }
    }
}

// MARK: - API key

public enum APIKeyLoader {
    public static let keyNames = ["JEV_API_KEY", "TYPESAFE_API_KEY"]

    /// Environment first, then each .env file in order.
    public static func load(environment: [String: String], envFiles: [URL]) -> String? {
        for name in keyNames {
            if let value = environment[name]?.trimmed, !value.isEmpty { return value }
        }
        for file in envFiles {
            if let text = try? String(contentsOf: file, encoding: .utf8), let value = parse(text) {
                return value
            }
        }
        return nil
    }

    public static func parse(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).trimmed
            guard !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmed }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmed
            guard keyNames.contains(key) else { continue }
            var value = String(line[line.index(after: equals)...]).trimmed
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { return value }
        }
        return nil
    }
}
