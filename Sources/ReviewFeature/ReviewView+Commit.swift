import AgentIDEData

/// Committing from the review pane: the ticked files, or the whole
/// worktree when every file is ticked. Split from the view for
/// length.
extension ReviewView {
    func commitOutstanding(model: ReviewModel) async {
        guard model.hasSomethingToCommit else {
            model.setStatus("Nothing ticked to commit.")
            return
        }

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

    /// Adds what is ticked to the last commit rather than making a
    /// new one.
    func amendOutstanding(model: ReviewModel) async {
        guard model.hasSomethingToCommit else {
            model.setStatus("Nothing ticked to add to the last commit.")
            return
        }

        do {
            try await service.amendOutstanding(worktreePath: worktreePath, paths: model.pathsToCommit)
            model.excludedFromCommit = []
            await model.reload()
        } catch {
            model.report(error.localizedDescription)
        }
    }
}
