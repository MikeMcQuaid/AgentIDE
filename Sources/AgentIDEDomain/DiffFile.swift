// MARK: - DiffLine

/// One line of a unified diff hunk.
public struct DiffLine: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a diff line.
    public init(kind: Kind, content: String) {
        self.kind = kind
        self.content = content
    }

    // MARK: Public

    /// How a diff line changes the file.
    public enum Kind: Hashable, Sendable {
        /// A line present on both sides.
        case context
        /// A line added by the change.
        case addition
        /// A line removed by the change.
        case deletion
    }

    /// The line's change kind.
    public let kind: Kind

    /// The line's text without its `+`, `-` or space prefix.
    public let content: String
}

// MARK: - DiffHunk

/// One `@@` hunk of a unified diff.
public struct DiffHunk: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a hunk.
    public init(oldStart: Int, newStart: Int, lines: [DiffLine]) {
        self.oldStart = oldStart
        self.newStart = newStart
        self.lines = lines
    }

    // MARK: Public

    /// The first line number on the old side.
    public let oldStart: Int

    /// The first line number on the new side.
    public let newStart: Int

    /// The hunk's lines in order.
    public let lines: [DiffLine]
}

// MARK: - DiffFile

/// One file's changes within a unified diff.
public struct DiffFile: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a file diff; the diffstat counts are computed once
    /// here rather than on every read, since the UI reads them per
    /// row on large diffs.
    public init(path: String, hunks: [DiffHunk], isNew: Bool = false) {
        self.path = path
        self.hunks = hunks
        self.isNew = isNew
        let lines = hunks.flatMap(\.lines)
        additions = lines.count { $0.kind == .addition }
        deletions = lines.count { $0.kind == .deletion }
    }

    // MARK: Public

    /// The file's path on the new side.
    public let path: String

    /// Whether the file is new: added or untracked, so its whole
    /// content is the diff and every line is an addition. The review
    /// says so and collapses it, since a wall of additions otherwise
    /// reads as a broken diff beside real hunks.
    public let isNew: Bool

    /// The file's hunks in order.
    public let hunks: [DiffHunk]

    /// Added line count across the file's hunks, for diffstats.
    public let additions: Int

    /// Deleted line count across the file's hunks, for diffstats.
    public let deletions: Int

    /// The stable identity, the file path.
    public var id: String {
        path
    }
}
