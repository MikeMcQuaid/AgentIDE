import Foundation

/// A plain-text record of what the app waits on: every process it
/// runs, every network call, and whether each cache read hit or
/// missed, one line each with how long it took. Off unless asked
/// for, so a build of the app by anyone else writes nothing anywhere:
/// it is on when the `AGENTIDE_PERFORMANCE_LOG` variable is set or a
/// `performance-log` marker file sits in the log's own directory,
/// which is how the installed build is switched on without
/// rebuilding. The file lives in a temporary directory both the
/// host user and the sandbox user can read, since either may be the
/// one reading it back. Lines older than a day are swept on the next
/// write, and once the file passes a hundred megabytes its oldest
/// half goes, so a busy day cannot fill the disk between sweeps.
public enum PerformanceLog {
    // MARK: Public

    /// How the app came to be waiting. Not raw-value backed: the
    /// formatter strips a raw value equal to its case name while the
    /// linter demands one, so the log's word is spelt out here.
    public enum Kind: Sendable {
        case process
        case network
        case cacheHit
        case cacheMiss

        // MARK: Internal

        var label: String {
            switch self {
            case .process:
                "process"

            case .network:
                "network"

            case .cacheHit:
                "cache-hit"

            case .cacheMiss:
                "cache-miss"
            }
        }
    }

    /// How long a line is kept: a day.
    public static let lifetime: TimeInterval = 86_400

    /// The size the file is trimmed at: a hundred megabytes, which a
    /// day of heavy use reaches between sweeps.
    public static let sizeCap = 104_857_600

    /// What it is trimmed back to: fifty megabytes, so the oldest
    /// half goes rather than the whole day at once.
    public static let sizeFloor = 52_428_800

    /// Whether anything is recorded: the variable, or the marker file
    /// in the log's directory, which is how the installed build is
    /// switched on without rebuilding.
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["AGENTIDE_PERFORMANCE_LOG"] != nil
            || FileManager.default.fileExists(atPath: directory + "/performance-log")
    }

    /// Where the lines go when enabled; the directory is made on
    /// the first write.
    public static var file: String {
        directory + "/performance.log"
    }

    /// Whether a line written at a moment is still kept.
    public static func keeps(lineWrittenAt written: Date, now: Date = Date()) -> Bool {
        written > now.addingTimeInterval(-lifetime)
    }

    /// The newest lines of `text` that fit in `bytes`, whole lines
    /// only and oldest dropped first. Pure, so the trimming is
    /// tested without writing a hundred megabytes.
    public static func newest(of text: String, within bytes: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var kept = [Substring]()
        var size = 0
        for line in lines.reversed() {
            size += line.utf8.count + 1
            guard size <= bytes else {
                break
            }

            kept.append(line)
        }
        guard kept.isEmpty == false else {
            return ""
        }

        return kept.reversed().joined(separator: "\n") + "\n"
    }

    /// Records one wait. `what` names the process or call briefly;
    /// `context` is the directory or key it was about.
    public static func record(_ kind: Kind, _ what: String, seconds: TimeInterval, context: String = "") {
        guard isEnabled else {
            return
        }

        let line = Self.stamp().string(from: Date()) + "\t" + kind.label + "\t"
            + String(format: "%8.3f", seconds) + "\t" + context + "\t" + what + "\n"
        queue.async {
            sweepIfDue()
            trimIfHuge()
            append(line)
        }
    }

    /// Records a cache decision, which has no duration of its own.
    public static func record(cacheHit: Bool, _ key: String) {
        record(cacheHit ? .cacheHit : .cacheMiss, key, seconds: 0)
    }

    /// Times an async wait and records it.
    public static func time<Value>(
        _ kind: Kind,
        _ what: String,
        context: String = "",
        _ work: () async throws -> Value,
    ) async rethrows -> Value {
        guard isEnabled else {
            return try await work()
        }

        let started = Date()
        defer { record(kind, what, seconds: Date().timeIntervalSince(started), context: context) }
        return try await work()
    }

    // MARK: Internal

    /// The shared temporary directory: readable by the host user and
    /// the sandbox user alike, unlike either one's own home. Tests
    /// point it elsewhere through the environment, since a test
    /// must never write into the real one.
    static var directory: String {
        if let override = ProcessInfo.processInfo.environment["AGENTIDE_PERFORMANCE_LOG_DIRECTORY"] {
            return override
        }

        let user = NSUserName()
        let prefix = "sandvault-"
        let host = user.hasPrefix(prefix) ? String(user.dropFirst(prefix.count)) : user
        return "/Users/Shared/sv-" + host + "/tmp/agentide"
    }

    // MARK: Private

    private static let queue: DispatchQueue = .init(label: "agentide.performance-log")
    private static let sweepInterval: TimeInterval = 3_600

    /// A formatter per use: the type is not Sendable, and a line is
    /// written rarely enough that sharing one would save nothing.
    private static func stamp() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// Sweeps at most once an hour: reading the whole file on every
    /// line would make the log the slowest thing it measures. The
    /// clock is the file's own modification time, so nothing mutable
    /// is shared between the queue's writes.
    private static func sweepIfDue() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file)
        let lastSweep = attributes?[.creationDate] as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastSweep) >= sweepInterval,
              let text = try? String(contentsOfFile: file, encoding: .utf8)
        else {
            return
        }

        // The creation date is the sweep clock: rewriting resets it.
        try? FileManager.default.setAttributes([.creationDate: Date()], ofItemAtPath: file)
        let stamp = stamp()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let kept = lines.filter { line in
            guard let tab = line.firstIndex(of: "\t"),
                  let written = stamp.date(from: String(line[..<tab]))
            else {
                return false
            }

            return keeps(lineWrittenAt: written)
        }
        guard kept.count < lines.count else {
            return
        }

        try? (kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n"))
            .write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// Drops the oldest half of the file once it passes the cap.
    /// The size is one stat; reading the file only happens on the
    /// rare write that finds it over.
    private static func trimIfHuge() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file)
        guard let size = attributes?[.size] as? Int, size > sizeCap,
              let text = try? String(contentsOfFile: file, encoding: .utf8)
        else {
            return
        }

        try? newest(of: text, within: sizeFloor).write(toFile: file, atomically: true, encoding: .utf8)
    }

    private static func append(_ line: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let handle = FileHandle(forWritingAtPath: file) else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
