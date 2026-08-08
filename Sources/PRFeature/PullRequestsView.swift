import AgentIDEData
import AgentIDEDomain
import SwiftUI

// MARK: - PullRequestsView

/// The repository's open pull requests with one-click actions.
public struct PullRequestsView: View {
    // MARK: Lifecycle

    /// Creates the pull request list for a repository.
    public init(repository: Repository, items: [WorktreeItem], github: GitHubClient, service: SessionService) {
        self.repository = repository
        self.items = items
        self.github = github
        self.service = service
    }

    // MARK: Public

    /// The list with merge, automerge and fix actions per row.
    public var body: some View {
        List(summaries) { summary in
            PullRequestRowView(
                summary: summary,
                canRemediate: worktree(for: summary) != nil,
                onAutomerge: {
                    act { try await github.enableAutomerge(repositoryPath: repository.path, number: summary.number) }
                },
                onMerge: { act { try await github.merge(repositoryPath: repository.path, number: summary.number) } },
                onRemediate: { act { try await remediate(summary) } },
            )
        }
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView("No open pull requests", systemImage: "arrow.triangle.pull")
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task(id: repository.id) { await reload() }
    }

    // MARK: Private

    private static let footerPadding: CGFloat = 8

    @State private var summaries: [PullRequestSummary] = []
    @State private var status: String?

    private let repository: Repository
    private let items: [WorktreeItem]
    private let github: GitHubClient
    private let service: SessionService

    private var footer: some View {
        HStack {
            Button("Refresh") { Task { await reload() } }
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Self.footerPadding)
        .background(.bar)
    }

    private func worktree(for summary: PullRequestSummary) -> Worktree? {
        items.first { $0.worktree.branch == summary.headBranch }?.worktree
    }

    private func reload() async {
        do {
            summaries = try await github.pullRequests(repositoryPath: repository.path)
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
    let onAutomerge: () -> Void
    let onMerge: () -> Void
    let onRemediate: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("#\(summary.number) \(summary.title)").font(.headline)
                Text(badges).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = URL(string: summary.url) {
                Link("Open", destination: url)
            }
            Button("Fix", action: onRemediate).disabled(canRemediate == false)
            Button("Automerge", action: onAutomerge)
            Button("Merge", action: onMerge)
        }
        .padding(.vertical, Self.rowPadding)
    }

    // MARK: Private

    private var badges: String {
        [summary.headBranch, summary.mergeable, summary.reviewDecision, summary.checks]
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
    }
}
