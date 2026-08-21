import AgentIDEDomain
import Foundation

/// A live `herdr terminal session control` client over pipes: JSON
/// command lines go in on standard input, parsed frame events stream
/// out. The terminal view renders panes locally from these events,
/// which is what makes selection, copying and pasting native.
/// Closing the channel only releases this controller; the herdr
/// workspace lives on.
public actor HerdrTerminalChannel {
    // MARK: Lifecycle

    /// Creates a channel that will spawn an argv resolved through
    /// `/usr/bin/env`; `environment` entries override the inherited
    /// ones.
    public init(command: [String], environment: [String: String] = [:]) {
        self.command = command
        extraEnvironment = environment
    }

    deinit {
        // stop() owns teardown; the pipes close with the process.
    }

    // MARK: Public

    /// Spawns the client and streams its events until it exits.
    public func start() throws -> AsyncStream<HerdrTerminalEvent> {
        let client = Process()
        client.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        client.arguments = command
        client.environment = ProcessEnvironment.scrubbed(merging: extraEnvironment)
        client.standardInput = input
        client.standardOutput = output
        client.standardError = errors
        try client.run()
        process = client
        spawned = true

        let reading = output.fileHandleForReading
        return AsyncStream { continuation in
            let pump = Task {
                var line = [UInt8]()
                do {
                    // Lines split at the byte level; each is ASCII
                    // JSON (frame bytes travel as base64), so the
                    // string round trip is lossless.
                    for try await byte in reading.bytes {
                        if byte == UInt8(ascii: "\n") {
                            let text = String(bytes: line, encoding: .utf8) ?? ""
                            if let event = HerdrTerminal.parse(line: text) {
                                continuation.yield(event)
                            }
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
                    }
                } catch {
                    // A read error ends the stream like an exit.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    /// Sends one command line to herdr. Deliberately nonisolated
    /// and synchronous: calls from one actor reach the pipe in
    /// order, which keystroke delivery depends on.
    public nonisolated func send(_ line: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Whether the spawned client process is still alive, for
    /// diagnosing a pane that receives nothing: a running client
    /// with no events points at the launch chain, a dead one at the
    /// session.
    public func isRunning() -> Bool {
        process?.isRunning ?? false
    }

    /// A one-line snapshot of the client's launch chain: the
    /// process and its descendants with their states, so a give-up
    /// report shows where a wedged sudo or sandbox launch stopped
    /// (`T` means suspended) instead of guessing.
    public func launchChainSnapshot() -> String {
        guard let pid = process?.processIdentifier else {
            return "no client process"
        }

        var pids = [String(pid)]
        var frontier = pids
        for _ in 0 ..< Self.descendantGenerations {
            frontier = frontier.flatMap { Self.outputLines("/usr/bin/pgrep", ["-P", $0]) }
            guard frontier.isEmpty == false else {
                break
            }

            pids += frontier
        }
        // Every herdr process joins the picture: a client alive
        // with no events usually means it is waiting on a slow or
        // wedged server, whose state and age then matter most.
        pids += Self.outputLines("/usr/bin/pgrep", ["-x", "herdr"]).filter { pids.contains($0) == false }
        return Self.outputLines("/bin/ps", ["-o", "pid=,stat=,etime=,ucomm=", "-p", pids.joined(separator: ",")])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
    }

    /// Detaches the client: end of standard input ends it, and the
    /// termination covers a client stuck before reading commands.
    public func stop() {
        try? input.fileHandleForWriting.close()
        process?.terminate()
        process = nil
    }

    /// Everything the client wrote to standard error, where herdr
    /// puts its diagnostics (unknown pane, refused sudo). Only
    /// call after the event stream has finished: the read waits for
    /// the pipe to close with the process, so a client that never
    /// spawned answers empty rather than waiting forever.
    public func collectedErrorText() -> String {
        guard spawned else {
            return ""
        }

        let data = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Private

    /// How many generations of children the chain snapshot follows;
    /// the launch chain is sudo, then sandbox-exec, then the shell
    /// or herdr it becomes.
    private static let descendantGenerations = 3

    private nonisolated let input: Pipe = .init()
    private nonisolated let output: Pipe = .init()
    private nonisolated let errors: Pipe = .init()
    private let command: [String]
    private let extraEnvironment: [String: String]
    private var process: Process?
    private var spawned = false

    /// Runs a quick diagnostic tool and returns its output lines.
    private static func outputLines(_ tool: String, _ arguments: [String]) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let captured = Pipe()
        task.standardOutput = captured
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else {
            return []
        }

        task.waitUntilExit()
        let data = (try? captured.fileHandleForReading.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
    }
}
