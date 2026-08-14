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

    /// Creates a file diff.
    public init(path: String, hunks: [DiffHunk]) {
        self.path = path
        self.hunks = hunks
    }

    // MARK: Public

    /// The file's path on the new side.
    public let path: String

    /// The file's hunks in order.
    public let hunks: [DiffHunk]

    /// The stable identity, the file path.
    public var id: String {
        path
    }

    /// Added line count across the file's hunks, for diffstats.
    public var additions: Int {
        hunks.flatMap(\.lines).count { $0.kind == .addition }
    }

    /// Deleted line count across the file's hunks, for diffstats.
    public var deletions: Int {
        hunks.flatMap(\.lines).count { $0.kind == .deletion }
    }
}
