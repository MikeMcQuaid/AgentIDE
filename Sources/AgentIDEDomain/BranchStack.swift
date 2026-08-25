import Foundation

/// A stack of branches in one worktree: each branch built on the one
/// below it, the bottom built on the repository's default branch.
/// Derived from ancestry rather than recorded anywhere, so a stack an
/// agent builds by checking out branches of its own is a stack here
/// too, and nothing is lost when the app quits.
public struct BranchStack: Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a stack, bottom first.
    public init(base: String?, branches: [String], checkedOut: String) {
        self.base = base
        self.branches = branches
        self.checkedOut = checkedOut
    }

    // MARK: Public

    /// The default branch everything here forks from, when known.
    public let base: String?

    /// The stack's branches, the one nearest the base first.
    public let branches: [String]

    /// The branch the worktree actually holds; the only one that can
    /// be written to without checking another out first.
    public let checkedOut: String

    /// Whether this is a stack at all: one branch on the default
    /// branch is just a branch, and the app shows it as it always did.
    public var isStacked: Bool {
        branches.count > 1
    }

    /// What a branch is built on: the branch below it, or the
    /// repository's default branch for the bottom one.
    public func parent(of branch: String) -> String? {
        guard let index = branches.firstIndex(of: branch) else {
            return nil
        }

        return index == 0 ? base : branches[index - 1]
    }
}
