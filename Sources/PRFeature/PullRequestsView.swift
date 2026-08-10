import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestsView

/// The repository's open pull requests with one-click actions.
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

    /// The scope picker over the list, with merge, automerge and fix
    /// actions per row and each pull request's review comments
    /// beneath it.
    public var body: some View {
        VStack(spacing: 0) {
            scopePicker
            Divider()
            List(summaries) { summary in
                PullRequestRowView(
                    summary: summary,
                    canRemediate: worktree(for: summary) != nil,
                    commentCount: comments[summary.number]?.count,
                    stackDepth: stackDepth(for: summary),
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
                commentsSection(for: summary)
            }
            .overlay {
                if summaries.isEmpty {
                    ContentUnavailableView("No pull requests", systemImage: "arrow.triangle.pull")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        // The branch joins the identity so switching worktrees in
        // the same repository reloads the list.
        .task(id: repository.id + scopeIdentity + (branch ?? "")) { await reload() }
    }

    // MARK: Private

    private enum Scope: Hashable {
        case worktree
        case mine
        case open
    }

    private static let footerPadding: CGFloat = 8
    private static let commentSpacing: CGFloat = 4

    /// Comments are fetched per pull request, so wide scopes only
    /// fetch them for the first few.
    private static let commentFetchLimit = 5

    @State private var scope: Scope = .worktree

    @State private var summaries: [PullRequestSummary] = []
    @State private var comments: [Int: [ReviewComment]] = [:]
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

    private var footer: some View {
        HStack {
            Button("Refresh") { Task { await reload() } }
                .hoverHelp("Fetch the open pull requests again")
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Self.footerPadding)
        .background(.bar)
    }

    private func commentsSection(for summary: PullRequestSummary) -> some View {
        ForEach(comments[summary.number] ?? []) { comment in
            HStack(alignment: .firstTextBaseline, spacing: Self.commentSpacing) {
                Text(comment.author).font(.caption.bold())
                MarkdownText(comment.body)
                    .font(.caption)
            }
            .padding(.leading, Self.footerPadding)
            .hoverHelp("A review comment; Fix sends every comment and failing check to an agent")
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

    private func reload() async {
        do {
            summaries = try await github.pullRequests(repositoryPath: repository.path, scope: listScope)
            for summary in summaries.prefix(Self.commentFetchLimit) {
                comments[summary.number] = await github.reviewComments(
                    repositoryPath: repository.path,
                    number: summary.number,
                )
            }
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
                await reload()
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

// MARK: - PullRequestRowView

/// One pull request row with its badges and actions.
struct PullRequestRowView: View {
    // MARK: Internal

    static let rowPadding: CGFloat = 4

    let summary: PullRequestSummary
    let canRemediate: Bool
    let commentCount: Int?
    let stackDepth: Int
    let onAutomerge: () -> Void
    let onMerge: () -> Void
    let onRemediate: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                titleRow
                Text(badges).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
        .padding(.vertical, Self.rowPadding)
    }

    // MARK: Private

    private static let commentBadgeSpacing: CGFloat = 2

    private var badges: String {
        let state = summary.state == "OPEN" ? "" : summary.state
        // Approval shows as the tick beside the title instead.
        let decision = summary.reviewDecision == "APPROVED" ? "" : summary.reviewDecision
        return [state, summary.headBranch, summary.mergeable, decision]
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
    }

    private var stateHelp: String {
        if summary.state != "OPEN" {
            summary.state.capitalized + " pull request"
        } else if summary.isDraft {
            "Draft pull request"
        } else {
            "Open pull request"
        }
    }

    private var titleRow: some View {
        HStack(spacing: Self.rowPadding) {
            Octicon(
                ChecksStyle.stateOcticonName(state: summary.state, isDraft: summary.isDraft),
                colour: ChecksStyle.stateColour(state: summary.state, isDraft: summary.isDraft),
            )
            .hoverHelp(stateHelp)
            Button {
                LinkOpener.open(summary.url)
            } label: {
                Text("#" + String(summary.number)).font(.headline)
            }
            .buttonStyle(.plain)
            .hoverHelp("Open the pull request in the Browser tab; Cmd-click for the system browser")
            checksButton
            statusBadges
            Text(summary.title).font(.headline).lineLimit(1)
            if let commentCount, commentCount > 0 {
                HStack(spacing: Self.commentBadgeSpacing) {
                    Octicon("octicon-comment", colour: .secondary)
                    Text(String(commentCount)).font(.caption).foregroundStyle(.secondary)
                }
                .hoverHelp("Review and conversation comments")
            }
        }
    }

    @ViewBuilder private var statusBadges: some View {
        if let review = ChecksStyle.reviewOcticonName(for: summary.reviewDecision) {
            Octicon(review, colour: ChecksStyle.reviewColour(for: summary.reviewDecision))
                .hoverHelp("Review: " + summary.reviewDecision.lowercased())
        }
        if summary.hasAutomerge {
            Octicon("octicon-git-merge-queue", colour: .blue)
                .hoverHelp("Automerge enabled")
        }
        if stackDepth > 1 {
            Octicon("octicon-stack", colour: .secondary)
                .hoverHelp("Stacked: \(stackDepth) pull requests based on each other")
            Text(String(stackDepth)).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The same jump the sidebar's icon makes: the one failing run
    /// when there is exactly one, the checks page otherwise.
    private var checksButton: some View {
        Button {
            LinkOpener.open(summary.checksClickURL)
        } label: {
            Octicon(
                ChecksStyle.octiconName(for: summary.checks),
                colour: ChecksStyle.colour(for: summary.checks),
            )
            .accessibilityLabel("Checks: \(summary.checks.lowercased())")
        }
        .buttonStyle(.plain)
        .hoverHelp(
            summary.failingCheckLinks.count == 1
                ? "Open the one failing run in the Browser tab; Cmd-click for the system browser"
                : "Open the checks page in the Browser tab; Cmd-click for the system browser",
        )
    }

    @ViewBuilder private var actions: some View {
        Button("Fix", action: onRemediate)
            .disabled(canRemediate == false)
            .hoverHelp("Dump every review comment and failing check into an agent in this worktree")
        // One merge action, matching what the pull request can do
        // right now: merge when green and mergeable, automerge
        // while checks are still running.
        if summary.state == "OPEN" {
            if summary.checks == "SUCCESS", summary.mergeable == "MERGEABLE" {
                Button("Merge", action: onMerge)
                    .hoverHelp("Checks passed and the branch is mergeable: squash-merge now")
            } else {
                Button("Automerge", action: onAutomerge)
                    .hoverHelp("Not mergeable yet: merge automatically once checks and reviews pass")
            }
        }
    }
}
