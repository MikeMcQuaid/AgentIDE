/// A watcher over workspace roots whose file-system events decide
/// when a repository's git is worth reading again. Mac uses FSEvents;
/// Linux will use inotify.
public protocol FileWatching: Sendable {
    /// Whether the stream is running; false answers every question
    /// with "assume changed", so a machine where watching fails
    /// falls back to time-based reads.
    var isWatching: Bool { get }

    /// Starts watching; safe to call more than once.
    func start()

    /// The directories changed since last asked, cleared by the asking.
    func consumeChangedPaths() -> Set<String>
}
