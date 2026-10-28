import Foundation
import SanductorDomain
import Synchronization

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
            // Event-driven, never a blocking read: `FileHandle.bytes`
            // serialises its reads across every handle in the
            // process, so one idle client held every later attach
            // at nothing until it spoke. The handler runs on the
            // handle's own serial queue, and the buffer's lock only
            // says so to the compiler.
            let line = Mutex([UInt8]())
            reading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.isEmpty == false else {
                    // End of the pipe: the client is gone.
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }

                // Lines split at the byte level; each is ASCII JSON
                // (frame bytes travel as base64), so the string round
                // trip is lossless.
                for byte in data {
                    guard byte == UInt8(ascii: "\n") else {
                        line.withLock { $0.append(byte) }
                        continue
                    }

                    let text = line.withLock { pending in
                        defer { pending.removeAll(keepingCapacity: true) }
                        return String(bytes: pending, encoding: .utf8) ?? ""
                    }
                    if let event = HerdrTerminal.parse(line: text) {
                        continuation.yield(event)
                    }
                }
            }
            continuation.onTermination = { _ in reading.readabilityHandler = nil }
        }
    }

    /// Sends one command line to herdr. Deliberately nonisolated
    /// and synchronous: calls from one actor reach the pipe in
    /// order, which keystroke delivery depends on.
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

    private nonisolated let input: Pipe = .init()
    private nonisolated let output: Pipe = .init()
    private nonisolated let errors: Pipe = .init()
    private let command: [String]
    private let extraEnvironment: [String: String]
    private var process: Process?
    private var spawned = false
}
