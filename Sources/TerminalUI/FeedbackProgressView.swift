import SanductorData
import SwiftUI

/// Stages stay in place, with the active one highlighted rather than hidden.
struct FeedbackProgressView: View {
    // MARK: Internal

    let state: PullRequestAutomation
    var localOnly = false

    var body: some View {
        FlowLayout(spacing: Self.spacing) {
            stage("Existing work", active: state.isAutomatic && state.isPreparingExistingWork, enabled: true)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            stage(
                "Local " + String(state.localRoundsStarted) + "/" + String(state.localRoundLimit),
                active: state.isAutomatic && state.isLocalStage && state.isPreparingExistingWork == false,
                enabled: state.autofixLocalReviews,
            )
            if localOnly == false {
                stage(
                    "Watching GitHub",
                    active: state.isAutomatic && state.hasRemoteSources,
                    enabled: state.hasRemoteSources,
                )
            }
        }
        .interfaceFont(.callout)
        .accessibilityElement(children: .combine)
        .hoverHelp("Finish existing feedback and local changes first. " + (localOnly
                ? "Review and fix for the chosen number of rounds, then inspect the changes"
                : "Fixes stay local while autofix watches GitHub for new feedback"))
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private func stage(_ title: String, active: Bool, enabled: Bool) -> some View {
        Text(title)
            .interfaceFont(.callout, weight: active ? .semibold : .regular)
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .accessibilityValue(active ? "Current stage" : enabled ? "" : "Not selected")
    }
}
