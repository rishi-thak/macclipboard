import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "com.rishi.clipboardopt", category: "app")
    static let paste = Logger(subsystem: "com.rishi.clipboardopt", category: "paste")
    static let watcher = Logger(subsystem: "com.rishi.clipboardopt", category: "watcher")
    static let jev = Logger(subsystem: "com.rishi.clipboardopt", category: "jev")
}

/// ~/Library/Application Support/ClipboardOpt — history, profile, key file, last Jev request.
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClipboardOpt", isDirectory: true)
    }
    static var history: URL { supportDirectory.appendingPathComponent("history.json") }
    static var profile: URL { supportDirectory.appendingPathComponent("profile.json") }
    /// Your picks for questions that aren't profile fields.
    static var answers: URL { supportDirectory.appendingPathComponent("answers.json") }
    static var envFile: URL { supportDirectory.appendingPathComponent(".env") }
    /// The exact body of the most recent Jev request, for checking what was sent.
    static var lastJevRequest: URL { supportDirectory.appendingPathComponent("last-jev-request.json") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    static func writePrivate(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.app.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

/// One line per decision step, no clipboard content: field kind, path taken, Jev scores, timing.
/// ~/Library/Application Support/ClipboardOpt/decisions.log
enum DecisionLog {
    static var url: URL { AppPaths.supportDirectory.appendingPathComponent("decisions.log") }
    private static let maxBytes = 256 * 1024

    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        let path = url.path
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: path))?[.size] as? Int, size > maxBytes {
            try? manager.removeItem(atPath: path)
        }
        if !manager.fileExists(atPath: path) {
            manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
