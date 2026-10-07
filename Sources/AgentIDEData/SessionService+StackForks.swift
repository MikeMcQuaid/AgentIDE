/// Branches that part ways at one commit, which a stack, being a
/// line, cannot hold. Split from the stack for length.
extension SessionService {
    /// The candidates on the checked-out branch's line. Ancestry alone
    /// read two sessions started on one branch as one stacked on the
    /// other, and a restack gave one the other's commits. Three
    /// branches whose every pair last shared history at one commit,
    /// two or more of them past it, meet at a fork; a branch past
    /// that fork stays only when the checked-out branch shares history
    /// with it beyond the fork. A parent that moved on after its child
    /// was cut is two branches parting, not three, and stays.
    func droppingForks(
        _ candidates: [StackCandidate],
        checkedOut: String,
        worktreePath: String,
    ) async -> [StackCandidate] {
        let related = await droppingOtherLines(candidates, checkedOut: checkedOut, worktreePath: worktreePath)
        guard related.count >= Self.branchesAtFork else {
            return related
        }

        let meets = await meets(of: related, checkedOut: checkedOut, worktreePath: worktreePath)
        var dropped = Set<String>()
        for (firstIndex, first) in related.enumerated() {
            for (secondIndex, second) in related.enumerated().dropFirst(firstIndex + 1) {
                for third in related.dropFirst(secondIndex + 1) {
                    let past = await pastFork(
                        of: [first, second, third],
                        meets: meets,
                        checkedOut: checkedOut,
                        worktreePath: worktreePath,
                    )
                    dropped.formUnion(past)
                }
            }
        }
        return related.filter { dropped.contains($0.branch) == false }
    }

    /// A fork is three branches meeting at one commit.
    private static let branchesAtFork = 3

    /// Where each pair last shared history, keyed by the pair.
    private func meets(
        of related: [StackCandidate],
        checkedOut: String,
        worktreePath: String,
    ) async -> [Set<String>: String] {
        var meets = [Set<String>: String]()
        for (index, first) in related.enumerated() {
            for second in related.dropFirst(index + 1) {
                meets[[first.branch, second.branch]] =
                    if first.branch == checkedOut {
                        second.forkCommit
                    } else if second.branch == checkedOut {
                        first.forkCommit
                    } else {
                        await git.mergeBase(first.branch, second.branch, worktreePath: worktreePath)
                    }
            }
        }
        return meets
    }

    /// The branches of three meeting at a fork that go: those past it
    /// with which the checked-out branch shares nothing beyond it.
    private func pastFork(
        of trio: [StackCandidate],
        meets: [Set<String>: String],
        checkedOut: String,
        worktreePath: String,
    ) async -> [String] {
        let pairMeets = trio.enumerated().flatMap { index, first in
            trio.dropFirst(index + 1).map { meets[[first.branch, $0.branch]] }
        }
        guard case let meet?? = pairMeets.first, pairMeets.allSatisfy({ $0 == meet }) else {
            return []
        }

        let past = trio.filter { $0.tipCommit != meet }
        guard past.count > 1 else {
            return []
        }

        var dropped = [String]()
        for entry in past where entry.branch != checkedOut {
            let shared = entry.forkCommit
            if shared != meet, await git.isAncestor(meet, of: shared, worktreePath: worktreePath) {
                continue
            }
            dropped.append(entry.branch)
        }
        return dropped
    }

    /// Without the branches that parted from the checked-out one on
    /// another line. Once two branches have both moved on from where
    /// they last met, ancestry cannot say which was cut from which,
    /// and reading the other as the parent put a parent's worktree
    /// on top of its own child and a child on top of its sibling. The
    /// reflog says what a branch was created from: the checked-out
    /// branch's parent stays, a branch cut from the checked-out one
    /// or from any other candidate goes, and a branch git has nothing
    /// to say about stays the parent it was always read as.
    private func droppingOtherLines(
        _ related: [StackCandidate],
        checkedOut: String,
        worktreePath: String,
    ) async -> [StackCandidate] {
        guard let here = related.first(where: { $0.branch == checkedOut }) else {
            return related
        }

        let parted = related.filter { entry in
            entry.branch != checkedOut && entry.forkCommit != entry.tipCommit && entry.forkCommit != here.tipCommit
        }
        guard parted.isEmpty == false else {
            return related
        }

        let names = Set(related.map(\.branch))
        let parent = await git.createdFrom(checkedOut, worktreePath: worktreePath)
        var dropped = Set<String>()
        for entry in parted where entry.branch != parent {
            if let origin = await git.createdFrom(entry.branch, worktreePath: worktreePath), names.contains(origin) {
                dropped.insert(entry.branch)
            }
        }
        return related.filter { dropped.contains($0.branch) == false }
    }
}
