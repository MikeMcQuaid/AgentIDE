import AgentIDEData
import SwiftUI
import TerminalUI

/// Lists everything this app has running: every agent session on
/// the sandboxed herdr server and the browser pages it renders
/// itself, with where each lives, what it costs and a way to stop
/// it. The escape hatch when something is running that should not
/// be.
public struct SessionManagerSheet: View {
    // MARK: Lifecycle

    /// Creates the manager; `onCloseBrowser` closes a browser page,
    /// which only the window can do, and `onDismiss` closes the
    /// sheet.
    @preconcurrency
    public init(
        service: SessionService,
        onCloseBrowser: @escaping @MainActor (String) -> Void,
        onDismiss: @escaping @MainActor () -> Void,
    ) {
        self.service = service
        self.onCloseBrowser = onCloseBrowser
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
                    .hoverHelp("List the sessions again")
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if hasLoaded == false {
                LaunchProgressView(
                    "Listing sessions…",
                    waitingOn: "`herdr api snapshot` and `ps` for each session's usage",
                )
                .frame(minHeight: Self.listHeight)
            } else if sessions.isEmpty, browsers.all.isEmpty {
                ContentUnavailableView(
                    "Nothing running",
                    systemImage: "terminal",
                    description: Text("Agent sessions and browser pages appear here."),
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
        List {
            ForEach(sessions, id: \.name) { session in
                row(
                    Entry(
                        icon: "cpu",
                        label: "Agent session",
                        title: session.name,
                        directory: session.workingDirectory,
                        usage: usage(of: session),
                    ),
                ) {
                    killButton(for: session)
                }
            }
            ForEach(browsers.all) { pane in
                row(
                    Entry(
                        icon: "safari",
                        label: "Browser page",
                        title: pane.address.isEmpty ? "Blank page" : pane.address,
                        directory: pane.worktreePath,
                        usage: usage(of: pane),
                    ),
                ) {
                    closeButton(for: pane)
                }
            }
        }
        .frame(minHeight: Self.listHeight)
    }

    // MARK: Private

    /// What one row says, whatever it is a row of.
    private struct Entry {
        let icon: String
        let label: String
        let title: String
        let directory: String
        let usage: String
    }

    private static let spacing: CGFloat = 10
    /// Roughly twenty rows: the list scrolls only past that.
    private static let listHeight: CGFloat = 560
    private static let minimumWidth: CGFloat = 640

    /// How many trailing path components place a worktree.
    private static let locationComponents = 3

    @State private var sessions: [SessionOverview] = []
    @State private var hasLoaded = false
    @State private var killed: Set<String> = []
    @State private var browserUsage: [Int32: (cpuPercent: Double, memoryMegabytes: Int)] = [:]

    private let browsers: BrowserPanes = .shared
    private let service: SessionService
    private let onCloseBrowser: @MainActor (String) -> Void
    private let onDismiss: @MainActor () -> Void

    /// One row: what it is, where it lives, what it costs and how to
    /// stop it.
    private func row(_ entry: Entry, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: entry.icon)
                .foregroundStyle(.secondary)
                .accessibilityLabel(entry.label)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(CodeStyle.font).lineLimit(1)
                Text(location(of: entry.directory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverHelp(entry.directory)
            }
            Spacer()
            Text(entry.usage)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .hoverHelp("CPU and memory summed over its process tree")
            action()
        }
    }

    /// Closing a page ends the web process rendering it; its address
    /// is remembered, so the tab opens it again.
    private func closeButton(for pane: BrowserPane) -> some View {
        Button("Close") { onCloseBrowser(pane.worktreePath) }
            .hoverHelp("Close this page and end the web process rendering it; its address is kept")
    }

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
                await service.killSession(name: session.name)
                killed.insert(session.name)
            }
            .hoverHelp("Kill this agent's session; its conversation stays resumable")
        }
    }

    private func reload() async {
        sessions = await service.sessionOverviews()
        browserUsage = await service.usage(ofProcesses: browsers.all.compactMap(\.processIdentifier))
        killed = killed.filter { name in sessions.contains { $0.name == name } }
        // A row killed and gone needs no marker; one killed and
        // still listed shows Killed until a refresh proves it away.
        hasLoaded = true
    }

    /// The owning worktree, its repository and container: the
    /// path's tail places it.
    private func location(of directory: String) -> String {
        directory
            .split(separator: "/")
            .suffix(Self.locationComponents)
            .joined(separator: "/")
    }

    private func usage(of session: SessionOverview) -> String {
        usage(cpuPercent: session.cpuPercent, memoryMegabytes: session.memoryMegabytes)
    }

    /// A page WebKit has not told us its process for shows no
    /// figures rather than numbers it cannot stand behind.
    private func usage(of pane: BrowserPane) -> String {
        guard let identifier = pane.processIdentifier, let measured = browserUsage[identifier] else {
            return ""
        }

        return usage(cpuPercent: measured.cpuPercent, memoryMegabytes: measured.memoryMegabytes)
    }

    private func usage(cpuPercent: Double, memoryMegabytes: Int) -> String {
        String(format: "%.0f%% · %d MB", cpuPercent, memoryMegabytes)
    }
}
