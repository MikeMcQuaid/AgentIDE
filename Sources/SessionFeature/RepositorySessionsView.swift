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
    /// worktree,
    /// `onResumed` runs after a resume launches and
    /// `onWorktreeFocus` reports the selected conversation's still
    /// existing worktree, so other panes can follow along, and
    /// `onNewSession`, when given, offers a fresh session in the
    /// worktree the list is scoped to.
    @preconcurrency
    public init(
        repository: Repository,
        service: SessionService,
        worktreePath: String? = nil,
        onWorktreeFocus: (@MainActor (String?) -> Void)? = nil,
        onNewSession: (@MainActor () -> Void)? = nil,
        onResumed: @escaping @MainActor () async -> Void,
    ) {
        self.onWorktreeFocus = onWorktreeFocus
        self.onNewSession = onNewSession
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
    private let onWorktreeFocus: (@MainActor (String?) -> Void)?
    private let onNewSession: (@MainActor () -> Void)?
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
            // Starting fresh comes before continuing something, in
            // the order the two are read; resuming stays the
            // prominent one, since it is why the list is here.
            if let onNewSession {
                Button("New session", action: onNewSession)
                    .controlSize(.small)
                    .hoverHelp("Start a fresh agent session in this worktree instead of continuing one")
            }
            // One resume button: in place when the conversation's
            // worktree still exists, into a fresh worktree only when
            // it is gone and that is all that can be done.
            if model.selected == nil || model.selectedWorktreePath != nil {
                Button("Resume here") { model.resumeSelectedHere(onResumed: onResumed) }
                    .controlSize(.small)
                    .disabled(model.selectedWorktreePath == nil)
                    .hoverHelp("Continue the selected conversation in the worktree it ran in")
            } else {
                Button("Resume in new worktree") { model.resumeSelected(onResumed: onResumed) }
                    .controlSize(.small)
                    .hoverHelp(
                        "This conversation's worktree is gone; continue it in a fresh worktree and branch",
                    )
            }
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
