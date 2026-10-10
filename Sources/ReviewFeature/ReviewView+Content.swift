import AgentIDEDomain
import SwiftUI
import TerminalUI

extension ReviewView {
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
                Button("Reject Selected Lines") { Task { await model.rejectSelected() } }
                    .disabled(
                        model.selections.values.allSatisfy(\.isEmpty)
                            || model.scope == .branch || model.scope == .upstream
                            || model.isReadOnly || localReview.isBusy,
                    )
            }
            .disabled(localReview.isBusy)
        }
    }

    /// One icon control; a selected one fills its bubble.
    func iconButton(
        _ systemImage: String,
        help: String,
        isOn: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(Self.iconPadding)
                .background(
                    RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                        .fill(isOn ? Color.accentColor.opacity(Self.iconSelectedOpacity) : .clear),
                )
                .contentShape(Rectangle())
                .accessibilityLabel(help)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Self.disabledOpacity : 1)
        // The colour fill alone is invisible to VoiceOver.
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .hoverHelp(help)
    }

    private static let iconPadding: CGFloat = 4
    private static let iconCornerRadius: CGFloat = 5
    private static let iconSelectedOpacity = 0.2
    private static let disabledOpacity = 0.4
}
