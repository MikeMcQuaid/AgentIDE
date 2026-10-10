import AgentIDEData
import AgentIDEDomain
import AppKit
@testable import ReviewFeature
import SwiftUI
import Testing

@MainActor
struct LocalReviewInlineTests {
    @Test
    func `findings remain in the review pane when the selected diff is empty`() async {
        let review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: (1 ... 10).map { index in
            ReviewThread(
                id: String(index),
                path: "outside.swift",
                line: index,
                isResolved: false,
                comments: [ReviewThreadComment(author: "Codex", body: "Finding " + String(index))],
            )
        })
        let local = LocalReviewModel(
            review: review,
            reviewer: .codexCLI,
            run: { _, _, _, _ in review },
            revision: { "r" },
            save: { _ in
                // Rendering must not change the saved review.
            },
        )
        let diff = ReviewModel(
            worktreePath: "/missing", repositoryName: "repo", git: GitClient(runner: FoundationProcessRunner()),
        )
        let list = ReviewFileListView(
            model: diff,
            localReview: local,
            worktreePath: "/missing",
            hideAllByDefault: false,
            collapseOverrides: .constant([:]),
        )
        let host = NSHostingView(rootView: list.unplacedConversations.frame(width: 600))
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            if host.fittingSize.height > 400 {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(host.fittingSize.height > 400)
    }
}
