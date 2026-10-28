import AppKit
import SanductorDomain
import SwiftUI

/// The same manual copy action beside local and GitHub conversations.
public struct CopyReviewConversationsButton: View {
    // MARK: Lifecycle

    public init(threads: [ReviewThread]) {
        self.threads = threads
    }

    // MARK: Public

    public var body: some View {
        PaneIconButton(
            "doc.on.doc",
            help: "Copy all unresolved local AI and GitHub conversations, with files and lines",
            disabled: open.isEmpty,
        ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ReviewThread.digest(of: open), forType: .string)
        }
        .accessibilityLabel("Copy " + String(open.count) + " unresolved conversations")
    }

    // MARK: Private

    private let threads: [ReviewThread]

    private var open: [ReviewThread] {
        threads.filter { $0.isResolved == false }
    }
}
