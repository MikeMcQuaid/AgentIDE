import AgentIDEData
import AgentIDEDomain
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

    /// Creates a session from a typed prompt.
    func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run(in: repository, placeholder: Self.placeholderName(from: prompt)) {
            try await service.createSession(
                repository: repository,
                prompt: prompt,
                agent: agent,
                options: options,
            )
        }
    }

    /// Creates a session working on a GitHub issue.
    func createSession(
        fromIssue number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run(in: repository, placeholder: "issue-\(number)") {
            try await service.createSession(
                fromIssue: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
            )
        }
    }

    /// Creates a session on a pull request's own branch.
    func createSession(
        fromPullRequest number: Int,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions = AgentLaunchOptions(),
    ) async {
        await run(in: repository, placeholder: "pr-\(number)") {
            try await service.createSession(
                fromPullRequest: number,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
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
        await run {
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
        await run {
            try await service.launchAgent(
                fromIssue: number,
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
    private func run(
        in repository: Repository? = nil,
        placeholder: String? = nil,
        _ work: () async throws -> String,
    ) async {
        // Only creation shows a placeholder: launching an agent in an
        // existing worktree has a real row already.
        let pending = repository.flatMap { repository in
            placeholder.map { insertPlaceholder(in: repository, branch: $0) }
        }
        launchProgress.begin("Starting")
        showsNewSession = false
        if let pending {
            selection = pending
        }
        defer {
            if let pending {
                removePlaceholder(pending)
            }
        }
        do {
            screenError = nil
            let sessionName = try await work()
            rememberLaunch(sessionName: sessionName)
            await refreshUntil { items in items.contains { $0.session?.name == sessionName } }
            if let created = groups.flatMap(\.items).first(where: { $0.session?.name == sessionName }) {
                launchProgress.report("Listed; opening the pane of `" + sessionName + "`")
                selection = created
            } else {
                launchProgress.report("`" + sessionName + "` never appeared in a listing; select it by hand")
            }
        } catch {
            // Back to the form with the failure inline: it cannot
            // show the Errors tab from there.
            showsNewSession = true
            selection = nil
            screenError = error.localizedDescription
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Re-reads the system until the listing satisfies a condition,
    /// narrating the wait: a reading takes seconds (git in every
    /// worktree, the herdr snapshot) and one the poll's own reading
    /// supersedes is discarded, so the first reading after a launch
    /// did not always list the new session, and nothing switched to
    /// it. Bounded, so a session that truly never lists cannot hold
    /// the page forever.
    func refreshUntil(_ isListed: ([WorktreeItem]) -> Bool) async {
        launchProgress.report("Reading every worktree and session again to list it")
        for attempt in 0 ..< Self.listingAttempts {
            await refresh()
            if isListed(groups.flatMap(\.items)) {
                return
            }
            if attempt == 0 {
                launchProgress.report("Not listed yet; reading again every half second")
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
        let path = repository.path + Self.placeholderMarker + branch
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
            hasUnread: false,
        )
        deletingPaths.insert(path)
        if let index = groups.firstIndex(where: { $0.repository.path == repository.path }) {
            // Right under the main checkout, where the newest work
            // sorts anyway.
            groups[index].items.insert(item, at: min(1, groups[index].items.count))
        }
        return item
    }

    /// Drops the placeholder; a refresh has usually replaced the
    /// whole group by then, so this only cleans up after a failure.
    private func removePlaceholder(_ item: WorktreeItem) {
        deletingPaths.remove(item.worktree.path)
        for index in groups.indices {
            groups[index].items.removeAll { $0.worktree.path == item.worktree.path }
        }
    }
}

public extension WorktreeItem {
    /// Whether this is the greyed provisional row a new session
    /// shows while its real worktree is created; the app's primary
    /// pane shows creation progress for it instead of a worktree.
    var isPlaceholder: Bool {
        worktree.path.contains(DashboardModel.placeholderMarker)
    }
}
