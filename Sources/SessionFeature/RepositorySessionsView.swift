import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The one conversations UI: every conversation of a repository, or
/// of a single worktree when scoped, whether or not its worktree
/// still exists. Selecting one shows its log; any of them can
/// resume here or into a fresh worktree. The view renders and
/// binds; RepositorySessionsModel owns the behaviour.
public struct RepositorySessionsView: View {
    // MARK: Lifecycle

    /// Creates the browser; `worktreePath` scopes the list to one
    /// worktree, `onNewSession` opens the new session page,
    /// `onResumed` runs after a resume launches and
    /// `onWorktreeFocus` reports the selected conversation's still
    /// existing worktree, so other panes can follow along.
    @preconcurrency
    public init(
        repository: Repository,
        service: SessionService,
        worktreePath: String? = nil,
        onNewSession: (@MainActor () -> Void)? = nil,
        onWorktreeFocus: (@MainActor (String?) -> Void)? = nil,
        onResumed: @escaping @MainActor () async -> Void,
    ) {
        self.onNewSession = onNewSession
        self.onWorktreeFocus = onWorktreeFocus
        self.onResumed = onResumed
        identity = repository.id + "#" + (worktreePath ?? "")
        makeModel = {
            RepositorySessionsModel(repository: repository, service: service, worktreePath: worktreePath)
        }
        _model = State(initialValue: makeModel())
    }

    // MARK: Public

    /// The session list over the selected conversation's log, a
    /// pane-filling progress state while a resume launches, and a
    /// loading state until the first listing answers so the empty
    /// message never flashes before conversations arrive.
    public var body: some View {
        VStack(spacing: 0) {
            if model.isResuming {
                ProgressView("Resuming conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasLoaded == false {
                ProgressView("Loading conversations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()
                if model.sessions.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Every agent conversation in this repository appears here, resumable."),
                    )
                } else {
                    list
                    Divider()
                    log
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The model is rebuilt whenever the repository or worktree
        // scope changes: state objects outlive view
        // re-initialisation, so the last scope's list would
        // otherwise linger. The identity comes from the view's own
        // inputs, never the persisted model, so a switch always
        // rebuilds.
        .task(id: identity) {
            model = makeModel()
            await model.load()
            onWorktreeFocus?(model.selectedWorktreePath)
        }
        .onChange(of: model.selected) {
            onWorktreeFocus?(model.selectedWorktreePath)
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let headerBottomPadding: CGFloat = 3
    private static let agentIconSize: CGFloat = 7
    private static let listHeight: CGFloat = 200

    @State private var model: RepositorySessionsModel

    private let identity: String
    private let onNewSession: (@MainActor () -> Void)?
    private let onWorktreeFocus: (@MainActor (String?) -> Void)?
    private let onResumed: @MainActor () async -> Void
    private let makeModel: () -> RepositorySessionsModel

    private var header: some View {
        HStack {
            Text(
                model.worktreePath == nil
                    ? "Conversations in \(model.repository.name)"
                    : "Conversations in this worktree",
            )
            .font(.subheadline.weight(.semibold))
            Spacer()
            if let onNewSession {
                Button("New session", action: onNewSession)
                    .controlSize(.small)
                    .hoverHelp("Start a fresh agent session in this repository instead of resuming")
            }
            Button("Resume here") { model.resumeSelectedHere(onResumed: onResumed) }
                .controlSize(.small)
                .disabled(model.selectedWorktreePath == nil)
                .hoverHelp(
                    "Continue the selected conversation in the worktree it ran in; dimmed when that worktree is gone",
                )
            Button("Resume in new worktree") { model.resumeSelected(onResumed: onResumed) }
                .controlSize(.small)
                .disabled(model.selected == nil)
                .hoverHelp("Create a fresh worktree and branch and continue the selected conversation there")
        }
        // Flush with the window's top: the page ignores the toolbar
        // inset, so only a hairline of breathing room remains.
        .padding(.horizontal, Self.padding)
        .padding(.top, Self.headerBottomPadding)
        .padding(.bottom, Self.headerBottomPadding)
    }

    private var list: some View {
        List(model.sessions, id: \.session.id, selection: $model.selected) { entry in
            HStack(spacing: Self.padding) {
                Image(entry.session.agent.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                    .accessibilityLabel(entry.session.agent.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    // Untitled conversations borrow their worktree's
                    // name, never the transcript uuid.
                    Text(model.title(of: entry))
                        .lineLimit(1)
                    HStack(spacing: Self.padding) {
                        Text(
                            Date(timeIntervalSince1970: TimeInterval(entry.session.modifiedAt)),
                            format: .relative(presentation: .named),
                        )
                        Text(model.location(of: entry.worktreePath))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .tag(entry.session)
            .contextMenu {
                Button("Delete conversation") { model.delete(entry.session) }
                    .hoverHelp("Remove this conversation's transcript permanently")
            }
        }
        .listStyle(.plain)
        .frame(height: Self.listHeight)
        .hoverHelp("Every conversation in this repository, newest first; pick one to read it below")
    }

    @ViewBuilder private var log: some View {
        if let selected = model.selected {
            TranscriptLogView(entries: model.service.transcriptEntries(for: selected))
        } else {
            ContentUnavailableView(
                "No conversation selected",
                systemImage: "text.bubble",
                description: Text("Pick a conversation above to read it."),
            )
        }
    }
}
