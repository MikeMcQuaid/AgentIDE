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

                // Split each pipe chunk under one lock, rather than locking for every byte.
                let records = line.withLock { pending in
                    pending.append(contentsOf: data)
                    guard let last = pending.lastIndex(of: UInt8(ascii: "\n")) else {
                        return [String]()
                    }

                    let records = pending[...last]
                        .split(separator: UInt8(ascii: "\n"))
                        .compactMap { String(bytes: $0, encoding: .utf8) }
                    pending.removeFirst(last + 1)
                    return records
                }
                for event in Self.events(from: records) {
                    continuation.yield(event)
                }
            }
            continuation.onTermination = { _ in reading.readabilityHandler = nil }
        }
    }

    /// A serial interactive queue preserves order without blocking UI events on a full pipe.
    public nonisolated func send(_ line: String) {
        let data = Data((line + "\n").utf8)
        writes.async { [input] in
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
    }

    /// Detaches the client: end of standard input ends it, and the
    /// termination covers a client stuck before reading commands.
    public func stop() {
        process?.terminate()
        writes.async { [input] in try? input.fileHandleForWriting.close() }
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

    private nonisolated let writes: DispatchQueue = .init(label: "Sanductor.terminal-input", qos: .userInteractive)
    private nonisolated let input: Pipe = .init()
    private nonisolated let output: Pipe = .init()
    private nonisolated let errors: Pipe = .init()
    private let command: [String]
    private let extraEnvironment: [String: String]
    private var process: Process?
    private var spawned = false

    private static func events(from records: [String]) -> [HerdrTerminalEvent] {
        var events = [HerdrTerminalEvent]()
        var frames = [UInt8]()
        for record in records {
            if let event = HerdrTerminal.parse(line: record) {
                if case let .frame(bytes) = event {
                    frames.append(contentsOf: bytes)
                } else {
                    if frames.isEmpty == false {
                        events.append(.frame(bytes: frames)); frames = []
                    }
                    events.append(event)
                }
            }
        }
        if frames.isEmpty == false {
            events.append(.frame(bytes: frames))
        }
        return events
    }
}
