import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The repository's pull requests: a paginated title list clicking
/// through to each pull request's conversation and actions.
public struct PullRequestsView: View {
    // MARK: Lifecycle

    /// Creates the pull request list for a repository, filtered to
    /// one branch when given.
    public init(
        repository: Repository,
        items: [WorktreeItem],
        github: GitHubClient,
        service: SessionService,
        branch: String? = nil,
    ) {
        self.repository = repository
        self.items = items
        self.github = github
        self.service = service
        self.branch = branch
    }

    // MARK: Public

    /// The scope picker over the list or the selected conversation.
    public var body: some View {
        VStack(spacing: 0) {
            scopePicker
            Divider()
            if let selected {
                conversation(for: selected)
            } else {
                listView
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        // The branch joins the identity so switching worktrees in
        // the same repository reloads the list.
        .task(id: repository.id + scopeIdentity + (branch ?? "")) { await reload() }
        .task(id: repository.id) {
            hasMergeQueue = await github.hasMergeQueue(repositoryPath: repository.path)
        }
    }

    // MARK: Private

    private enum Scope: Hashable {
        case worktree
        case mine
        case open
    }

    private static let footerPadding: CGFloat = 8
    private static let rowSpacing: CGFloat = 4

    @State private var scope: Scope = .worktree
    @State private var summaries: [PullRequestSummary] = []
    @State private var selected: PullRequestSummary?
    @State private var isLoading = false
    @State private var page = 0
    @State private var hasMergeQueue = false
    @State private var status: String?

    private let repository: Repository
    private let items: [WorktreeItem]
    private let github: GitHubClient
    private let service: SessionService
    private let branch: String?

    private var scopeIdentity: String {
        String(describing: scope)
    }

    private var listScope: GitHubClient.ListScope {
        switch scope {
        case .worktree:
            .branch(branch ?? "")

        case .mine:
            .mine

        case .open:
            .open
        }
    }

    /// Push makes sense with unpushed commits or without an open
    /// pull request for this worktree's branch; nil upstream means
    /// nothing was ever pushed.
    private var canShip: Bool {
        guard let item = items.first(where: { $0.worktree.branch == branch }) else {
            return false
        }

        let hasOpen = summaries.contains { $0.headBranch == branch && $0.state == "OPEN" }
        return (item.aheadOfUpstream ?? 1) > 0 || hasOpen == false
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            Text("Worktree").tag(Scope.worktree)
            Text("Mine").tag(Scope.mine)
            Text("Open").tag(Scope.open)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(Self.footerPadding)
        .hoverHelp(
            "Worktree: this branch's pull requests, open and closed. Mine: open ones you created. Open: every open one",
        )
    }

    private var listView: some View {
        PullRequestListView(
            summaries: summaries,
            isLoading: isLoading,
            stackDepth: { stackDepth(for: $0) },
            onSelect: { selected = $0 },
            page: $page,
        )
    }

    private var footer: some View {
        HStack {
            Button("Push and open PR") { Task { await ship() } }
                .disabled(canShip == false)
                .hoverHelp(
                    canShip
                        ? "Push this worktree's branch and open a pull request; a repository template fills the body"
                        : "Everything is pushed and this branch already has an open pull request",
                )
            Button("Refresh") { Task { await reload(keepingSelection: true) } }
                .hoverHelp("Fetch the pull requests again")
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Self.footerPadding)
        .background(.bar)
    }

    private func conversation(for summary: PullRequestSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.rowSpacing) {
                Button("Back to the list", systemImage: "chevron.backward") { selected = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverHelp("Back to the pull request list")
                PullRequestRowView(
                    summary: summary,
                    canRemediate: worktree(for: summary) != nil,
                    stackDepth: stackDepth(for: summary),
                    hasMergeQueue: hasMergeQueue,
                    onAutomerge: {
                        act {
                            try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number)
                        }
                    },
                    onMerge: {
                        act { try await github.merge(repositoryPath: repository.path, number: summary.number) }
                    },
                    onRemediate: { act { try await remediate(summary) } },
                )
            }
            .padding(.horizontal, Self.footerPadding)
            Divider()
            PullRequestConversationView(
                github: github,
                repositoryPath: repository.path,
                number: summary.number,
            )
        }
    }

    private func ship() async {
        guard let item = items.first(where: { $0.worktree.branch == branch }) else {
            return
        }

        do {
            status = try await service.pushAndCreatePullRequest(worktree: item.worktree)
            await reload(keepingSelection: true)
        } catch {
            status = error.localizedDescription
        }
    }

    private func worktree(for summary: PullRequestSummary) -> Worktree? {
        items.first { $0.worktree.branch == summary.headBranch }?.worktree
    }

    /// The stack size, following base branches that are other listed
    /// pull requests' heads.
    private func stackDepth(for summary: PullRequestSummary) -> Int {
        let byHead = Dictionary(summaries.map { ($0.headBranch, $0) }) { first, _ in first }
        var current = summary
        var depth = 1
        var seen = Set([current.headBranch])
        while let next = byHead[current.baseBranch], seen.insert(next.headBranch).inserted {
            depth += 1
            current = next
        }
        return depth
    }

    /// The list empties and shows its loading state instantly; a
    /// kept selection is re-selected once the fetch answers, and a
    /// single result opens its conversation directly.
    private func reload(keepingSelection: Bool = false) async {
        let previous = keepingSelection ? selected?.number : nil
        isLoading = true
        summaries = []
        selected = nil
        page = 0
        defer { isLoading = false }
        do {
            let fetched = try await github.pullRequests(repositoryPath: repository.path, scope: listScope)
            summaries = fetched
            selected = fetched.first { $0.number == previous }
                ?? (fetched.count == 1 ? fetched.first : nil)
        } catch {
            status = error.localizedDescription
        }
    }

    private func remediate(_ summary: PullRequestSummary) async throws {
        guard let worktree = worktree(for: summary) else {
            return
        }

        let context = await github.remediationContext(repositoryPath: repository.path, number: summary.number)
        let prompt = """
        Address the following review comments and failing checks on pull request #\(summary.number), \
        then commit your fixes. Do not push.

        \(context)
        """
        _ = try await service.launchAgent(in: worktree, prompt: prompt, agent: .claudeCode)
        status = "Fix agent launched for #\(summary.number)."
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                status = "Done."
                await reload(keepingSelection: true)
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
