import AgentIDEData
import SwiftUI
import TerminalUI

/// Lists every AgentIDE tmux session, sandboxed agents and host
/// shells alike, with where each lives, what it costs and a kill
/// per row: the escape hatch when something is running that should
/// not be.
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
            HStack(spacing: Self.spacing) {
                Image(systemName: session.isHostShell ? "terminal" : "cpu")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(session.isHostShell ? "Host shell" : "Agent session")
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name).font(CodeStyle.font).lineLimit(1)
                    Text(location(of: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .hoverHelp(session.workingDirectory)
                }
                Spacer()
                Text(usage(of: session))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .hoverHelp("CPU and memory summed over the session's process tree")
                killButton(for: session)
            }
        }
        .frame(minHeight: Self.listHeight)
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let listHeight: CGFloat = 260
    private static let minimumWidth: CGFloat = 640

    /// How many trailing path components place a worktree.
    private static let locationComponents = 3

    @State private var sessions: [SessionOverview] = []
    @State private var killed: Set<String> = []

    private let service: SessionService
    private let onDismiss: @MainActor () -> Void

    /// Kill greys to Killing while it runs and Killed once the
    /// session is gone; the service escalates a stuck kill itself.
    @ViewBuilder
    private func killButton(for session: SessionOverview) -> some View {
        if killed.contains(session.name) {
            Button("Killed") {
                // Nothing left to do.
            }
            .disabled(true)
        } else {
            BusyButton("Kill", busy: "Killing") {
                await service.killTmuxSession(name: session.name, isHostShell: session.isHostShell)
                killed.insert(session.name)
            }
            .hoverHelp(
                session.isHostShell
                    ? "Kill this host shell tmux session, escalating to KILL if it hangs on"
                    : "Kill this agent's tmux session; its conversation stays resumable",
            )
        }
    }

    private func reload() async {
        sessions = await service.sessionOverviews()
        killed = killed.filter { name in sessions.contains { $0.name == name } }
        // A row killed and gone needs no marker; one killed and
        // still listed shows Killed until a refresh proves it away.
    }

    /// The owning worktree, its repository and container: the
    /// path's tail places it.
    private func location(of session: SessionOverview) -> String {
        session.workingDirectory
            .split(separator: "/")
            .suffix(Self.locationComponents)
            .joined(separator: "/")
    }

    private func usage(of session: SessionOverview) -> String {
        String(format: "%.0f%% · %d MB", session.cpuPercent, session.memoryMegabytes)
    }
}
