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
    public init(worktree: Worktree, git: GitClient, github: GitHubClient, service: SessionService) {
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
                ErrorLog.shared.report("Conversations fell back to REST (no resolve buttons): " + failure)
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
        let builder = {
            ReviewModel(
                worktreePath: worktree.path,
                git: git,
                baseRefProvider: { await service.reviewBase(for: worktree) },
                draftMessage: { await service.draftCommitMessage(worktreePath: worktree.path) },
                fetchThreads: fetchThreads,
                setThreadResolved: setThreadResolved,
            )
        }
        makeModel = builder
        _model = State(initialValue: builder())
    }

    // MARK: Public

    /// The toolbar, diff list and commit message editor.
    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Only a stack shows it, so a branch standing on its own
            // reviews exactly as it always did.
            if stack.isStacked {
                BranchStackStrip(stack: stack, selected: selectedBranch) { branch in
                    show(branch)
                }
                Divider()
            }
            if showsFind {
                ReviewFindBar(model: model, focusRequest: findRequest) { closeFind() }
                Divider()
            }
            diffList
            ReviewFooterView(
                model: model,
                onCommit: { await commitOutstanding() },
                canCommit: model.showsUncommitted && model.files.isEmpty == false && model.isReadOnly == false,
            )
        }
        // The model is rebuilt whenever the worktree changes: state
        // survives the view struct's re-initialisation, so the first
        // worktree's model would otherwise review every one.
        .task(id: worktreePath) {
            model = makeModel()
            stack = await service.stack(for: worktree)
            selectedBranch = stack.checkedOut
            await model.reload()
        }
        // Cmd-F reaches the pane through the storage bus: a diff is
        // not a text view, so AppKit's own find bar, which the
        // editor and the terminals answer, has nothing to attach to.
        .onChange(of: findRequest) { showsFind = true }
        .onChange(of: findNextRequest) { model.moveFind(by: 1) }
        .onChange(of: findPreviousRequest) { model.moveFind(by: -1) }
        // The menu bar's Commit Outstanding lands here through the
        // storage bus.
        .onChange(of: commitRequest) { Task { await commitOutstanding() } }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let captionSpacing: CGFloat = 2
    private static let iconPadding: CGFloat = 4
    private static let iconCornerRadius: CGFloat = 5
    private static let iconSelectedOpacity = 0.2
    private static let disabledOpacity = 0.4

    @State private var model: ReviewModel

    /// The stack the worktree's branch belongs to, and which entry
    /// of it this pane is showing. A stack of one is every branch
    /// that stands on its own, and shows no strip at all.
    @State private var stack: BranchStack = .init(base: nil, branches: [], checkedOut: "")
    @State private var selectedBranch = ""
    @State private var collapsedAll = false

    /// The menu bar's commit signal.
    @AppStorage("commitRequest")
    private var commitRequest = 0
    @State private var collapseOverrides: [String: Bool] = [:]

    /// Whether the find bar is showing; the menu's Find opens it
    /// and Escape or its own button closes it.
    @State private var showsFind = false

    /// The find menu items' counters on the storage bus.
    @AppStorage("reviewFindRequest")
    private var findRequest = 0
    @AppStorage("reviewFindNextRequest")
    private var findNextRequest = 0
    @AppStorage("reviewFindPreviousRequest")
    private var findPreviousRequest = 0

    private let worktreePath: String
    private let worktree: Worktree
    private let service: SessionService
    private let makeModel: () -> ReviewModel

    /// Icon-only controls in two grouped capsules, every one
    /// explained by its tooltip.
    private var toolbar: some View {
        HStack(spacing: Self.spacing) {
            HStack(spacing: Self.captionSpacing) {
                scopeButtons
            }
            .padding(Self.captionSpacing)
            .background(.thinMaterial, in: Capsule())
            Spacer()
            displayToggles
            Spacer()
            Text(model.files.count == 1 ? "1 file" : String(model.files.count) + " files")
                .font(.caption)
                .foregroundStyle(.secondary)
                .hoverHelp("How many files the diff touches")
            DiffStatText(
                additions: model.files.map(\.additions).reduce(0, +),
                deletions: model.files.map(\.deletions).reduce(0, +),
            )
            .hoverHelp("Lines added and deleted across the diff")
            RefreshButton { await model.reload() }
                .hoverHelp("Reload the diff from git")
        }
        .padding(Self.spacing)
    }

    /// The collapse-all and whitespace toggles, one capsule group.
    private var displayToggles: some View {
        HStack(spacing: Self.captionSpacing) {
            iconButton(
                collapsedAll ? "eye" : "eye.slash",
                help: collapsedAll
                    ? "Expand every file (generated files stay behind their carets)"
                    : "Collapse every file to its name",
            ) {
                collapsedAll.toggle()
                collapseOverrides = [:]
            }
            iconButton(
                "textformat",
                help: model.hidesWhitespace
                    ? "Whitespace-only changes are hidden; click to show them"
                    : "Hide whitespace-only changes from the diff",
                isOn: model.hidesWhitespace,
            ) {
                model.hidesWhitespace.toggle()
                Task { await model.reload() }
            }
        }
        .padding(Self.captionSpacing)
        .background(.thinMaterial, in: Capsule())
    }

    @ViewBuilder private var scopeButtons: some View {
        scopeButton(.uncommitted, systemImage: "pencil", help: "Review uncommitted changes")
        scopeButton(.lastCommit, systemImage: "clock", help: "Review the last commit")
        scopeButton(
            .upstream,
            systemImage: "icloud.and.arrow.up",
            help: model.hasUpstream
                ? "Review commits not yet pushed to this branch's origin ref"
                : "Dimmed until this branch has been pushed",
            disabled: model.hasUpstream == false,
        )
        scopeButton(
            .branch,
            systemImage: "arrow.triangle.branch",
            help: "Review every commit on the branch against its merge base",
        )
    }

    @ViewBuilder private var diffList: some View {
        if model.hasLoaded == false {
            // A local `git diff` lands in well under half a second;
            // a wait that short shows nothing rather than a flash.
            Color.clear
        } else if model.files.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReviewFileListView(
                model: model,
                worktreePath: worktreePath,
                service: service,
                hideAllByDefault: collapsedAll,
                collapseOverrides: $collapseOverrides,
            )
            .contextMenu {
                Button("Reject Selected Lines") { Task { await model.rejectSelected() } }
                    .disabled(
                        model.selections.values.allSatisfy(\.isEmpty)
                            || model.scope == .branch || model.scope == .upstream
                            || model.isReadOnly,
                    )
            }
        }
    }

    private func scopeButton(
        _ scope: ReviewModel.Scope,
        systemImage: String,
        help: String,
        disabled: Bool = false,
    ) -> some View {
        iconButton(systemImage, help: help, isOn: model.scope == scope, disabled: disabled) {
            model.scope = scope
            model.commitTarget = nil
            collapseOverrides = [:]
            Task { await model.reload() }
        }
    }

    /// One icon control; a selected one fills its bubble.
    private func iconButton(
        _ systemImage: String,
        help: String,
        isOn: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(Self.iconPadding)
                .background(
                    RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                        .fill(isOn ? Color.accentColor.opacity(Self.iconSelectedOpacity) : .clear),
                )
                .contentShape(Rectangle())
                .accessibilityLabel(help)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Self.disabledOpacity : 1)
        // The colour fill alone is invisible to VoiceOver.
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .hoverHelp(help)
    }

    /// Retargets the pane at a stack entry: the checked-out branch
    /// reviews as usual, and any other shows its own diff, read
    /// only, since rejecting a line would have to write to a branch
    /// this worktree does not hold.
    private func show(_ branch: String) {
        selectedBranch = branch
        model.commitTarget = nil
        model.stackTarget = branch == stack.checkedOut
            ? nil
            : stack.parent(of: branch).map { (parent: $0, branch: branch) }
        Task { await model.reload() }
    }

    /// The collapsible file list; the uncommitted scope embeds the
    /// shared editor per file so fixes are typed directly.
    /// Closing clears the query too, so the highlights go with the
    /// bar rather than being left behind on the diff.
    private func closeFind() {
        showsFind = false
        model.findQuery = ""
    }

    private func commitOutstanding() async {
        do {
            try await service.commitOutstanding(worktreePath: worktreePath)
            await model.reload()
        } catch {
            model.report(error.localizedDescription)
        }
    }
}
