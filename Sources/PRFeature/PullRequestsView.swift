import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The repository's pull requests: a paginated title list clicking
/// through to each pull request's conversation and actions. The
/// view renders and binds; PullRequestsModel owns the behaviour.
public struct PullRequestsView: View {
    // MARK: Lifecycle

    /// Creates the pull request list for a repository, filtered to
    /// one branch when given; the store caches listings and
    /// conversations between sessions.
    public init(
        repository: Repository,
        items: [WorktreeItem],
        github: GitHubClient,
        service: SessionService,
        store: MetadataStore,
        branch: String? = nil,
    ) {
        self.items = items
        identity = repository.id + "#" + (branch ?? "")
        makeModel = {
            PullRequestsModel(
                repository: repository,
                branch: branch,
                items: items,
                github: github,
                service: service,
                store: store,
            )
        }
        _model = State(initialValue: makeModel())
    }

    // MARK: Public

    /// The scope picker over the list or the selected conversation.
    public var body: some View {
        VStack(spacing: 0) {
            PullRequestScopePicker(scope: $model.scope)
            Divider()
            if let selected = model.selected {
                conversation(for: selected)
            } else {
                listView
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        // The model is rebuilt whenever the repository or branch
        // changes: state objects outlive view re-initialisation, so
        // the last worktree's list would otherwise linger.
        .task(id: identity) {
            model = makeModel()
            await model.loadMergeQueue()
        }
        // The scope joins the reload identity so switching scopes
        // refetches without rebuilding the model.
        .task(id: identity + model.scopeIdentity) { await model.reload() }
        .onChange(of: items) { model.items = items }
    }

    // MARK: Internal

    /// The repository's worktree items, forwarded into the model as
    /// the dashboard polls so push and rebase states stay current.
    let items: [WorktreeItem]

    // MARK: Private

    /// The errors tab's position in the utility tab order, driven
    /// through the storage signal bus.
    private static let errorsTabIndex = 5

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage("utilityTabIndex")
    private var utilityTabIndex = 0

    @State private var model: PullRequestsModel

    /// The repository and branch as a task identity: it comes from
    /// the view's own inputs, never the persisted model, so a
    /// repository switch always rebuilds.
    private let identity: String

    private let makeModel: () -> PullRequestsModel

    private var listView: some View {
        PullRequestListView(
            summaries: model.summaries,
            isLoading: model.isLoading,
            hasMore: model.hasMore,
            stackDepth: { model.stackDepth(for: $0) },
            onSelect: { model.select($0) },
            page: $model.page,
        )
    }

    private var footer: some View {
        PullRequestFooterView(
            canPush: model.canPush,
            canOpenPullRequest: model.canOpenPullRequest,
            canRebase: model.branchItem != nil,
            status: model.status,
            onPush: { Task { await model.push() } },
            onOpenPullRequest: { Task { await model.ship() } },
            onRebase: {
                Task {
                    if await model.rebaseSigned() == false {
                        utilityTabIndex = Self.errorsTabIndex
                    }
                }
            },
            onRefresh: { Task { await model.reload(keepingSelection: true) } },
        )
    }

    private func conversation(for summary: PullRequestSummary) -> some View {
        PullRequestConversationPane(
            summary: summary,
            canRemediate: model.worktree(for: summary) != nil,
            stackDepth: model.stackDepth(for: summary),
            hasMergeQueue: model.hasMergeQueue,
            github: model.github,
            repositoryPath: model.repository.path,
            store: model.store,
            onBack: { model.selected = nil },
            onAutomerge: {
                model.act { try await model.github.enableAutomerge(
                    repositoryPath: model.repository.path,
                    number: summary.number,
                )
                }
            },
            onMerge: {
                model.act { try await model.github.merge(
                    repositoryPath: model.repository.path,
                    number: summary.number,
                )
                }
            },
            onRemediate: { model.act { try await model.remediate(summary) } },
        )
    }
}
