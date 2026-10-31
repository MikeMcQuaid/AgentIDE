import SanductorData
import SanductorDomain
import SwiftUI

extension FeedbackView {
    func binding<Value>(_ path: WritableKeyPath<PullRequestAutomation, Value>) -> Binding<Value> {
        Binding(get: { state[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }

    @ViewBuilder
    func sourceControls(
        available: FeedbackAvailability?,
        localReview: LocalReview?,
        reviewing: Bool,
    ) -> some View {
        if localOnly {
            localSources(available: available, review: localReview, reviewing: reviewing)
        } else {
            remoteSourceControls(
                available: available,
                localReview: localReview,
                reviewing: reviewing,
            )
        }
    }

    private func remoteSourceControls(
        available: FeedbackAvailability?, localReview: LocalReview?, reviewing: Bool,
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Self.spacing) {
                localSources(available: available, review: localReview, reviewing: reviewing)
                    .frame(minWidth: Self.stageWidth)
                githubSources(available: available)
                    .frame(minWidth: Self.stageWidth)
            }
            VStack(alignment: .leading, spacing: Self.spacing) {
                localSources(available: available, review: localReview, reviewing: reviewing)
                githubSources(available: available)
            }
        }
    }

    private static let stageWidth: CGFloat = 260
    private static let groupInset: CGFloat = 4

    private func localSources(available: FeedbackAvailability?, review: LocalReview?, reviewing: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Self.spacing) {
                sourceRow("Local AI", selection: binding(\.autofixLocalReviews), status: localStatus(
                    available: available, review: review, reviewing: reviewing,
                ))
                LabeledContent("Reviewer") {
                    Picker("Local reviewer", selection: Binding(
                        get: { state.reviewer ?? .claudeCode },
                        set: { reviewer in update { $0.reviewer = reviewer } },
                    )) {
                        ForEach(AgentKind.allCases, id: \.self) { ReviewerLabel($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(inputsLocked || state.autofixLocalReviews == false)
                    .hoverHelp("Also remember this reviewer for this repository")
                }
                LocalReviewConfigurationView(reviewer: state.reviewer ?? .claudeCode)
                    .disabled(inputsLocked || state.autofixLocalReviews == false)
            }
            .padding(Self.groupInset)
        } label: {
            HStack {
                Text("Local review").interfaceFont(.callout, weight: .semibold)
                Spacer()
                rounds("Local rounds", selection: binding(\.localRoundLimit))
                    .disabled(inputsLocked || state.autofixLocalReviews == false)
            }
        }
    }

    private func githubSources(available: FeedbackAvailability?) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Self.spacing) {
                sourceRow(
                    "CI",
                    selection: binding(\.autofixCI),
                    status: remoteStatus(.checks, selected: state.autofixCI, available: available),
                    unavailable: state.number <= 0,
                )
                sourceRow(
                    "Bot reviews",
                    selection: binding(\.autofixBots),
                    status: remoteStatus(.githubReview, selected: state.autofixBots, available: available),
                    unavailable: state.number <= 0,
                )
                .hoverHelp("Includes Copilot, CodeRabbit and GitHub quality/security comments, with nitpicks")
                sourceRow(
                    "Human reviews",
                    selection: binding(\.autofixReviews),
                    status: remoteStatus(.reviews, selected: state.autofixReviews, available: available),
                    unavailable: state.number <= 0,
                )
                .hoverHelp("Only unresolved comments from human reviewers with verified repository write access")
            }
            .padding(Self.groupInset)
        } label: {
            Text("GitHub feedback").interfaceFont(.callout, weight: .semibold)
        }
    }

    private func sourceRow(
        _ title: String, selection: Binding<Bool>, status: String, unavailable: Bool = false,
    ) -> some View {
        HStack {
            Toggle(title, isOn: selection).fixedSize().disabled(inputsLocked || unavailable)
            Spacer(minLength: Self.spacing)
            Text(status).interfaceFont(.callout).foregroundStyle(.secondary).lineLimit(1).hoverHelp(status)
        }
    }

    private func localStatus(available: FeedbackAvailability?, review: LocalReview?, reviewing: Bool) -> String {
        if reviewing || state.collection?.isPending == true {
            return "Reviewing…"
        }
        if state.autofixLocalReviews == false {
            return ""
        }
        if review?.failure != nil {
            return "Review failed"
        }
        guard let current = available?.localReview else {
            return review == nil ? "Not reviewed" : "Review again"
        }

        return current.remaining == 0 ? "No findings"
            : String(current.remaining) + (current.remaining == 1 ? " finding" : " findings")
    }

    private func remoteStatus(
        _ source: AutofixAttempt.Kind, selected: Bool, available: FeedbackAvailability?,
    ) -> String {
        guard state.number > 0 else {
            return "Open a PR first"
        }
        guard selected else {
            return ""
        }
        guard let available, let summary = available.summary else {
            return "Loading…"
        }
        guard available.hasMatchingHead else {
            return "Integrate the current PR head"
        }

        if source == .checks {
            guard let checks = summary.autofixChecks else {
                return "Waiting for CI checks"
            }

            if checks.isComplete == false {
                let finished = Set(checks.results
                    .filter { $0.status == "COMPLETED" && $0.conclusion.isEmpty == false }
                    .map(\.name))
                return String(finished.count) + "/"
                    + String(Set(checks.results.map(\.name)).union(checks.required).count) + " jobs finished"
            }
            let count = available.counts[.checks] ?? 0
            return count == 0 ? "No failures" : String(count) + (count == 1 ? " failed job" : " failed jobs")
        }
        let count = source == .githubReview
            ? [.copilot, .codeRabbit, .githubReview].reduce(0) { $0 + (available.counts[$1] ?? 0) }
            : available.counts[source] ?? 0
        return count == 0 ? "No eligible comments" : String(count) + (count == 1 ? " comment" : " comments")
    }

    private func rounds(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(PullRequestAutomation.localRoundLimits, id: \.self) { limit in
                Text(String(limit) + (limit == 1 ? " round" : " rounds")).tag(limit)
            }
        }
        .labelsHidden()
        .fixedSize()
        .hoverHelp("Maximum local review and fix cycles when you choose Start loop")
    }
}
