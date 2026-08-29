import AgentIDEData
import AgentIDEDomain

// MARK: - StackWork

/// What the tab knows about the stack this branch belongs to: the
/// stack itself, and the work it can be asked to do as a whole.
struct StackWork {
    var stack: BranchStack = .init(base: nil, branches: [], checkedOut: "")

    /// The entry the tab is listing, always named rather than left
    /// to the branch the worktree holds: reading up and down a stack
    /// must survive the reload that asks git which branch is really
    /// checked out, and where a local-only twin is checked out the
    /// entry standing for it is a different name entirely.
    var selected: String?

    /// What each of the stack's two actions would actually do, so
    /// a button with nothing to do says so by dimming.
    var needsRestack = false
    var needsPush = false

    /// The branches with commits the remote lacks, bottom first.
    var unpushedBranches: [String] = []

    /// The branches whose tip is unsigned, which no push will take.
    var unsignedBranches: [String] = []

    /// Bumped as each facts read begins; a slower, older read must
    /// not land its answers over a newer one's, which is how a
    /// rebase sometimes needed pressing twice: a poll's reload
    /// started before the rebase finished after the action's own.
    var factsGeneration = 0
    var fetch: (Worktree) async -> BranchStack = { worktree in
        BranchStack(base: nil, branches: [worktree.branch], checkedOut: worktree.branch)
    }

    var restack: (Worktree) async throws -> [String] = { _ in [] }
    var push: (Worktree) async throws -> [String] = { _ in [] }
    var pending: (Worktree) async -> Bool = { _ in false }
    var unpushed: (Worktree) async -> [String] = { _ in [] }
    var unsigned: (Worktree) async -> [String] = { _ in [] }
}
