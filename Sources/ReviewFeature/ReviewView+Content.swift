import AgentIDEDomain
import SwiftUI
import TerminalUI

extension ReviewView {
    func closeFind() {
        showsFind = false
        model.findQuery = ""
    }

    func showRequestedCommit(isBusy: Bool) {
        guard let commit = ReviewCommitLink.requestedCommit(worktreePath: worktreePath) else {
            return
        }
        guard isBusy == false else {
            model.setStatus("Wait for the local review to finish before opening another commit.")
            return
        }

        Task {
            await model.showCommit(commit)
        }
    }

    @ViewBuilder var scopeButtons: some View {
        scopeButton(.uncommitted, systemImage: "pencil", help: "Review uncommitted changes")
        scopeButton(.lastCommit, systemImage: "clock", help: "Review the last commit")
        scopeButton(
            .upstream,
            systemImage: "icloud.and.arrow.up",
            help: "Review the commits not yet on this branch's own origin ref; dimmed until the branch has been pushed",
            disabled: model.hasUpstream == false,
        )
        scopeButton(
            .branch,
            systemImage: "arrow.triangle.branch",
            help: "Review every commit on the branch against its merge base",
        )
    }

    private func scopeButton(
        _ scope: ReviewModel.Scope,
        systemImage: String,
        help: String,
        disabled: Bool = false,
    ) -> some View {
        PaneIconButton(systemImage, help: help, isOn: model.scope == scope, disabled: disabled) {
            model.scope = scope
            model.commitTarget = nil
            collapseOverrides = [:]
            Task {
                await model.reload()
            }
        }
    }

    func feedback(
        model: ReviewModel, localReview: LocalReviewModel, onReview: @escaping (AgentKind) -> Void,
    ) -> some View {
        FeedbackView(
            service: service,
            repositoryPath: worktree.repositoryPath,
            worktreePath: worktreePath,
            localOnly: true,
            reviewIsBusy: localReview.isBusy,
            loopUnavailableReason: model.isReadOnly ? "Select the checked-out branch to start a loop." : nil,
            onReview: onReview,
        )
        .id(worktreePath)
    }

    var feedbackStatus: some View {
        FeedbackStatusView(
            service: service,
            repositoryPath: worktree.repositoryPath,
            worktreePath: worktreePath,
            summary: nil,
        )
    }

    @ViewBuilder
    func diffList(
        model: ReviewModel,
        localReview: LocalReviewModel,
        collapsedAll: Bool,
        collapseOverrides: Binding<[String: Bool]>,
    ) -> some View {
        if model.hasLoaded == false {
            // A local `git diff` lands in well under half a second;
            // a wait that short shows nothing rather than a flash.
            Color.clear
        } else if model.isRepositoryAvailable == false {
            ContentUnavailableView(
                "Git repository unavailable",
                systemImage: "folder.badge.questionmark",
                description: Text("Restore this worktree and its Git metadata, then refresh."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.files.isEmpty, model.threads.isEmpty, localReview.review?.threads.isEmpty != false {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReviewFileListView(
                model: model,
                localReview: localReview,
                worktreePath: worktreePath,
                hideAllByDefault: collapsedAll,
                collapseOverrides: collapseOverrides,
            )
            .contextMenu {
                Button("Reject Selected Lines") {
                    Task {
                        await model.rejectSelected()
                    }
                }
                .disabled(
                    model.selections.values.allSatisfy(\.isEmpty)
                        || model.scope == .branch || model.scope == .upstream
                        || model.isReadOnly || localReview.isBusy,
                )
            }
            .disabled(localReview.isBusy)
        }
    }
}
