import SwiftUI
import TerminalUI

extension ReviewView {
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
        } else if model.files.isEmpty {
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

    func localReviewButton(
        model: ReviewModel,
        localReview: LocalReviewModel,
        isPresented: Binding<Bool>,
    ) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(localReview.reviewer.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: Self.reviewIconSize, height: Self.reviewIconSize)
                .opacity(localReview.isRunning ? 0 : 1)
                .overlay {
                    if localReview.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.glass)
        .disabled(worktree.isHostDirectory)
        .accessibilityLabel("Review with " + localReview.reviewer.displayName)
        .accessibilityValue(localReview.isRunning ? "Review in progress" : "")
        .hoverHelp(localReview.isRunning ? "Review in progress" : "Edit the review prompt and manage local findings")
        .popover(isPresented: isPresented, arrowEdge: .bottom) { LocalReviewView(model: localReview, diff: model) }
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
    private static let reviewIconSize: CGFloat = 14
}
