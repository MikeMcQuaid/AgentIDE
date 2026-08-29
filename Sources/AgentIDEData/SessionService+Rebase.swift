import AgentIDEDomain
import Synchronization

// MARK: - OverwriteTips

/// The remote tips set aside by a conflicted integration rebase,
/// keyed by worktree and branch, in memory only: losing them costs
/// nothing but a repeated fetch-and-rebase. A class so every copy
/// of the service value shares one set.
final class OverwriteTips: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing owned beyond the dictionary; the rule wants the
        // release made explicit.
    }

    // MARK: Internal

    func remember(_ tip: String, worktreePath: String, branch: String) {
        tips.withLock { $0[worktreePath + "#" + branch] = tip }
    }

    func tip(worktreePath: String, branch: String) -> String? {
        tips.withLock { $0[worktreePath + "#" + branch] }
    }

    func forget(worktreePath: String, branch: String) {
        tips.withLock { $0[worktreePath + "#" + branch] = nil }
    }

    // MARK: Private

    private let tips: Mutex<[String: String]> = .init([:])
}

// MARK: - SessionService

/// What the rebase button would do and where its rebase lands,
/// split from the sources file for length.
public extension SessionService {
    /// Rebases onto the target; when integrating a remote tip this
    /// branch has never seen conflicts, the remote's version is set
    /// aside instead: the branch rebases onto origin/HEAD as it
    /// would have before the remote moved, the conflicting tip is
    /// remembered, and the next Push replaces it with an explicit
    /// lease naming that tip. Fetch and Rebase, then Push: never a
    /// terminal step.
    internal func integrateOrSetAside(worktree: Worktree, branch: String, target: String) async throws {
        do {
            try await git.rebaseSigned(worktreePath: worktree.path, branch: branch, onto: target)
            overwriteTips.forget(worktreePath: worktree.path, branch: branch)
        } catch {
            let remote = "origin/" + branch
            guard target == remote,
                  let tip = await git.commitHash(of: remote, worktreePath: worktree.path)
            else {
                throw error
            }

            overwriteTips.remember(tip, worktreePath: worktree.path, branch: branch)
            try await git.rebaseSigned(worktreePath: worktree.path, branch: branch, onto: "origin/HEAD")
        }
    }

    /// What a signed rebase would actually change, so the button
    /// dims or names its work: moving the branch onto a newer base,
    /// signing unsigned commits, both, or nothing at all.
    enum RebaseNeed: Sendable {
        case nothing
        case rebase
        case sign
        case rebaseAndSign
    }

    /// The rebase button's work, judged from local refs; the action
    /// itself fetches first, so a stale answer only mislabels until
    /// the next reload.
    func rebaseNeed(worktree: Worktree) async -> RebaseNeed {
        // The caller's branch, which for a stack is the entry being
        // looked at rather than whichever one the worktree holds.
        let branch = worktree.branch
        let target = await signedRebaseTarget(worktreePath: worktree.path, branch: branch)
        let movesBase = await (git.aheadBehind(worktreePath: worktree.path, baseRef: target)?.behind ?? 0) > 0
        // With signing waived there is never a sign-only need, and
        // the rebase itself stops passing --gpg-sign.
        let needsSigning =
            if AppSettings.requiresSignedCommits {
                await git.allCommitsSigned(
                    worktreePath: worktree.path,
                    range: target + ".." + branch,
                ) == false
            } else {
                false
            }
        switch (movesBase, needsSigning) {
        case (true, true):
            return .rebaseAndSign

        case (true, false):
            return .rebase

        case (false, true):
            return .sign

        case (false, false):
            return .nothing
        }
    }

    /// The ref a signed rebase lands on. The branch's own origin ref
    /// wins when it exists, is still an ancestor of the branch,
    /// every commit unique to it verifies and local commits sit on
    /// top needing signatures: rebasing there signs only the new
    /// commits, so pushed history keeps its hashes. Anything else
    /// falls back to origin/HEAD, re-signing the whole branch, with
    /// one exception: a remote that moved to a tip this branch
    /// never had is rebased on rather than around, since the leased
    /// push refuses to overwrite commits that were never integrated
    /// and nothing else would ever integrate them.
    ///
    /// The branch's reflog is what tells that apart from an amend.
    /// Amending a pushed commit leaves the pushed one behind as a
    /// stale twin rather than a parent, and rebasing on it would
    /// replay the amended work on top of what it replaced; but the
    /// twin was once this branch's own tip, and a tip pushed
    /// elsewhere never was.
    func signedRebaseTarget(worktreePath: String, branch: String) async -> String {
        let remote = "origin/" + branch
        guard await git.remoteBranchExists(worktreePath: worktreePath, branch: branch) else {
            return "origin/HEAD"
        }
        guard await git.isAncestor(remote, of: "HEAD", worktreePath: worktreePath) else {
            let wasOurs = await git.refWasBranchTip(worktreePath: worktreePath, branch: branch, ref: remote)
            return wasOurs ? "origin/HEAD" : remote
        }

        // With signing waived the pushed commits need no verifying:
        // the point of preferring the branch's own origin ref is
        // keeping pushed history's hashes, which holds either way.
        let pushedSigned =
            if AppSettings.requiresSignedCommits {
                await git.allCommitsSigned(worktreePath: worktreePath, range: "origin/HEAD.." + remote)
            } else {
                true
            }
        guard pushedSigned,
              await (git.commitCount(worktreePath: worktreePath, range: remote + "..HEAD") ?? 0) > 0
        else {
            return "origin/HEAD"
        }

        return remote
    }
}
