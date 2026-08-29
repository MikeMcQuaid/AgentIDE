import AgentIDEDomain

// MARK: - PushDestination

/// Where a branch can be pushed: the repository it came from, or the
/// viewer's own fork of it when they may not write there.
public enum PushDestination: Hashable, Sendable {
    case origin
    case fork(owner: String)

    // MARK: Public

    /// How `gh pr create` must name the branch: `owner:branch` when
    /// it lives in a fork, since the pull request belongs to the
    /// repository it is opened against rather than the one holding
    /// the branch, and the plain name otherwise. Never nil: left to
    /// itself `gh` opens a pull request for whatever is checked out,
    /// which in a stack of branches in one worktree is rarely the
    /// branch being looked at.
    public func head(branch: String) -> String {
        guard case let .fork(owner) = self else {
            return branch
        }

        return owner + ":" + branch
    }
}

// MARK: - MergeCleanupReport

/// What a post-merge cleanup did and what it could not do, so the
/// caller can put both in the messages pane rather than the work
/// happening silently.
public struct MergeCleanupReport: Sendable {
    // MARK: Lifecycle

    /// Creates an empty report.
    public init() {
        // Both lists fill as the cleanup runs.
    }

    // MARK: Public

    /// What the cleanup did, in order.
    public var notes: [String] = []

    /// What it could not do, each naming the step and the reason.
    public var failures: [String] = []
}

// MARK: - Pull requests

/// Pushing branches, drafting and opening pull requests, and
/// tidying up after a merge.
public extension SessionService {
    /// Every pull request question goes through here, which holds
    /// the answers and when each was last asked for.
    internal var pullRequests: PullRequestStore {
        PullRequestStore(github: github, store: store)
    }

    /// The same store, for the feature modules: a view asking about
    /// a pull request must go through the app's one gate, not build
    /// a query of its own.
    var pullRequestReads: PullRequestStore {
        pullRequests
    }

    /// Pushes the branch to origin without opening anything. An
    /// unsigned tip refuses: every pushed commit must be GPG signed
    /// (a local hook enforces the same), and Rebase on origin is the
    /// signing path.
    func push(worktree: Worktree) async throws -> PushDestination {
        if AppSettings.requiresSignedCommits,
           await git.isCommitSigned(worktreePath: worktree.path, ref: worktree.branch) == false {
            throw SessionServiceError(
                "The tip commit is not GPG signed; Rebase on origin signs the branch before pushing.",
            )
        }

        let destination = await pushDestination(worktree: worktree)
        guard case let .fork(owner) = destination else {
            try await git.push(
                worktreePath: worktree.path,
                branch: worktree.branch,
                expectedTip: overwriteTips.tip(worktreePath: worktree.path, branch: worktree.branch),
            )
            overwriteTips.forget(worktreePath: worktree.path, branch: worktree.branch)
            return destination
        }

        try await github.ensureFork(worktreePath: worktree.path, remoteName: owner)
        try await git.push(worktreePath: worktree.path, branch: worktree.branch, remote: owner)
        return destination
    }

    /// Opens the pull request for a worktree's branch, naming the
    /// branch as `owner:branch` when it lives in a fork: the pull
    /// request belongs to the repository it is opened against rather
    /// than the one holding the branch.
    func createPullRequest(worktree: Worktree, title: String, body: String) async throws -> String {
        // The branch is the caller's, which is the entry whose form
        // was filled in, never whatever the worktree has checked out.
        // A branch opening against the branch below it is what makes
        // GitHub show a stack, and the bottom of one opens against
        // the default branch exactly as a lone branch does. Both ends
        // are named: `gh` left to work either out for itself takes
        // whatever is checked out as the head, which in a stack is
        // rarely the branch being opened.
        let stack = await stack(for: worktree)
        let branch = worktree.branch
        return try await github.createPullRequest(
            worktreePath: worktree.path,
            title: title,
            body: body,
            head: pushDestination(worktree: worktree).head(branch: branch),
            base: base(for: branch, in: stack, of: worktree),
        )
    }

    /// Asks GitHub to show the stack's open pull requests as a
    /// stack, bottom up, which is what makes them a stack there
    /// rather than pull requests that happen to chain. Read fresh
    /// rather than from the cache, which may be a minute behind the
    /// pull request just opened. `gh stack link` adds to a stack it
    /// already knows and never removes from one, so repeating it
    /// whenever a pull request opens is safe, and two is the fewest
    /// that make a stack.
    func linkStack(worktree: Worktree) async throws {
        let stack = await stack(for: worktree)
        var numbers = [Int]()
        for branch in stack.branches {
            let listed = try? await github.pullRequests(
                repositoryPath: worktree.repositoryPath,
                scope: .branch(branch),
            )
            if let open = listed?.first(where: { $0.state == "OPEN" }) {
                numbers.append(open.number)
            }
        }
        guard numbers.count >= Self.linkableCount else {
            return
        }

        try await github.linkStack(worktreePath: worktree.path, numbers: numbers)
    }

    /// The repository's default branch by name, nil when neither
    /// the remote's head nor a local main or master says what it is.
    func defaultBranchName(of repository: Repository) async -> String? {
        await git.defaultBaseRef(of: repository).map(Self.branchName(fromBaseRef:))
    }

    /// What a pull request for this branch opens against: the branch
    /// below it in its stack, else the repository's default branch,
    /// read from git and, for a clone whose remote was never given a
    /// head, from GitHub itself. Never left to `gh` to work out.
    func base(for branch: String, in stack: BranchStack, of worktree: Worktree) async throws -> String {
        let parent = stack.parent(of: branch)
        if let parent, parent != stack.base {
            return parent
        }

        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        if let local = await defaultBranchName(of: repository) {
            return local
        }
        guard let asked = await github.defaultBranch(repositoryPath: worktree.path) else {
            throw SessionServiceError(repository.name + " has no default branch to open against.")
        }

        return asked
    }

    /// Merges a stacked pull request and every one below it.
    func mergeStack(worktree: Worktree, number: Int) async throws {
        try await github.mergeStack(repositoryPath: worktree.repositoryPath, number: number)
    }

    /// Where this branch belongs: the repository itself when GitHub
    /// says the branch may be pushed there, and the viewer's own fork
    /// of it otherwise.
    func pushDestination(worktree: Worktree) async -> PushDestination {
        guard await github.canPush(worktreePath: worktree.path) == false,
              let owner = await github.viewer(worktreePath: worktree.path)
        else {
            return .origin
        }

        return .fork(owner: owner)
    }

    /// Whether the worktree's tip commit is GPG signed, gating Push.
    func isTipSigned(worktree: Worktree) async -> Bool {
        await git.isCommitSigned(worktreePath: worktree.path, ref: worktree.branch)
    }

    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable.
    func currentBranch(worktreePath: String) async -> String? {
        await git.currentBranch(worktreePath: worktreePath)
    }

    /// The branch's full commit messages beyond origin/HEAD, oldest
    /// first, for drafting pull request descriptions.
    /// The effort an agent runs at when no flag names one, for the
    /// disclosure of a session started on the picker's defaults.
    func defaultEffort(for agent: AgentKind) -> String? {
        runner(for: agent).defaultEffort
    }

    /// The commits a pull request would carry: `range` names a stack
    /// entry's own span (`parent..branch`), nil the checked-out
    /// branch against the default.
    func commitMessages(worktree: Worktree, range: String? = nil) async -> [String] {
        guard let span = await resolvedSpan(worktree: worktree, range: range) else {
            return []
        }

        return await git.commitMessages(worktreePath: worktree.path, range: span)
    }

    /// How many commits a branch has of its own, which is how many a
    /// pull request for it would carry.
    func commitCount(worktree: Worktree, range: String? = nil) async -> Int {
        guard let span = await resolvedSpan(worktree: worktree, range: range) else {
            return 0
        }

        return await git.commitCount(worktreePath: worktree.path, range: span) ?? 0
    }

    /// The span a range names, with `origin/HEAD` resolved.
    private func resolvedSpan(worktree: Worktree, range: String?) async -> String? {
        // `origin/HEAD` names the default branch symbolically; a
        // worktree whose remote never had its head set cannot
        // resolve it, and git then listed the branch back to the
        // root, every merged pull request included. The resolved
        // default base stands in for it.
        var span = range ?? "origin/HEAD..HEAD"
        if span.hasPrefix("origin/HEAD..") {
            // From where the branch forked off the remote's default
            // branch, not from a local `main` that may sit commits
            // behind it and drag every one of them into the list.
            let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
            let branch = String(span.dropFirst("origin/HEAD..".count))
            // `origin/HEAD` itself when the worktree resolves it,
            // then the remote's default branch; never a bare local
            // name, which may sit commits behind the remote and drag
            // its missing history into the branch's own span.
            var fork = await git.mergeBase("origin/HEAD", branch, worktreePath: worktree.path)
            let name = await defaultBranchName(of: repository) ?? "main"
            if fork == nil {
                fork = await git.mergeBase("origin/" + name, branch, worktreePath: worktree.path)
            }
            if fork == nil {
                // No remote at all: the local default branch is the
                // only base there is, and the honest one.
                fork = await git.mergeBase(name, branch, worktreePath: worktree.path)
            }
            guard let fork else {
                return nil
            }

            span = fork + ".." + branch
        }
        return span
    }

    /// A pull request title and body drafted by the on-device model,
    /// nil when it is unavailable or unhelpful.
    func draftPullRequestDescription(fromCommits commits: [String]) async -> (title: String, body: String)? {
        await summariser.pullRequestDescription(fromCommits: commits)
    }

    /// A commit message drafted from a worktree's uncommitted diff,
    /// nil when the on-device model is unavailable or unhelpful.
    func draftCommitMessage(worktreePath: String) async -> String? {
        guard let diff = try? await git.uncommittedDiff(worktreePath: worktreePath), diff.isEmpty == false else {
            return nil
        }

        return await summariser.commitMessage(fromDiff: diff)
    }

    /// The pull request template completed from the commits by the
    /// on-device model, nil when it is unavailable or unhelpful.
    func fillPullRequestTemplate(fromCommits commits: [String], template: String) async -> String? {
        await summariser.filledTemplate(fromCommits: commits, template: template)
    }

    /// After merging from the main checkout: return to the default
    /// branch, reset it to origin when it carries nothing of its
    /// own, and delete the merged branch with `-d` so an unmerged
    /// branch survives. Dirty checkouts and worktrees other than
    /// the main checkout are left untouched.
    func cleanUpAfterMerge(worktree: Worktree, mergedBranch _: String) async -> MergeCleanupReport {
        var report = MergeCleanupReport()
        guard worktree.path == worktree.repositoryPath else {
            return report
        }
        guard await git.isDirty(worktreePath: worktree.path) == false else {
            report.failures.append("\(worktree.repositoryName) has uncommitted changes, so it was left alone.")
            return report
        }

        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        do {
            try await fetchIfStale(repositoryPath: worktree.repositoryPath, workingDirectory: worktree.path)
        } catch {
            report.failures.append("Fetching \(worktree.repositoryName) failed: " + error.localizedDescription)
        }
        guard let base = await git.defaultBaseRef(of: repository) else {
            report.failures.append("\(worktree.repositoryName) has no default branch to return to.")
            return report
        }

        // defaultBaseRef answers `origin/main` or a bare local name.
        let branch = Self.branchName(fromBaseRef: base)
        if await git.currentBranch(worktreePath: worktree.path) != branch {
            do {
                try await git.checkout(worktreePath: worktree.path, branch: branch)
                report.notes.append("Checked out \(branch) in \(worktree.repositoryName).")
            } catch {
                report.failures.append("Checking out \(branch) failed: " + error.localizedDescription)
                return report
            }
        }
        await catchUp(worktreePath: worktree.path, branch: branch, into: &report)
        await deleteMerged(worktreePath: worktree.path, branch: branch, into: &report)
        return report
    }

    /// Brings the default branch level with origin: a checkout with
    /// nothing of its own fast-forwards by reset, one carrying local
    /// commits rebases them on top so nothing is thrown away.
    private func catchUp(worktreePath: String, branch: String, into report: inout MergeCleanupReport) async {
        let upstream = "origin/" + branch
        guard let counts = await git.aheadBehind(worktreePath: worktreePath, baseRef: upstream) else {
            return
        }
        guard counts.behind > 0 || counts.ahead > 0 else {
            return
        }

        do {
            if counts.ahead == 0 {
                try await git.resetHard(worktreePath: worktreePath, ref: upstream)
                report.notes.append("Pulled \(branch) up to \(upstream).")
            } else {
                try await git.rebaseSigned(worktreePath: worktreePath, branch: branch, onto: upstream)
                report.notes.append("Rebased \(counts.ahead) local commits onto \(upstream).")
            }
        } catch {
            report.failures.append("Updating \(branch) failed: " + error.localizedDescription)
        }
    }

    /// Deletes every branch already merged into the default branch,
    /// not just the one that prompted the cleanup; `-d` refuses
    /// anything unmerged, so this cannot lose work.
    private func deleteMerged(worktreePath: String, branch: String, into report: inout MergeCleanupReport) async {
        let merged = await git.mergedBranches(worktreePath: worktreePath, into: branch)
        for name in merged {
            await git.deleteMergedBranch(worktreePath: worktreePath, branch: name)
        }
        let remaining = await git.mergedBranches(worktreePath: worktreePath, into: branch)
        let deleted = merged.filter { remaining.contains($0) == false }
        if deleted.isEmpty == false {
            report.notes.append("Deleted merged \(deleted.count == 1 ? "branch" : "branches"): "
                + deleted.joined(separator: ", ") + ".")
        }
        for name in remaining {
            report.failures.append("Deleting merged branch \(name) failed; it is still there.")
        }
    }
}
