import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A pull-request-style review of the worktree's changes with
/// per-line rejection, commit message editing and a file editor. The
/// scope toggles between the last commit and the whole branch against
/// its merge base.
public struct ReviewView: View {
    // MARK: Lifecycle

    /// Creates the review view for a worktree; the GitHub client
    /// feeds the inline pull request conversations.
    public init(
        worktree: Worktree,
        branchStatus: BranchStatus,
        git: GitClient,
        github: GitHubClient,
        service: SessionService,
        localReviews: LocalReviewStore,
    ) {
        self.branchStatus = branchStatus
        worktreePath = worktree.path
        self.worktree = worktree
        self.service = service
        let pullRequests = service.pullRequestReads
        let fetchThreads: () async -> [ReviewThread] = {
            let branch = await git.currentBranch(worktreePath: worktree.path) ?? worktree.branch
            let listed = try? await pullRequests.listing(
                repositoryPath: worktree.repositoryPath,
                scope: .branch(branch),
            )
            guard let number = listed?.first(where: { $0.state == "OPEN" })?.number else {
                return []
            }

            let answer = try? await pullRequests.conversation(
                repositoryPath: worktree.repositoryPath,
                number: number,
                seededBody: nil,
            )
            if let failure = answer?.graphQLFailure {
                PerformanceLog.recordMessage(
                    "Conversations fell back to REST (no resolve buttons): " + failure,
                    isError: false,
                )
            }
            return answer?.threads ?? []
        }
        let setThreadResolved: (String, Bool) async throws -> Void = { threadID, resolved in
            try await github.setThreadResolved(
                repositoryPath: worktree.repositoryPath,
                threadID: threadID,
                resolved: resolved,
            )
        }
        makeModel = {
            let created = ReviewModel(
                worktreePath: worktree.path,
                repositoryName: worktree.repositoryName,
                git: git,
                baseRefProvider: { await service.reviewBase(for: worktree) },
                draftMessage: { await service.draftCommitMessage(worktreePath: worktree.path) },
                fetchThreads: fetchThreads,
                setThreadResolved: setThreadResolved,
            )
            created.configureResolveOnPush(worktree: worktree, git: git, pullRequests: pullRequests)
            return created
        }
        _model = State(initialValue: makeModel())
        makeLocalReview = { localReviews.model(worktreePath: worktree.path) }
        _localReview = State(initialValue: makeLocalReview())
    }

    // MARK: Public

    /// The diff and local findings share the selected scope.
    public var body: some View {
        codeReview
            .disabled(model.isAmending)
            // The find bar fades in rather than popping; nothing else
            // in the stack changes with it.
            .animation(Motion.quick, value: showsFind)
            .task(id: branchStatus) {
                if model.worktreePath != worktreePath {
                    model = makeModel()
                    localReview = makeLocalReview()
                    showsLocalReview = false
                    selectedBranch = ""
                }
                guard model.isAmending == false else {
                    return
                }

                let fresh = await service.stack(for: worktree)
                guard Task.isCancelled == false else {
                    return
                }

                stack = fresh
                if stack.branches.contains(selectedBranch) == false {
                    if selectedBranch.isEmpty == false {
                        model.commitTarget = nil
                    }
                    let remembered = StackSelection.branch(for: worktreePath)
                    selectedBranch = remembered.flatMap { stack.branches.contains($0) ? $0 : nil } ?? stack.checkedOut
                    StackSelection.remember(selectedBranch, for: worktreePath)
                }
                model.stackTarget = selectedBranch == stack.checkedOut
                    ? nil
                    : stack.parent(of: selectedBranch).map { (parent: $0, branch: selectedBranch) }
                await model.reload()
            }
            // Cmd-F reaches the pane through the storage bus: a diff is
            // not a text view, so AppKit's own find bar, which the
            // editor and the terminals answer, has nothing to attach to.
            .onChange(of: findRequest) { showsFind = true }
            .onChange(of: findNextRequest) { model.moveFind(by: 1) }
            .onChange(of: findPreviousRequest) { model.moveFind(by: -1) }
            .onChange(of: reviewCommitRequest) { showRequestedCommit(isBusy: localReview.isBusy) }
            // The menu bar's Commit Outstanding lands here through the
            // storage bus.
            .onChange(of: commitRequest) {
                if localReview.isBusy == false {
                    Task {
                        await commitOutstanding(model: model)
                    }
                }
            }
            .onChange(of: automationGeneration) {
                if localReview.isBusy == false {
                    localReview.refreshAutomation()
                }
                Task { [model] in
                    model.threads = await model.fetchThreads()
                }
            }
            .onChange(of: model.files) { localReview.update(files: model.files) }
            .onChange(of: localReview.review) {
                localReview.update(files: model.files)
                automationGeneration += 1
            }
            .sheet(isPresented: $localReview.showsPrompt) { LocalReviewPromptView(model: localReview) }
            .sheet(isPresented: $showsLocalReview) { LocalReviewView(model: localReview, diff: model) }
    }

    // MARK: Internal

    // swiftformat:disable:next privateSwiftUIDynamicProperties -- Shared with cross-file extensions.
    @State var model: ReviewModel // swiftlint:disable:this private_swiftui_state
    // swiftformat:disable:next privateSwiftUIDynamicProperties -- Shared with cross-file extensions.
    @State var collapseOverrides: [String: Bool] = [:] // swiftlint:disable:this private_swiftui_state

    // Whether the find bar is showing; the menu's Find opens it
    // and Escape or its own button closes it.
    // swiftformat:disable:next privateSwiftUIDynamicProperties -- Shared with the content extension.
    @State var showsFind = false // swiftlint:disable:this private_swiftui_state

    /// Internal, since the commit extension file reads them.
    let worktreePath: String

    /// Internal for the same reason as `worktreePath`.
    let service: SessionService

    let worktree: Worktree

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let captionSpacing: CGFloat = 2

    @State private var localReview: LocalReviewModel
    @State private var showsLocalReview = false
    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var automationGeneration = 0

    /// The stack the worktree's branch belongs to, and which entry
    /// of it this pane is showing. A stack of one is every branch
    /// that stands on its own, and shows no strip at all.
    @State private var stack: BranchStack = .init(base: nil, branches: [], checkedOut: "")
    @State private var selectedBranch = ""
    @State private var collapsedAll = false

    /// The menu bar's commit signal.
    @AppStorage("commitRequest")
    private var commitRequest = 0

    @AppStorage(ReviewCommitLink.requestKey)
    private var reviewCommitRequest = 0

    /// The find menu items' counters on the storage bus.
    @AppStorage("reviewFindRequest")
    private var findRequest = 0
    @AppStorage("reviewFindNextRequest")
    private var findNextRequest = 0
    @AppStorage("reviewFindPreviousRequest")
    private var findPreviousRequest = 0

    private let branchStatus: BranchStatus

    private let makeModel: () -> ReviewModel
    private let makeLocalReview: () -> LocalReviewModel

    private var codeReview: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Only a stack shows it, so a branch standing on its own
            // reviews exactly as it always did.
            if stack.isStacked {
                BranchStackStrip(stack: stack, selected: selectedBranch) { branch in
                    show(branch)
                }
                .disabled(localReview.isBusy)
                Divider()
            }
            if showsFind {
                ReviewFindBar(model: model, focusRequest: findRequest) { closeFind() }
                Divider()
            }
            feedbackStatus
            diffList(
                model: model,
                localReview: localReview,
                collapsedAll: collapsedAll,
                collapseOverrides: $collapseOverrides,
            )
            if model.isRepositoryAvailable {
                ReviewFooterView(
                    model: model,
                    onCommit: { await commitOutstanding(model: model) },
                    onAmend: { await amendOutstanding(model: model) },
                    canCommit: model.showsUncommitted && model.files.isEmpty == false && model.isReadOnly == false,
                )
                .disabled(localReview.isBusy)
            }
        }
    }

    /// Icon-only controls in two grouped capsules, every one
    /// explained by its tooltip.
    private var toolbar: some View {
        HStack(spacing: Self.spacing) {
            HStack(spacing: Self.captionSpacing) {
                scopeButtons
            }
            .padding(Self.captionSpacing)
            .background(.thinMaterial, in: Capsule())
            .disabled(localReview.isBusy)
            Spacer()
            displayToggles
                .disabled(localReview.isBusy)
            Spacer()
            Text(model.files.count == 1 ? "1 file" : String(model.files.count) + " files")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .hoverHelp("How many files the diff touches")
            DiffStatText(
                additions: model.files.map(\.additions).reduce(0, +),
                deletions: model.files.map(\.deletions).reduce(0, +),
            )
            .hoverHelp("Lines added and deleted across the diff")
            RefreshButton { await model.reload() }
                .controlSize(.small)
                .hoverHelp("Reload the diff from git")
                .disabled(localReview.isBusy)
            feedback(model: model, localReview: localReview) { reviewer in
                localReview.reviewer = reviewer
                showsLocalReview = true
            }
            .disabled(worktree.isHostDirectory || model.isRepositoryAvailable == false)
        }
        .padding(Self.spacing)
    }

    /// The collapse-all and whitespace toggles, one capsule group.
    private var displayToggles: some View {
        HStack(spacing: Self.captionSpacing) {
            PaneIconButton(
                collapsedAll ? "eye" : "eye.slash",
                help: collapsedAll
                    ? "Expand every file (generated files stay behind their carets)"
                    : "Collapse every file to its name",
            ) {
                collapsedAll.toggle()
                collapseOverrides = [:]
            }
            PaneIconButton(
                "textformat",
                help: model.hidesWhitespace
                    ? "Whitespace-only changes are hidden; click to show them"
                    : "Hide whitespace-only changes from the diff",
                isOn: model.hidesWhitespace,
            ) {
                model.hidesWhitespace.toggle()
                Task {
                    await model.reload()
                }
            }
        }
        .padding(Self.captionSpacing)
        .background(.thinMaterial, in: Capsule())
    }

    /// Retargets the pane at a stack entry: the checked-out branch
    /// reviews as usual, and any other shows its own diff, read
    /// only, since rejecting a line would have to write to a branch
    /// this worktree does not hold.
    private func show(_ branch: String) {
        selectedBranch = branch
        StackSelection.remember(branch, for: worktreePath)
        model.commitTarget = nil
        model.stackTarget = branch == stack.checkedOut
            ? nil
            : stack.parent(of: branch).map { (parent: $0, branch: branch) }
        Task {
            await model.reload()
        }
    }
}
