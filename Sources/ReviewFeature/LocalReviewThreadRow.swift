import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The same local finding actions beneath the diff and inside the popover.
struct LocalReviewThreadRow: View {
    @Bindable var model: LocalReviewModel

    let diff: ReviewModel
    let thread: ReviewThread

    var body: some View {
        ReviewThreadRow(
            thread: thread,
            onEdit: { FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: diff.worktreePath) },
            localReviewer: model.review?.reviewer,
            onMakeFix: {
                model.showsPrompt = await model.prepare(threadID: thread.id) {
                    await diff.reload()
                    return diff.files
                }
            },
            onToggleResolved: { model.toggleResolved(thread.id) },
            allowsActions: model.isBusy == false,
            allowsFix: model.canPrepare,
        )
    }
}
