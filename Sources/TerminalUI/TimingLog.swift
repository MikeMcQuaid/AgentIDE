import Foundation

/// A plain-text log of how long each launch, resume and refresh step
/// took, for reading back when something feels slow. One line per
/// step, appended as it happens, in the app's own support directory
/// where nothing else looks. Entries older than a day are swept on
/// the next write, so the file never grows past what a day of use
/// produces and holds nothing worth keeping.
public enum TimingLog {
    // MARK: Public

    /// Where the lines go: set once at launch to the app's own area
    /// of the shared workspace, where both users can read it, the
    /// sandbox included. Until then a temporary file, so a record
    /// from before the paths exist is never lost.
    public static var file: String = NSTemporaryDirectory() + "agentide-timings.log"

    /// Records a step and how long it took, stamped with when it
    /// ended. `context` names what the step belonged to (a session,
    /// a worktree) so a day's lines can be grouped.
    public static func record(_ step: String, seconds: TimeInterval, context: String) {
        let line = stamp.string(from: Date()) + "\t" + String(format: "%7.3f", seconds)
            + "\t" + context + "\t" + step + "\n"
        queue.async {
            sweep()
            append(line)
        }
    }

    /// Times an async step and records it.
    public static func time<Value>(
        _ step: String,
        context: String,
        _ work: () async throws -> Value,
    ) async rethrows -> Value {
        let started = Date()
        defer { record(step, seconds: Date().timeIntervalSince(started), context: context) }
        return try await work()
    }

    // MARK: Private

    private static let queue: DispatchQueue = .init(label: "agentide.timing-log")
    private static let lifetime: TimeInterval = 86_400
    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Drops every line older than a day; run before each append
    /// rather than on a timer, so an idle app costs nothing.
    private static func sweep() {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-lifetime)
        let kept = text.split(separator: "\n", omittingEmptySubsequences: true).filter { line in
            guard let tab = line.firstIndex(of: "\t"),
                  let written = stamp.date(from: String(line[..<tab]))
            else {
                return false
            }

            return written > cutoff
        }
        guard kept.count < text.split(separator: "\n").count else {
            return
        }

        try? (kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n"))
            .write(toFile: file, atomically: true, encoding: .utf8)
    }

    private static func append(_ line: String) {
        let url = URL(fileURLWithPath: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        guard let handle = FileHandle(forWritingAtPath: file) else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
