import AgentIDEData
import SwiftUI

/// Stages stay in place, with the active one highlighted rather than hidden.
struct FeedbackProgressView: View {
    // MARK: Internal

    let state: PullRequestAutomation

    var body: some View {
        FlowLayout(spacing: Self.spacing) {
            stage(
                "Local " + String(state.localRoundsStarted) + "/" + String(state.localRoundLimit),
                active: state.isAutomatic && state.isLocalStage,
                enabled: state.autofixLocalReviews,
            )
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            stage("Inspect", active: state.isPausedForReview, enabled: state.autofixLocalReviews)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            stage(
                "GitHub " + String(state.roundsStarted) + "/" + String(state.roundLimit),
                active: state.isAutomatic && state.isLocalStage == false,
                enabled: state.hasRemoteSources,
            )
        }
        .interfaceFont(.callout)
        .accessibilityElement(children: .combine)
        .hoverHelp("Local review rounds finish before inspection and the shared GitHub CI and review rounds")
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
