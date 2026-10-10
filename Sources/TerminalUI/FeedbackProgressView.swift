import AgentIDEData
import SwiftUI

/// Stages stay in place, with the active one highlighted rather than hidden.
struct FeedbackProgressView: View {
    // MARK: Internal

    let state: PullRequestAutomation
    var localOnly = false

    var body: some View {
        FlowLayout(spacing: Self.spacing) {
            stage(
                "Local " + String(state.localRoundsStarted) + "/" + String(state.localRoundLimit),
                active: state.isAutomatic && state.isLocalStage,
                enabled: state.autofixLocalReviews,
            )
            if localOnly == false {
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                stage("Push", active: state.pushedCommit != nil, enabled: state.pushAutomatically)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                stage(
                    "GitHub " + String(state.roundsStarted) + "/" + String(state.roundLimit),
                    active: state.isAutomatic && state.isLocalStage == false,
                    enabled: state.hasRemoteSources,
                )
            }
        }
        .interfaceFont(.callout)
        .accessibilityElement(children: .combine)
        .hoverHelp(localOnly ? "Review and fix for the chosen number of rounds, then inspect the changes"
            : "Local review and commit rounds finish before pushing and the shared GitHub CI and review rounds")
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
