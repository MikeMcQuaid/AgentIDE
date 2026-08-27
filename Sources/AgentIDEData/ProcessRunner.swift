import AgentIDEDomain
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

// MARK: - ProcessEnvironment

/// The one environment every spawned process starts from.
enum ProcessEnvironment {
    /// The inherited environment with the tool prefixes on PATH and
    /// any surrounding herdr scrubbed: an inherited HERDR_SESSION or
    /// HERDR_SOCKET_PATH (a dev build or test running inside a herdr
    /// pane) makes every child herdr command target the surrounding
    /// server; a surrounding-server teardown once killed a
    /// production multiplexer and every agent on it that way.
    /// Servers are only ever selected explicitly.
    static func scrubbed(merging extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let toolPath = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], toolPath].compactMap(\.self).joined(separator: ":")
        for variable in [
            "HERDR_SESSION", "HERDR_SOCKET_PATH", "HERDR_ENV",
            "HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID",
        ] {
            environment[variable] = nil
        }
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
        // Every process the app runs passes through here, so this is
        // where each one's cost is recorded: the command's first
        // words name it, the directory says what it was about.
        try await PerformanceLog.time(
            .process,
            Self.name(of: arguments),
            context: workingDirectory ?? "",
        ) {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try continuation.resume(
                            returning: Self.runBlocking(arguments, workingDirectory, environment),
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: Private

    /// How many words of a command name it in the log: enough for
    /// `git rev-list --count` or `gh pr list` without the arguments
    /// that make every line unique. Git's `-c key=value` hardening
    /// pairs are skipped, or every git call read the same.
    private static let namedWords = 3

    private static func name(of arguments: [String]) -> String {
        // A sandbox launch reads as `sudo --login --set-home` whatever
        // it runs; its own label, in the environment it sets, is the
        // name worth logging.
        let label = arguments.first == "sudo" ? arguments.first { $0.hasPrefix("AGENTIDE_SESSION=") } : nil
        if let label {
            return "sandbox " + label.dropFirst("AGENTIDE_SESSION=".count)
        }
        var words = [String]()
        var skipNext = false
        for word in arguments {
            if skipNext {
                skipNext = false
                continue
            }
            if word == "-c" {
                skipNext = true
                continue
            }
            // A flag before the subcommand says nothing about what
            // was run: without this every git call in the log read
            // `git --no-optional-locks` and the subcommand was lost.
            // A flag after it, like `rev-list --count`, is kept.
            if word.hasPrefix("--"), words.count == 1 {
                continue
            }
            words.append(word)
            if words.count == namedWords {
                break
            }
        }
        return words.joined(separator: " ")
    }

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
