import AgentIDEDomain
import Foundation

// MARK: - StackFacts

/// What a stack is and what it would take to put it in order and on
/// the remote, read together: the branches not sitting on the one
/// below them, those with commits the remote lacks, and those whose
/// tip is unsigned while signing is required.
public struct StackFacts: Sendable, Codable, Equatable {
    // MARK: Lifecycle

    /// Creates the facts; a lone branch in order has empty lists.
    public init(stack: BranchStack, outOfPlace: [String] = [], unpushed: [String] = [], unsigned: [String] = []) {
        self.stack = stack
        self.outOfPlace = outOfPlace
        self.unpushed = unpushed
        self.unsigned = unsigned
    }

    // MARK: Public

    public let stack: BranchStack
    public let outOfPlace: [String]
    public let unpushed: [String]
    public let unsigned: [String]
}

// MARK: - CachedStackFacts

/// A worktree's last stack facts in the metadata, with the reading
/// they were derived from and whether signing was required when the
/// unsigned list was read: a relaunch reads one `for-each-ref` per
/// worktree and derives nothing that has not moved, where an empty
/// cache re-derived every stack, ten processes each, at every start.
public struct CachedStackFacts: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(fingerprint: String, requiresSigning: Bool, facts: StackFacts, savedAt: Date = Date()) {
        self.fingerprint = fingerprint
        self.requiresSigning = requiresSigning
        self.facts = facts
        self.savedAt = savedAt
    }

    // MARK: Public

    public let fingerprint: String
    public let requiresSigning: Bool
    public let facts: StackFacts
    public let savedAt: Date
}
