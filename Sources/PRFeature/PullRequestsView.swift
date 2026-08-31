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
        worktreePath: String? = nil,
        defaultBranch: String? = nil,
        isMainCheckout: Bool = false,
    ) {
        self.items = items
        self.isMainCheckout = isMainCheckout
        identity = repository.id + "#" + (branch ?? "")
        makeModel = {
            PullRequestsModel(
                repository: repository,
                branch: branch,
                worktreePath: worktreePath,
                defaultBranch: defaultBranch,
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
            HStack {
                PullRequestScopePicker(scope: $model.scope, worktreeTitle: worktreeScopeTitle)
                Spacer()
                RefreshButton { await model.reload(keepingSelection: true) }
                    .hoverHelp("Fetch the pull requests again")
            }
            .padding(.trailing, Self.headerPadding)
            Divider()
            // Shown only by a stack, so a lone branch's tab is the
            // one it always was.
            if model.stack.isStacked {
                BranchStackStrip(
                    stack: model.stack,
                    selected: model.listedBranch ?? "",
                    isEnabled: { model.canList($0) },
                    onSelect: { model.show(branch: $0) },
                )
                Divider()
            }
            if let selected = model.selected {
                conversation(for: selected)
            } else if model.needsCreateForm {
                PullRequestCreateForm(model: model)
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
        // about to replace. Revisiting the tab refreshes the list
        // but leaves the creation form alone: there is no pull
        // request to poll for until Open PR creates it.
        .task(id: identity) {
            if loadedIdentity != identity {
                model = makeModel()
                loadedIdentity = identity
                await model.reload()
                await model.loadMergeQueue()
            } else if model.needsCreateForm == false {
                await model.reload(keepingSelection: true)
            }
        }
        .onChange(of: model.scope) { Task { await model.reload() } }
        .onChange(of: items) { model.items = items }
        // The menu bar's Push and Rebase land here through the
        // storage bus, acting on whichever worktree the pane shows.
        .onChange(of: pushRequest) { Task { _ = await model.push() } }
        .onChange(of: rebaseRequest) { Task { _ = await model.rebaseSigned() } }
    }

    // MARK: Internal

    /// The repository's worktree items, forwarded into the model as
    /// the dashboard polls so push and rebase states stay current.
    let items: [WorktreeItem]

    // MARK: Private

    private static let headerPadding: CGFloat = 8

    /// The menu bar's action signals.
    @AppStorage("pushRequest")
    private var pushRequest = 0
    @AppStorage("rebaseRequest")
    private var rebaseRequest = 0

    @State private var model: PullRequestsModel

    /// Which repository and branch the model was last built for;
    /// tab revisits with the same identity keep it.
    @State private var loadedIdentity = ""

    private let isMainCheckout: Bool

    /// The repository and branch as a task identity: it comes from
    /// the view's own inputs, never the persisted model, so a
    /// repository switch always rebuilds.
    private let identity: String

    private let makeModel: () -> PullRequestsModel

    /// The worktree scope names the branch itself when the pane
    /// drives from the main checkout, where no worktree exists.
    private var worktreeScopeTitle: String {
        if isMainCheckout {
            "Branch"
        } else {
            "Worktree"
        }
    }

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
        PullRequestFooterView(model: model)
    }

    private func conversation(for summary: PullRequestSummary) -> some View {
        PullRequestConversationPane(
            summary: summary,
            stackDepth: model.stackDepth(for: summary),
            github: model.github,
            repositoryPath: model.repository.path,
            store: model.store,
            onBack: { model.selected = nil },
            onCopyComments: { await model.copyUnresolvedComments(summary) },
            onOpenChecks: { model.openFailingChecks(summary) },
            onResolvedChanged: { await model.refreshSummary(summary.number) },
            onThreadsChanged: { model.updateUnresolved($0, number: summary.number) },
            onToggleLabel: { _ = await model.toggleLabel($0) },
            labels: model.selectedLabels,
            availableLabels: model.availableLabels,
        )
    }
}
