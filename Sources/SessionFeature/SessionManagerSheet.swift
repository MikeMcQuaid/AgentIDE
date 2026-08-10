import AgentIDEData
import SwiftUI
import TerminalUI

/// Lists every AgentIDE tmux session, sandboxed agents and host
/// shells alike, with a kill per row: the escape hatch when
/// something is running that should not be.
public struct SessionManagerSheet: View {
    // MARK: Lifecycle

    /// Creates the manager; `onDismiss` closes the sheet.
    @preconcurrency
    public init(service: SessionService, onDismiss: @escaping @MainActor () -> Void) {
        self.service = service
        self.onDismiss = onDismiss
    }

    // MARK: Public

    /// The session list with kill actions.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack {
                Text("Sessions").font(.title2)
                Spacer()
                Button("Refresh") { Task { await reload() } }
                    .hoverHelp("List the tmux sessions again")
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions running",
                    systemImage: "terminal",
                    description: Text("Agent sessions and host shells appear here."),
                )
                .frame(minHeight: Self.listHeight)
            } else {
                list
            }
        }
        .padding()
        .frame(minWidth: Self.minimumWidth)
        .task { await reload() }
    }

    // MARK: Internal

    var list: some View {
        List(sessions, id: \.name) { session in
            HStack {
                Image(systemName: session.isHostShell ? "terminal" : "cpu")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(session.isHostShell ? "Host shell" : "Agent session")
                Text(session.name).font(CodeStyle.font).lineLimit(1)
                Spacer()
                Button("Kill") {
                    Task {
                        await service.killTmuxSession(name: session.name, isHostShell: session.isHostShell)
                        await reload()
                    }
                }
                .hoverHelp(
                    session.isHostShell
                        ? "Kill this host shell tmux session"
                        : "Kill this agent's tmux session; its conversation stays resumable",
                )
            }
        }
        .frame(minHeight: Self.listHeight)
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let listHeight: CGFloat = 260
    private static let minimumWidth: CGFloat = 520

    @State private var sessions: [(name: String, isHostShell: Bool)] = []

    private let service: SessionService
    private let onDismiss: @MainActor () -> Void

    private func reload() async {
        sessions = await service.allTmuxSessions()
    }
}
