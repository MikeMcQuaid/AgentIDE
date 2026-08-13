import AgentIDEDomain
import Foundation

/// A live `tmux -C` control mode client over pipes: command lines go
/// in on standard input, parsed protocol events stream out. The
/// terminal view renders panes locally from these events, which is
/// what makes selection, copying and scrollback native. Closing the
/// channel only detaches this client; the tmux session lives on.
public actor TmuxControlChannel {
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
    public func start() throws -> AsyncStream<TmuxControlEvent> {
        let client = Process()
        client.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        client.arguments = command
        var environment = ProcessInfo.processInfo.environment
        let toolPath = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], toolPath].compactMap(\.self).joined(separator: ":")
        // As in FoundationProcessRunner: an inherited TMUX variable
        // would aim the client at the surrounding server no matter
        // what TMUX_TMPDIR says. Servers are only chosen explicitly.
        environment["TMUX"] = nil
        environment["TMUX_PANE"] = nil
        environment.merge(extraEnvironment) { _, new in new }
        client.environment = environment
        client.standardInput = input
        client.standardOutput = output
        client.standardError = FileHandle.nullDevice
        try client.run()
        process = client

        let reading = output.fileHandleForReading
        return AsyncStream { continuation in
            let pump = Task {
                var parser = TmuxControlParser()
                do {
                    for try await line in reading.bytes.lines {
                        if let event = parser.parse(line: line) {
                            continuation.yield(event)
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

    /// Sends one command line to tmux. Deliberately nonisolated and
    /// synchronous: calls from one actor reach the pipe in order,
    /// which keystroke delivery depends on.
    public nonisolated func send(_ line: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Detaches the client: end of standard input ends it, and the
    /// termination covers a client stuck before reading commands.
    public func stop() {
        try? input.fileHandleForWriting.close()
        process?.terminate()
        process = nil
    }

    // MARK: Private

    private nonisolated let input: Pipe = .init()
    private nonisolated let output: Pipe = .init()
    private let command: [String]
    private let extraEnvironment: [String: String]
    private var process: Process?
}
