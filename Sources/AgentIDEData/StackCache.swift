import AgentIDEDomain
import Foundation

/// The stack each worktree was last found to be in, against the
/// state it was derived from. Deriving one asks git about every
/// branch's fork point and how far it has come, thirty processes
/// for a repository of a few branches, and the sidebar's rota does
/// it for a worktree at a time all day. Nothing about the answer
/// can change while every branch still points where it did, the
/// same branch is checked out and the same ones are excluded, so
/// that is what the answer is kept against.
actor StackCache {
    // MARK: Internal

    static let shared: StackCache = .init()

    /// The remembered stack, or nil when anything it was derived
    /// from has moved.
    func stack(for worktreePath: String, derivedFrom fingerprint: String) -> BranchStack? {
        guard let entry = entries[worktreePath], entry.fingerprint == fingerprint else {
            return nil
        }

        return entry.stack
    }

    func remember(_ stack: BranchStack, for worktreePath: String, derivedFrom fingerprint: String) {
        entries[worktreePath] = Entry(fingerprint: fingerprint, stack: stack)
    }

    // MARK: Private

    private struct Entry {
        let fingerprint: String
        let stack: BranchStack
    }

    private var entries: [String: Entry] = [:]
}
