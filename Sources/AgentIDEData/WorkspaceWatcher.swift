import CoreServices
import Foundation
import Synchronization

// MARK: - WorkspaceWatcher

/// One FSEvents stream over the repository and worktree roots,
/// remembering which top-level directories changed so git is asked
/// about a repository only when something under it actually moved.
/// Blind polling read `git status` and `git worktree list` across
/// the whole workspace every few seconds for rows that never
/// changed; the file system already knows.
public final class WorkspaceWatcher: Sendable {
    // MARK: Lifecycle

    /// Creates a watcher over some root directories.
    public init(roots: [String]) {
        box = ChangeBox(roots: roots)
    }

    deinit {
        // The stream and its box deliberately outlive the watcher:
        // stopping a stream from a deinit cannot touch non-Sendable
        // state, and the one watcher lives for the process anyway.
    }

    // MARK: Public

    /// Whether the stream is running; false answers every question
    /// with "assume changed", so a machine where FSEvents fails
    /// falls back to time-based reads.
    public var isWatching: Bool {
        watching.withLock { $0 }
    }

    /// Starts watching; safe to call more than once.
    public func start() {
        guard started.withLock({ let was = $0; $0 = true; return was }) == false else {
            return
        }

        var context = FSEventStreamContext()
        // The stream holds the one strong reference the callback
        // reads; never released, since the stream is never stopped.
        context.info = Unmanaged.passRetained(box).toOpaque()
        guard let stream = FSEventStreamCreate(
            nil,
            workspaceEventsCallback,
            &context,
            box.roots as CFArray,
            // swiftformat:disable:next acronyms
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latencySeconds,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes),
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, Self.queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        watching.withLock { $0 = true }
    }

    /// The directories changed since last asked, trimmed to at most
    /// two levels under their root (a repository, or a worktree's
    /// `repository/branch`), and cleared by the asking.
    public func consumeChangedPaths() -> Set<String> {
        box.changed.withLock { changed in
            let consumed = changed
            changed = []
            return consumed
        }
    }

    // MARK: Internal

    /// What the event callback writes into: separate from the
    /// watcher so the never-stopped stream can never point at a
    /// deallocated object.
    final class ChangeBox: Sendable {
        // MARK: Lifecycle

        init(roots: [String]) {
            self.roots = roots
        }

        deinit {
            // Owned by the stream for the life of the process.
        }

        // MARK: Internal

        let roots: [String]
        let changed: Mutex<Set<String>> = .init([])

        /// Records event paths trimmed to their root plus two
        /// components: deep churn inside one worktree collapses to
        /// one entry however busy the agent in it is.
        func record(_ paths: [String]) {
            changed.withLock { set in
                for path in paths {
                    guard let root = roots.first(where: { candidate in
                        path == candidate || path.hasPrefix(candidate + "/")
                    }) else {
                        continue
                    }

                    let suffix = path.dropFirst(root.count)
                        .split(separator: "/")
                        .prefix(Self.keptComponents)
                    set.insert(suffix.isEmpty ? root : root + "/" + suffix.joined(separator: "/"))
                }
            }
        }

        // MARK: Private

        /// `repositories/<repo>` is one component under its root,
        /// `worktrees/<repo>/<branch>` two; nothing needs more.
        private static let keptComponents = 2
    }

    // MARK: Private

    /// How long FSEvents may coalesce a burst before delivering it;
    /// the poll only reads the answers every few seconds anyway.
    private static let latencySeconds = 0.5

    private static let queue: DispatchQueue = .init(label: "agentide.workspace-watcher", qos: .utility)

    private let box: ChangeBox
    private let started: Mutex<Bool> = .init(false)
    private let watching: Mutex<Bool> = .init(false)
}

// MARK: - Event callback

/// The C callback FSEvents delivers into; with `UseCFTypes` the
/// paths arrive as a `CFArray` of strings.
private let workspaceEventsCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
    guard let info else {
        return
    }

    let box = Unmanaged<WorkspaceWatcher.ChangeBox>.fromOpaque(info).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
    box.record(paths)
}
