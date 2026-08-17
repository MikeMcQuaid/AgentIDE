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
        self.service = service
        let fetchThreads: () async -> [ReviewThread] = {
            let branch = await git.currentBranch(worktreePath: worktree.path) ?? worktree.branch
            let listed = try? await github.pullRequests(
                repositoryPath: worktree.repositoryPath,
                scope: .branch(branch),
            )
            guard let number = listed?.first(where: { $0.state == "OPEN" })?.number else {
                return []
            }

            let answer = await github.conversationThreads(
                repositoryPath: worktree.repositoryPath,
                number: number,
            )
            if let failure = answer.graphQLFailure {
                ErrorLog.shared.report("Conversations fell back to REST (no resolve buttons): " + failure)
            }
            return answer.threads
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
            diffList
            ReviewFooterView(
                model: model,
                onCommit: { await commitOutstanding() },
                canCommit: model.showsUncommitted && model.files.isEmpty == false,
            )
        }
        // The model is rebuilt whenever the worktree changes: state
        // survives the view struct's re-initialisation, so the first
        // worktree's model would otherwise review every one.
        .task(id: worktreePath) {
            model = makeModel()
            await model.reload()
        }
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
    @State private var collapsedAll = false

    /// The menu bar's commit signal.
    @AppStorage("commitRequest")
    private var commitRequest = 0
    @State private var collapseOverrides: [String: Bool] = [:]

    private let worktreePath: String
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

    /// The collapsible file list; the uncommitted scope embeds the
    /// shared editor per file so fixes are typed directly.
    @ViewBuilder private var diffList: some View {
        if model.files.isEmpty {
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
                            || model.scope == .branch || model.scope == .upstream,
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

    private func commitOutstanding() async {
        do {
            try await service.commitOutstanding(worktreePath: worktreePath)
            await model.reload()
        } catch {
            model.report(error.localizedDescription)
        }
    }
}
