/// The git facts that refresh branch actions and diffs, independent
/// of agent activity.
public struct BranchStatus: Hashable, Sendable {
    // Periphery does not see the synthesised equality and hash reads.
    // periphery:ignore
    let worktreePath: String
    // periphery:ignore
    let branch: String
    // periphery:ignore
    let isDirty: Bool
    // periphery:ignore
    let aheadOfUpstream: Int?
    // periphery:ignore
    let aheadOfDefault: Int?
    // periphery:ignore
    let behindDefault: Int?
    // periphery:ignore
    let behindUpstream: Int?
    // periphery:ignore
    let revision: String?
}
