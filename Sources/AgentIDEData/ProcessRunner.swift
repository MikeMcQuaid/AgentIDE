import Foundation

// MARK: - ProcessResult

/// The captured outcome of a finished process.
public struct ProcessResult: Sendable {
    // MARK: Lifecycle

    /// Creates a result.
    public init(status: Int32, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    // MARK: Public

    /// The process's exit status.
    public let status: Int32

    /// Everything the process wrote to standard output.
    public let standardOutput: String

    /// Everything the process wrote to standard error.
    public let standardError: String

    /// Whether the process exited zero.
    public var succeeded: Bool {
        status == 0
    }
}

// MARK: - CommandError

/// An error from a failed external command; handled as a generic
/// Error outside this module.
struct CommandError: Error, LocalizedError {
    // MARK: Lifecycle

    /// Creates a command error.
    init(command: String, result: ProcessResult) {
        self.command = command
        self.result = result
    }

    // MARK: Internal

    /// The command that failed, for display.
    let command: String

    /// The failing process's captured result.
    let result: ProcessResult

    /// A readable failure description.
    var errorDescription: String? {
        let detail = result.standardError.isEmpty ? result.standardOutput : result.standardError
        return "\(command) failed (\(result.status)): \(detail)"
    }
}

// MARK: - Shell helpers

extension String {
    /// The string single-quoted for a POSIX shell: quotes close,
    /// escape the quote and reopen, so no content can break out of
    /// the quoting. The one quoting implementation for every shell
    /// payload this module builds.
    var shellQuoted: String {
        "'" + replacing("'", with: "'\\''") + "'"
    }
}

public extension String {
    /// The string capped to a length, keeping its end: log excerpts
    /// explain themselves at the bottom, so trimming the head is
    /// what keeps the useful part.
    func prefixWithinLimit(_ limit: Int) -> String {
        count <= limit ? self : "…\n" + String(suffix(limit))
    }
}

// MARK: - ProcessEnvironment

/// The one environment every spawned process starts from.
enum ProcessEnvironment {
    /// The inherited environment with the tool prefixes on PATH and
    /// any surrounding tmux scrubbed: an inherited TMUX variable
    /// makes every child tmux command target the surrounding server
    /// regardless of TMUX_TMPDIR; a test teardown's kill-server once
    /// killed the production server and every agent on it that way.
    /// Servers are only ever selected explicitly.
    static func scrubbed(merging extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let toolPath = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], toolPath].compactMap(\.self).joined(separator: ":")
        environment["TMUX"] = nil
        environment["TMUX_PANE"] = nil
        environment.merge(extra) { _, new in new }
        return environment
    }
}

// MARK: - ProcessRunner

/// Runs external commands and captures their output.
public protocol ProcessRunner: Sendable {
    /// Runs an argv, resolved via `/usr/bin/env`, and captures output.
    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
    ) async throws -> ProcessResult
}

// MARK: - FoundationProcessRunner

/// A `ProcessRunner` backed by Foundation's `Process`, writing output
/// to temporary files so large output can never deadlock a pipe.
public struct FoundationProcessRunner: ProcessRunner {
    // MARK: Lifecycle

    /// Creates a runner.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// Runs the argv on a global queue and captures its output.
    public func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try continuation.resume(returning: Self.runBlocking(arguments, workingDirectory, environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Private

    private static func runBlocking(
        _ arguments: [String],
        _ workingDirectory: String?,
        _ extraEnvironment: [String: String],
    ) throws -> ProcessResult {
        let outputURL = temporaryFile()
        let errorURL = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = ProcessEnvironment.scrubbed(merging: extraEnvironment)
        process.standardOutput = try FileHandle(forWritingTo: outputURL)
        process.standardError = try FileHandle(forWritingTo: errorURL)
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: (try? String(contentsOf: outputURL, encoding: .utf8)) ?? "",
            standardError: (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "",
        )
    }

    private static func temporaryFile() -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-" + UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }
}
