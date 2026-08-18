import AgentIDEDomain

/// The files commands outside the app are waiting to have edited.
public extension SessionService {
    /// The environment a host shell needs for its editors to open
    /// here, and for `agentide` to work as a command in it.
    func shellEnvironment() -> [String: String] {
        EditorShim(paths: paths).environment
    }

    /// Every file a command is waiting on, in the order they were
    /// asked for, published again whenever the set changes. Reading
    /// the spool is a directory listing, so it polls rather than
    /// watching: a request has to reach the screen in the time it
    /// takes to notice a shell has stopped echoing.
    func pendingEdits() -> AsyncStream<[ExternalEdit]> {
        let spool = ExternalEditSpool(directory: paths.editsDirectory)
        return AsyncStream { continuation in
            let task = Task {
                var previous = [ExternalEdit]()
                var hasRead = false
                while Task.isCancelled == false {
                    let current = await Self.pending(in: spool)
                    if hasRead == false || current != previous {
                        previous = current
                        hasRead = true
                        continuation.yield(current)
                    }
                    try? await Task.sleep(for: .milliseconds(Self.editPollMilliseconds))
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

    /// Releases the waiting command: a saved file lets it carry on,
    /// a cancelled one fails it.
    @concurrent
    func finishEdit(_ edit: ExternalEdit, saved: Bool) async {
        ExternalEditSpool(directory: paths.editsDirectory).finish(edit, saved: saved)
    }

    // MARK: Private

    /// How often the spool is read; the shim polls for its answer at
    /// the same rate, so the whole round trip stays under a second.
    private static let editPollMilliseconds = 300

    /// Off the caller's actor: the poll runs while the window is
    /// being used, so it must never touch the main thread.
    @concurrent
    private static func pending(in spool: ExternalEditSpool) async -> [ExternalEdit] {
        spool.pending()
    }
}
