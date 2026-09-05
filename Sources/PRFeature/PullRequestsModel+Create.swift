import AgentIDEDomain
import Foundation
import TerminalUI

/// Opening a pull request, and telling both surfaces about it at
/// once: the sidebar's row and this pane read one per-branch cache,
/// so what the form opens is on the row before any poll. Split from
/// the actions for length.
extension PullRequestsModel {
    /// Pushes every branch of the stack, bottom first, and says so
    /// as one push rather than as the branch in view: what went up
    /// is the whole stack.
    func pushWholeStack(_ worktree: Worktree) async -> Bool {
        do {
            let pushed = try await stacking.push(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            if let tip = await fetchTipCommit(worktree) {
                pushedTip = PushedTip(branch: listedBranch ?? worktree.branch, commit: tip)
            }
            recordFinished(.pushed, branch: listedBranch ?? worktree.branch)
            note("Pushed " + pushed.joined(separator: ", ") + ".")
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Opens the pull request from the form's title and body, with
    /// the template appended below the body after an empty line;
    /// false opens the errors surface. The button dims until the
    /// branch is pushed, so nothing pushes implicitly here.
    func createPullRequest() async -> Bool {
        guard let worktree = listedWorktree else {
            return false
        }

        let title = prTitle.trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            report("The pull request needs a title.")
            return false
        }

        let template = prTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = prBody + (template.isEmpty ? "" : "\n\n" + template)
        isOpening = true
        defer { isOpening = false }
        do {
            let url = try await performCreate(worktree, title, body, prLabels, prIsDraft)
            note("Opened pull request " + url)
            // A stack is built one pull request at a time: each one
            // links what is open into the stack, and failing to link
            // never takes the pull request that opened with it.
            do {
                try await performLinkStack(worktree)
            } catch {
                report("Stacking on GitHub failed: " + error.localizedDescription)
            }
            pullRequests.invalidateListings(repositoryPath: repository.path)
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            // Straight into what was just opened: the listing has it
            // by number, and its conversation is what the form was
            // for. Only once it is showing does the form let go of
            // the text, so nothing blank is ever on screen.
            // The sidebar reads the same per-branch cache, so what
            // was just opened is on its row now rather than at the
            // next poll: GitHub's own answer when the listing has
            // caught up, otherwise what the form knows.
            let created = Self.created(
                url: url,
                title: title,
                worktree: worktree,
                base: defaultBranch,
                listed: summaries,
                isDraft: prIsDraft,
            )
            if let created {
                cacheCreated(created, branch: worktree.branch)
                select(created)
            }
            loadingDraft = true
            prTitle = ""
            prLabels = []
            prBody = ""
            prTemplate = originalTemplate
            loadingDraft = false
            clearDraft()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Pushes the checked-out branch; false means the push failed
    /// and the errors tab should open with the cause.
    func push() async -> Bool {
        guard let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        // The button dims on what the last read knew, and a tip
        // amended since then must never reach the service's refusal
        // as an error: the signature is read again at the click, and
        // a failed check declines in the footer instead, with Rebase
        // relit to sign.
        guard await checkTipSigned(worktree) else {
            tipSignature = .unsigned
            rebaseNeed = await fetchRebaseNeed(worktree)
            setStatus(
                "Not pushed: the tip commit is unsigned.",
                detail: "The tip commit of " + worktree.branch
                    + " is not GPG signed; Rebase on origin signs the branch, then Push.",
            )
            return true
        }

        do {
            // A branch of a stack never goes up alone: the ones
            // above it are built on this tip, and pushing it by
            // itself leaves GitHub reading their parents as gone.
            guard stacking.stack.isStacked == false else {
                return await pushWholeStack(worktree)
            }

            let destination = try await performPush(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            if let tip = await fetchTipCommit(worktree) {
                pushedTip = PushedTip(branch: listedBranch ?? worktree.branch, commit: tip)
            }
            recordFinished(.pushed, branch: listedBranch ?? worktree.branch)
            note(Self.describe(push: destination, branch: worktree.branch))
            Self.requestSidebarRefresh()
            await reload(keepingSelection: true)
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// What a just-opened pull request is, for the row and the pane:
    /// the listing's own answer where GitHub has caught up, else the
    /// bare facts the form knows, which the next fetch replaces.
    static func created(
        url: String,
        title: String,
        worktree: Worktree,
        base: String?,
        listed: [PullRequestSummary],
        isDraft: Bool = false,
    ) -> PullRequestSummary? {
        guard let number = number(inURL: url) else {
            return nil
        }

        // The creation's own answer is the pull request's page, so
        // opening it in a browser, and the checks link beside it,
        // work before any fetch has been near it.
        return listed.first { $0.number == number } ?? PullRequestSummary(
            number: number,
            title: title,
            url: url,
            headBranch: worktree.branch,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            baseBranch: base ?? "",
            state: "OPEN",
            isDraft: isDraft,
        )
    }

    /// Records a new pull request where both surfaces read it, and
    /// asks the sidebar to repaint from it at once.
    func cacheCreated(_ summary: PullRequestSummary, branch: String) {
        pullRequests.rememberBranchSummary(summary, repositoryPath: repository.path, branch: branch)
        cacheEnriched(summary)
        let key = UtilityTabTarget.pullRequestCacheKey
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
