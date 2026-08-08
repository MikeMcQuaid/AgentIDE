import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The final agent message plus the session's terminals and browser.
public struct SessionDetailView: View {
    // MARK: Lifecycle

    /// Creates the detail view for a worktree item.
    public init(item: WorktreeItem, service: SessionService) {
        self.item = item
        self.service = service
    }

    // MARK: Public

    /// A tab picker over message, terminals and browser.
    public var body: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $tab) {
                ForEach(SessionTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Self.padding)
            Divider()
            content
        }
    }

    // MARK: Private

    private enum SessionTab: CaseIterable {
        case message
        case agentTerminal
        case hostTerminal
        case browser

        // MARK: Internal

        var title: String {
            switch self {
            case .message:
                "Message"

            case .agentTerminal:
                "Agent"

            case .hostTerminal:
                "Shell"

            case .browser:
                "Browser"
            }
        }
    }

    private static let padding: CGFloat = 8

    @State private var tab: SessionTab = .message

    private let item: WorktreeItem
    private let service: SessionService

    @ViewBuilder private var content: some View {
        switch tab {
        case .message:
            FinalMessageView(item: item, service: service)

        case .agentTerminal:
            if let session = item.session {
                TerminalPaneView(command: service.attachCommand(sessionName: session.name))
                    .id(session.name)
            } else {
                ContentUnavailableView("No session", systemImage: "terminal")
            }

        case .hostTerminal:
            TerminalPaneView(command: service.hostShellCommand(worktreePath: item.worktree.path))
                .id(item.worktree.path)

        case .browser:
            BrowserView()
        }
    }
}
