import AgentIDEData
import AgentIDEDomain
import TerminalUI

/// The footer's branch actions, split from the model body for
/// length.
extension PullRequestsModel {
    /// The branch item's worktree with the checked-out branch
    /// substituted, so pushes and pull requests act on what is
    /// actually checked out.
    var actionWorktree: Worktree? {
        guard let item = branchItem else {
            return nil
        }
        guard let currentBranch, currentBranch != item.worktree.branch else {
            return item.worktree
        }

        return Worktree(
            repositoryName: item.worktree.repositoryName,
            repositoryPath: item.worktree.repositoryPath,
            branch: currentBranch,
            path: item.worktree.path,
        )
    }

    /// Pushes when needed, then opens GitHub's pull request
    /// creation page for the branch in the Browser tab; false means
    /// something failed and the errors surface should open.
    func openPullRequestPage() async -> Bool {
        if canPush, await push() == false {
            return false
        }
        guard let branch = listedBranch ?? branchItem?.worktree.branch,
              let fullName = await fetchFullName()
        else {
            ErrorLog.shared.report("The repository's GitHub name is unknown; is it pushed to GitHub?")
            return false
        }

        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        LinkOpener.open("https://github.com/" + fullName + "/pull/new/" + encoded)
        return true
    }

    /// Pushes the checked-out branch; false means the push failed
    /// and the errors tab should open with the cause.
    func push() async -> Bool {
        guard let worktree = actionWorktree else {
            return true
        }

        do {
            try await performPush(worktree)
            isPushed = true
            status = "Pushed."
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    /// Rebases onto origin with signed commits; false means the
    /// rebase aborted and the errors tab should open with the cause.
    func rebaseSigned() async -> Bool {
        guard let worktree = actionWorktree else {
            return true
        }

        do {
            try await performRebase(worktree)
            status = "Rebased and signed."
            await reload(keepingSelection: true)
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            return false
        }
    }

    func remediate(_ summary: PullRequestSummary) async throws {
        guard let worktree = worktree(for: summary) else {
            return
        }

        let context = await fetchRemediationContext(summary.number)
        let prompt = """
        Address the following review comments and failing checks on pull request #\(summary.number), \
        then commit your fixes. Do not push.

        \(context)
        """
        _ = try await service.launchAgent(in: worktree, prompt: prompt, agent: .claudeCode)
        status = "Fix agent launched for #\(summary.number)."
    }

    func act(_ work: () async throws -> Void) async {
        do {
            try await work()
            status = "Done."
            await reload(keepingSelection: true)
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }
}
