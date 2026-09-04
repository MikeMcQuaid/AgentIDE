import AgentIDEData
import SwiftUI

/// Committing from the review pane: the ticked files, or the
/// whole worktree when every file is ticked. Split from the view
/// for length.
extension ReviewView {
    func commitOutstanding(model: ReviewModel) async {
        do {
            try await service.commitOutstanding(
                worktreePath: worktreePath,
                paths: model.pathsToCommit,
                message: model.commitMessage,
            )
            model.excludedFromCommit = []
            await model.reload()
        } catch {
            model.report(error.localizedDescription)
        }
    }
}
