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

    /// The errors tab's position in the utility tab order, driven
    /// through the storage signal bus.
    private static let errorsTabIndex = 5

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage("utilityTabIndex")
    private var utilityTabIndex = 0

    /// The new session form's last choices, naming what wrote the
    /// change in the draft's AI disclosure.
    @AppStorage("agentModel")
    private var agentModel = ""
    @AppStorage("agentEffort")
    private var agentEffort = ""

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
            hasDraft: model.hasDraft,
            pushHelp: model.pushHelp,
            status: model.status,
            onRebase: {
                Task {
                    if await model.rebaseSigned() == false {
                        utilityTabIndex = Self.errorsTabIndex
                    }
                }
            },
            onPush: {
                Task {
                    if await model.push() == false {
                        utilityTabIndex = Self.errorsTabIndex
                    }
                }
            },
            onOpenPullRequest: { Task { await ship() } },
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

    /// Routes Open PR's outcome: a fresh draft opens in the editor
    /// tab, a failure opens the errors tab.
    private func ship() async {
        let item = model.branchItem
        let disclosure = PullRequestDraft.disclosure(
            agent: (item?.session?.agent ?? item?.pastSessions.first?.agent)?.displayName,
            model: agentModel,
            effort: agentEffort,
        )
        switch await model.ship(disclosure: disclosure) {
        case let .drafted(relativePath):
            if let path = item?.worktree.path {
                FileOpener.open(relativePath: relativePath, line: nil, worktreePath: path)
            }

        case .failed:
            utilityTabIndex = Self.errorsTabIndex

        case .created,
             .unavailable:
            break
        }
    }
}
