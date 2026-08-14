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
        // the last worktree's list would otherwise linger. The first
        // reload happens here rather than in a second task keyed on
        // the scope, which could run against the model this one is
        // about to replace.
        .task(id: identity) {
            model = makeModel()
            await model.reload()
            await model.loadMergeQueue()
        }
        .onChange(of: model.scope) { Task { await model.reload() } }
        .onChange(of: items) { model.items = items }
    }

    // MARK: Internal

    /// The repository's worktree items, forwarded into the model as
    /// the dashboard polls so push and rebase states stay current.
    let items: [WorktreeItem]

    // MARK: Private

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage("utilityTab")
    private var utilityTab = ""

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
            canRebase: model.canRebase,
            rebaseTitle: model.rebaseTitle,
            pushTitle: model.pushTitle,
            pushHelp: model.pushHelp,
            status: model.status,
            onRebase: {
                if await model.rebaseSigned() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            },
            onPush: {
                if await model.push() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            },
            onOpenPullRequest: {
                if await model.openPullRequestPage() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            },
            onRefresh: { await model.reload(keepingSelection: true) },
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
                await model.act { try await model.github.enableAutomerge(
                    repositoryPath: model.repository.path,
                    number: summary.number,
                )
                }
            },
            onMerge: {
                await model.act { try await model.github.merge(
                    repositoryPath: model.repository.path,
                    number: summary.number,
                )
                }
            },
            onRemediate: { await model.act { try await model.remediate(summary) } },
        )
    }
}
