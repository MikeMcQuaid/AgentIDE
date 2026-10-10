import AgentIDEDomain
import AppKit
import SwiftUI

/// The same manual copy action beside local and GitHub conversations.
public struct CopyReviewConversationsButton: View {
    // MARK: Lifecycle

    public init(threads: [ReviewThread]) {
        self.threads = threads
    }

    // MARK: Public

    public var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ReviewThread.digest(of: open), forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .accessibilityLabel("Copy " + String(open.count) + " unresolved conversations")
        }
        .buttonStyle(.borderless)
        .disabled(open.isEmpty)
        .hoverHelp("Copy all unresolved local AI and GitHub conversations, with files and lines")
    }

    // MARK: Private

    private let threads: [ReviewThread]

    private var open: [ReviewThread] {
        threads.filter { $0.isResolved == false }
    }
}
