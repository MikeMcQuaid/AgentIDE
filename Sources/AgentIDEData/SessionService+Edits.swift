import AgentIDEDomain
import Foundation
import Synchronization

/// The files commands outside the app are waiting to have edited.
public extension SessionService {
    /// The environment a host shell needs for its editors to open
    /// here, and for `agentide` to work as a command in it.
    func shellEnvironment() -> [String: String] {
        EditorShim(paths: paths).environment
    }

    /// Where Settings keeps checkouts and worktrees, for the
    /// published choices: only the host user can read Settings, and
    /// `agentide` looks wherever the app does. Always the resolved
    /// path, so clearing an override replaces the one it left.
    var locationChoices: [(key: String, value: String)] {
        [
            ("repositories-directory", publishedLocation(paths.repositoriesDirectory)),
            ("worktrees-directory", publishedLocation(paths.worktreesDirectory)),
        ]
    }

    /// A location agents can run in, or empty, which the command
    /// reads as unset: outside the shared workspace setup reports the
    /// location and no agent launches there, so the command keeps to
    /// the defaults rather than making worktrees nothing can use.
    internal func publishedLocation(_ directory: String) -> String {
        if (try? requireSandboxWorkspace(directory)) == nil {
            ""
        } else {
            directory
        }
    }

    /// Publishes what a session was last started with, so
    /// `agentide new` offers the same repositories, agents, models
    /// and efforts with the last ones already chosen. Written as
    /// `key=value` lines because the sandbox has no JSON tool and
    /// the command reading them is a shell script, and merged with
    /// what is there: the file is one memory shared with that
    /// command, which writes its own choices into it. A value
    /// holding a newline cannot be one line, so its key is dropped
    /// and the command falls back to its own default. Every refresh
    /// publishes, so an unchanged file is left alone, and the sandbox
    /// can write the file, so it is read and replaced as a
    /// `SandboxFile`.
    func publishSessionChoices(_ values: [(key: String, value: String)]) {
        let replaced = Set(values.map(\.key))
        SandboxFile.update("session-defaults", in: paths.agentideDirectory) { existing in
            let kept = (existing?.split(separator: "\n") ?? [])
                .filter { replaced.contains(String($0.prefix { $0 != "=" })) == false }
                .map(String.init)
            let published = values.filter { $0.value.contains("\n") == false }.map { $0.key + "=" + $0.value }
            return (kept + published).sorted().joined(separator: "\n") + "\n"
        }
    }

    /// Every file a command is waiting on, in the order they were
    /// asked for, published again whenever the set changes. A
    /// dispatch source on the spool directory reads a request the
    /// moment its file lands; the 300 ms poll it replaces woke two
    /// hundred times a minute with nothing ever waiting. The ticks
    /// that remain are backstops: a slow one for a lost event, a
    /// faster one only while requests wait, whose commands can die
    /// without writing anything.
    func pendingEdits() -> AsyncStream<[ExternalEdit]> {
        pendingEdits(sweepInterval: nil)
    }

    /// Lets tests keep safety sweeps beyond their deadline.
    internal func pendingEdits(sweepInterval: Duration?) -> AsyncStream<[ExternalEdit]> {
        let spool = ExternalEditSpool(directory: paths.editsDirectory)
        let directory = paths.editsDirectory
        return AsyncStream { continuation in
            let task = Task {
                let wake = Self.directoryChanges(in: directory)
                var previous = [ExternalEdit]()
                var hasRead = false
                while Task.isCancelled == false {
                    let current = await Self.pending(in: spool)
                    if hasRead == false || current != previous {
                        previous = current
                        hasRead = true
                        continuation.yield(current)
                    }
                    let timeoutSeconds =
                        if wake == nil {
                            // No watch (the directory would not
                            // open): the old poll, a touch slower.
                            Self.unwatchedPollSeconds
                        } else if current.isEmpty {
                            Self.idleSweepSeconds
                        } else {
                            Self.activeSweepSeconds
                        }
                    let timeout = sweepInterval ?? .seconds(timeoutSeconds)
                    if let wake {
                        await wake.wait(timeout: timeout)
                    } else {
                        try? await Task.sleep(for: timeout)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Tells the waiting command's shim the app has its file.
    @concurrent
    func claimEdit(_ edit: ExternalEdit) async {
        ExternalEditSpool(directory: paths.editsDirectory).claim(edit)
    }

    /// Drops a request nothing waits on, once it has been acted on.
    @concurrent
    func discardEdit(_ edit: ExternalEdit) async {
        ExternalEditSpool(directory: paths.editsDirectory).discard(edit)
    }

    /// Releases the waiting command: a saved file lets it carry on,
    /// a cancelled one fails it.
    @concurrent
    func finishEdit(_ edit: ExternalEdit, saved: Bool) async {
        ExternalEditSpool(directory: paths.editsDirectory).finish(edit, saved: saved)
    }

    // MARK: Private

    /// The backstop ticks around the directory watch, in seconds:
    /// sweep waiting requests whose command has died every couple
    /// of seconds, and re-read a quiet spool inside the ten seconds
    /// a waiting shim gives the app to claim, so even a dead watch
    /// answers in time.
    private static let activeSweepSeconds = 2.0
    private static let idleSweepSeconds = 8.0

    /// The plain poll used only when the directory cannot be
    /// watched at all.
    private static let unwatchedPollSeconds = 1.0

    /// Off the caller's actor: the watch runs while the window is
    /// being used, so it must never touch the main thread.
    @concurrent
    private static func pending(in spool: ExternalEditSpool) async -> [ExternalEdit] {
        spool.pending()
    }

    /// A wake rung whenever the spool directory's listing changes;
    /// nil when the directory cannot be opened for watching. The
    /// source lives as long as the wake does.
    internal static func directoryChanges(in directory: String) -> DirectoryWake? {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let descriptor = unsafe open(directory, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        let wake = DirectoryWake()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .global(qos: .utility),
        )
        source.setEventHandler { wake.ring() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        // The source is kept by its own handler chain until the
        // process ends: the loop it wakes lives as long as the
        // window, and a watch that outlives it costs one descriptor.
        Self.sources.withLock { $0.append(source) }
        return wake
    }

    /// The directory watches in flight, held so their sources are
    /// never released while the loops they wake still run.
    private static let sources: Mutex<[DispatchSourceFileSystemObject]> = .init([])
}
