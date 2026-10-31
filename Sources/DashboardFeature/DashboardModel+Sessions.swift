import Foundation
import SanductorData
import SanductorDomain
import TerminalUI

/// Session creation: every entry point funnels through one runner
/// that closes the form, refreshes and selects the new worktree.
public extension DashboardModel {
    /// Forgets a worktree's session without waiting to be told: a
    /// finished pane is still a session, so closing one only cleared
    /// the pane once the next reading of herdr landed, and a kill
    /// herdr was slow to finish left the agent pane on screen as
    /// though the button had done nothing.
    func forgetSession(at worktreePath: String) {
        for groupIndex in groups.indices {
            let items = groups[groupIndex].items
            for itemIndex in items.indices where items[itemIndex].worktree.path == worktreePath {
                groups[groupIndex].items[itemIndex] = items[itemIndex].withoutSession()
            }
        }
        if selection?.worktree.path == worktreePath {
            selection = groups.flatMap(\.items).first { $0.worktree.path == worktreePath }
        }
    }

    /// Creates a session from a typed prompt; public for the App
    /// Intents, which start work from Shortcuts and Siri, and answer
    /// with the failure when there is one.
    @discardableResult
    func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
        baseBranch: String? = nil,
    ) async -> LaunchFailure? {
        let draft = LaunchDraft(text: prompt, source: .prompt, agent: agent, options: options, base: baseBranch)
        return await run(draft, in: repository, placeholder: Self.placeholderName(from: prompt)) { service in
            try await service.createSession(
                repository: repository,
                prompt: prompt,
                agent: agent,
                options: options,
                baseBranch: baseBranch,
            )
        }
    }

    /// Creates a session working on a GitHub issue; `reveals` is
    /// false for every launch of several picks but the first.
    func createSession(
        fromIssue number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
        baseBranch: String? = nil,
        reveals: Bool = true,
    ) async {
        let draft = LaunchDraft(
            text: context, source: .issue, agent: agent, options: options, number: number, base: baseBranch,
        )
        await run(draft, in: repository, placeholder: "issue-\(number)", reveals: reveals) { service in
            try await service.createSession(
                fromIssue: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
                baseBranch: baseBranch,
            )
        }
    }

    /// Creates a session on a pull request's own branch; `reveals` as
    /// for issues.
    func createSession(
        fromPullRequest number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
        reveals: Bool = true,
    ) async {
        // One launch per pull request at a time: a second found the
        // first's worktree before its agent was running, and killed
        // that agent to start its own. A launch holds a progress log
        // under its placeholder's path until it ends.
        let pending = repository.path + Self.placeholderMarker + "pr-\(number)-"
        guard launchProgresses.keys.contains(where: { $0.hasPrefix(pending) }) == false else {
            return
        }

        let draft = LaunchDraft(text: context, source: .pullRequest, agent: agent, options: options, number: number)
        await run(draft, in: repository, placeholder: "pr-\(number)", reveals: reveals) { service in
            try await service.createSession(
                fromPullRequest: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Creates a session fixing a security advisory, on a branch that
    /// names nothing.
    func createSession(
        fromAdvisory ghsaID: String,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
        baseBranch: String? = nil,
    ) async {
        let draft = LaunchDraft(
            text: context, source: .advisory, agent: agent, options: options, ghsaID: ghsaID, base: baseBranch,
        )
        await run(draft, in: repository, placeholder: SessionService.advisoryBranch) { service in
            try await service.createSession(
                fromAdvisory: ghsaID,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
                baseBranch: baseBranch,
            )
        }
    }

    /// Starts an agent in an existing worktree.
    func launchAgent(
        in worktree: Worktree,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        let draft = LaunchDraft(text: prompt, source: .prompt, agent: agent, options: options)
        await run(draft, at: worktree.path) { service in
            try await service.launchAgent(in: worktree, prompt: prompt, agent: agent, options: options)
        }
    }

    /// Starts an agent on an open issue in an existing worktree.
    func launchAgent(
        fromIssue number: Int,
        in worktree: Worktree,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        let draft = LaunchDraft(text: context, source: .issue, agent: agent, options: options, number: number)
        await run(draft, at: worktree.path) { service in
            try await service.launchAgent(
                fromIssue: number,
                in: worktree,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Starts an agent on a security advisory in an existing worktree.
    func launchAgent(
        fromAdvisory ghsaID: String,
        in worktree: Worktree,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        let draft = LaunchDraft(text: context, source: .advisory, agent: agent, options: options, ghsaID: ghsaID)
        await run(draft, at: worktree.path) { service in
            try await service.launchAgent(
                fromAdvisory: ghsaID,
                in: worktree,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Runs a session-creation action, closing the page, refreshing
    /// and selecting the new session's worktree so the agent is on
    /// screen immediately. Creation takes seconds (naming the branch
    /// on device, `git worktree add`, launching the agent), so a
    /// greyed placeholder row under a provisional name appears in
    /// the repository the instant the click lands and is selected;
    /// the real worktree replaces it on the refresh that follows.
    /// The launch narrates into a log of its own and stays on its own
    /// row, the placeholder or the worktree at `worktreePath`: it
    /// opens its pane only while that row is still selected, and a
    /// failure waits there with its draft for a retry, since another
    /// form or launch may have taken the screen since.
    @discardableResult
    private func run(
        _ draft: LaunchDraft,
        in repository: Repository? = nil,
        placeholder: String? = nil,
        at worktreePath: String? = nil,
        reveals: Bool = true,
        _ work: (SessionService) async throws -> String,
    ) async -> LaunchFailure? {
        // Only creation shows a placeholder: launching an agent in an
        // existing worktree has a real row already.
        let pending = repository.flatMap { repository in
            placeholder.map { insertPlaceholder(in: repository, branch: $0) }
        }
        let rowPath = pending?.worktree.path ?? worktreePath
        let progress = LaunchProgress()
        if let rowPath {
            launchFailures[rowPath] = nil
            launchProgresses[rowPath] = progress
        }
        defer {
            if let rowPath {
                launchProgresses[rowPath] = nil
            }
        }
        progress.begin("Starting")
        // A launch that leaves the selection alone leaves the page
        // over it alone too: one started from the pull request list
        // closed a new session form being filled in beside it.
        if reveals {
            showsNewSession = false
            if let pending {
                reveal(pending)
            }
        }
        do {
            // Told once per run, and never acted on: the steps are
            // the user's to take.
            if let advice = await service.sandboxKeychainAdvice() {
                ErrorLog.shared.report(advice)
            }
            let sessionName = try await work(service.reporting(to: progress.reporter))
            rememberLaunch(sessionName: sessionName)
            // herdr says when the agent settles, so the listing loop
            // below usually succeeds on its first reading.
            progress.report("Waiting for herdr to see the agent settle")
            await service.waitForAgentReady(sessionName: sessionName)
            await refreshUntil(narrating: progress) { items in items.contains { $0.session?.name == sessionName } }
            if let created = groups.flatMap(\.items).first(where: { $0.session?.name == sessionName }) {
                if selection.map({ $0.worktree.path == rowPath }) ?? true,
                   showsNewSession == false, showsRepositoryFinder == false
                {
                    progress.report("Listed; opening the pane of `" + sessionName + "`")
                    reveal(created)
                }
            } else {
                progress.report("`" + sessionName + "` never appeared in a listing; select it by hand")
            }
            if let pending {
                removePlaceholder(pending)
            }
            return nil
        } catch {
            return fail(with: error, draft: draft, rowPath: rowPath, pending: pending)
        }
    }

    /// Leaves a failed launch on its row, which becomes selectable:
    /// its pane is where the failure is read.
    private func fail(
        with error: any Error, draft: LaunchDraft, rowPath: String?, pending: WorktreeItem?,
    ) -> LaunchFailure {
        ErrorLog.shared.report(error.localizedDescription)
        let failure = LaunchFailure(message: error.localizedDescription, draft: draft)
        if let pending,
           let index = groups.firstIndex(where: { $0.repository.path == pending.worktree.repositoryPath }),
           groups[index].items.contains(where: { $0.id == pending.id }) == false
        {
            groups[index].items.insert(pending, at: min(1, groups[index].items.count))
        }
        if let rowPath {
            launchFailures[rowPath] = failure
            // Only a placeholder was greyed for the launch; a worktree
            // greyed by a deletion stays so.
            if rowPath.contains(Self.placeholderMarker) {
                deletingPaths.remove(rowPath)
            }
        }
        return failure
    }

    /// Re-reads the system until the listing satisfies a condition,
    /// narrating the wait into the launch's log, or the shared one: a
    /// reading takes seconds (git in every worktree, the herdr
    /// snapshot) and one the poll's own reading supersedes is
    /// discarded, so the first reading after a launch did not always
    /// list the new session, and nothing switched to it. Bounded, so
    /// a session that truly never lists cannot hold the page forever.
    func refreshUntil(narrating launch: LaunchProgress? = nil, _ isListed: ([WorktreeItem]) -> Bool) async {
        let progress = launch ?? launchProgress
        progress.report("Reading every worktree and session again to list it")
        for attempt in 0 ..< Self.listingAttempts {
            await refresh()
            if isListed(groups.flatMap(\.items)) {
                return
            }
            if attempt == 0 {
                progress.report("Not listed yet; reading again every half second")
            }
            // A cancelled sleep ends the wait: swallowing the
            // cancellation would spin the readings back to back.
            guard await (try? Task.sleep(for: .milliseconds(Self.listingRetryMilliseconds))) != nil else {
                return
            }
        }
    }

    private static let listingAttempts = 20
    private static let listingRetryMilliseconds = 500

    /// A provisional branch-style name from the prompt's first words,
    /// in the same underscore style the real name will have.
    static func placeholderName(from prompt: String) -> String {
        let words = prompt.split { $0.isLetter == false && $0.isNumber == false }
            .prefix(Self.placeholderWords)
            .map { $0.lowercased() }
        return words.isEmpty ? "new_session" : words.joined(separator: "_")
    }

    private static let placeholderWords = 4

    /// The path segment marking a creation placeholder's synthetic
    /// path; nothing real ever lives there.
    static let placeholderMarker = "/.pending/"

    /// Inserts a greyed placeholder row into the repository's group
    /// and marks it pending so the sidebar dims it and refuses
    /// re-selection while the real worktree is created.
    private func insertPlaceholder(in repository: Repository, branch: String) -> WorktreeItem {
        // Unique, since two launches can share a provisional name
        // (the same issue twice) and a row is known by its path.
        let path = repository.path + Self.placeholderMarker + branch + "-" + UUID().uuidString
        let item = WorktreeItem(
            worktree: Worktree(
                repositoryName: repository.name,
                repositoryPath: repository.path,
                branch: branch,
                path: path,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        deletingPaths.insert(path)
        if let index = groups.firstIndex(where: { $0.repository.path == repository.path }) {
            // Right under the main checkout, where the newest work
            // sorts anyway.
            groups[index].items.insert(item, at: min(1, groups[index].items.count))
        }
        return item
    }

    /// Drops the placeholder once its launch has started; a refresh
    /// has usually replaced the whole group by then already.
    private func removePlaceholder(_ item: WorktreeItem) {
        deletingPaths.remove(item.worktree.path)
        for index in groups.indices {
            groups[index].items.removeAll { $0.worktree.path == item.worktree.path }
        }
    }
}

public extension Worktree {
    /// Whether this is the greyed provisional row a new session
    /// shows while its real worktree is created; the app's primary
    /// pane shows creation progress for it instead of a worktree.
    var isPlaceholder: Bool {
        path.contains(DashboardModel.placeholderMarker)
    }
}

public extension WorktreeItem {
    /// See `Worktree.isPlaceholder`.
    var isPlaceholder: Bool {
        worktree.isPlaceholder
    }
}
