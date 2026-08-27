/// Where a branch sits in its stack: how many pull requests are
/// under it, how tall the whole stack is, and what it is built on.
/// A branch on its own stands one of one on nothing in particular.
public struct StackStanding: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a standing.
    public init(position: Int, height: Int, base: String? = nil) {
        self.position = position
        self.height = height
        self.base = base
    }

    // MARK: Public

    /// Counting from the bottom of the stack.
    public let position: Int

    /// How many pull requests the stack holds in all.
    public let height: Int

    /// The branch this one opens against, when it is not the
    /// repository's own default.
    public let base: String?

    /// Whether this is a stack at all.
    public var isStacked: Bool {
        height > 1
    }

    /// How many pull requests are built on this one.
    public var above: Int {
        max(0, height - position)
    }
}
