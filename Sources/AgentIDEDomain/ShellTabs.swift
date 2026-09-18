// MARK: - ShellTabs

/// The shells open in the utility pane, worktree by worktree.
///
/// One worktree needs more than one: a dev server holds its shell
/// for as long as it runs, and the git and API calls that go with it
/// need a prompt of their own. Each shell is a pane the window
/// mounts and a capsule in the shell tab's strip, and each lives
/// until it is closed, its worktree is destroyed or the app quits.
public struct ShellTabs: Sendable {
    // MARK: Lifecycle

    /// Creates the empty set: shells only ever start from a click.
    public init() {
        // Nothing runs until one is opened.
    }

    // MARK: Public

    /// One open shell.
    public struct Shell: Identifiable, Equatable, Sendable {
        /// Unique for the app's run, never reused: a closed shell's
        /// identity must not land on the pane that replaces it.
        public let id: Int

        /// The worktree it runs in, which is also its directory.
        public let worktreePath: String

        /// Its place in its worktree's strip, kept for the shell's
        /// life: renumbering the rest as one closes would move the
        /// tab under the pointer between one click and the next.
        public let number: Int

        /// What its capsule says.
        public var title: String {
            "Shell " + String(number)
        }
    }

    /// Every open shell, in the order they were opened, so mounting
    /// one more never remounts the rest.
    public private(set) var all: [Shell] = []

    /// Whether nothing is running, which is what lets the machine
    /// sleep.
    public var isEmpty: Bool {
        all.isEmpty
    }

    /// One worktree's shells, in opening order: what its strip lists.
    public func shells(in worktreePath: String) -> [Shell] {
        all.filter { $0.worktreePath == worktreePath }
    }

    /// The shell a worktree is showing, which is the only one of
    /// its own that takes keys.
    public func selected(in worktreePath: String) -> Shell.ID? {
        selection[worktreePath]
    }

    /// Opens a shell in a worktree and shows it. It takes the
    /// lowest number that worktree is not already using, so closing
    /// the second of three and opening another fills the gap rather
    /// than counting ever upwards.
    @discardableResult
    public mutating func open(in worktreePath: String) -> Shell.ID {
        let used = Set(shells(in: worktreePath).map(\.number))
        var number = 1
        while used.contains(number) {
            number += 1
        }
        let shell = Shell(id: nextIdentifier, worktreePath: worktreePath, number: number)
        nextIdentifier += 1
        all.append(shell)
        selection[worktreePath] = shell.id
        return shell.id
    }

    /// Shows one of a worktree's shells.
    public mutating func select(_ identifier: Shell.ID) {
        guard let shell = all.first(where: { $0.id == identifier }) else {
            return
        }

        selection[shell.worktreePath] = shell.id
    }

    /// Closes a shell, which unmounts its pane and kills its PTY.
    /// The one beside it takes its place, the one after for
    /// preference, so closing along a strip never jumps back to its
    /// start.
    public mutating func close(_ identifier: Shell.ID) {
        guard let shell = all.first(where: { $0.id == identifier }) else {
            return
        }

        let siblings = shells(in: shell.worktreePath)
        all.removeAll { $0.id == identifier }
        guard selection[shell.worktreePath] == identifier else {
            return
        }
        guard let index = siblings.firstIndex(of: shell) else {
            return
        }

        let neighbour = siblings.dropFirst(index + 1).first ?? siblings.prefix(index).last
        selection[shell.worktreePath] = neighbour?.id
    }

    /// Keeps only the worktrees that still exist: a destroyed
    /// worktree takes its shells with it, while one the sidebar
    /// merely stopped listing keeps them.
    public mutating func keep(worktreePaths: Set<String>) {
        all.removeAll { worktreePaths.contains($0.worktreePath) == false }
        selection = selection.filter { worktreePaths.contains($0.key) }
    }

    // MARK: Private

    /// The next identity to hand out; counting on rather than
    /// reusing is what keeps a new pane from inheriting a closed
    /// one's view.
    private var nextIdentifier = 1

    /// Each worktree's shown shell.
    private var selection: [String: Shell.ID] = [:]
}
