import AgentIDEData
import AgentIDEDomain
import SwiftUI

extension FeedbackView {
    @ViewBuilder
    func sourceControls(
        available: FeedbackAvailability?,
        localReview: LocalReview?,
        reviewing: Bool,
        privateReviewersAvailable: Bool,
    ) -> some View {
        if localOnly {
            localSources(available: available, review: localReview, reviewing: reviewing)
        } else {
            remoteSourceControls(
                available: available,
                localReview: localReview,
                reviewing: reviewing,
                privateReviewersAvailable: privateReviewersAvailable,
            )
        }
    }

    private func remoteSourceControls(
        available: FeedbackAvailability?, localReview: LocalReview?, reviewing: Bool, privateReviewersAvailable: Bool,
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Self.spacing) {
                localSources(available: available, review: localReview, reviewing: reviewing)
                    .frame(minWidth: Self.stageWidth)
                githubSources(available: available, privateReviewersAvailable: privateReviewersAvailable)
                    .frame(minWidth: Self.stageWidth)
            }
            VStack(alignment: .leading, spacing: Self.spacing) {
                localSources(available: available, review: localReview, reviewing: reviewing)
                githubSources(available: available, privateReviewersAvailable: privateReviewersAvailable)
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

    private func githubSources(available: FeedbackAvailability?, privateReviewersAvailable: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Self.spacing) {
                sourceRow(
                    "Required CI",
                    selection: binding(\.autofixCI),
                    status: remoteStatus(.checks, selected: state.autofixCI, available: available),
                    unavailable: state.number <= 0,
                )
                sourceRow(
                    "Automated reviews",
                    selection: binding(\.autofixBots),
                    status: remoteStatus(.githubReview, selected: state.autofixBots, available: available),
                    unavailable: state.number <= 0,
                )
                .hoverHelp("Includes Copilot, CodeRabbit and GitHub quality/security comments, with nitpicks")
                remoteReviewer
                sourceRow(
                    "Private reviewers",
                    selection: binding(\.autofixReviews),
                    status: privateReviewersAvailable
                        ? remoteStatus(.reviews, selected: state.autofixReviews, available: available)
                        : "Private repository required",
                    unavailable: privateReviewersAvailable == false,
                )
                .hoverHelp("Only unresolved comments from human reviewers with verified repository write access")
            }
            .padding(Self.groupInset)
        } label: {
            HStack {
                Text("GitHub feedback").interfaceFont(.callout, weight: .semibold)
                Spacer()
                rounds("GitHub rounds", selection: binding(\.roundLimit))
                    .disabled(inputsLocked || state.hasRemoteSources == false || state.number <= 0)
            }
        }
    }

    private var remoteReviewer: some View {
        LabeledContent("Request from") {
            Picker("Requested reviewer", selection: binding(\.reviewBot)) {
                ForEach(ReviewBot.allCases, id: \.self) { ReviewerLabel($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(inputsLocked || state.autofixBots == false || state.number <= 0)
            .hoverHelp("One reviewer per push; changing a requested reviewer takes effect after the next push")
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
            return "Local and GitHub heads differ"
        }

        if source == .checks {
            guard let checks = summary.autofixChecks else {
                return "Waiting for required checks"
            }

            if checks.isComplete == false {
                let finished = Set(checks.results
                    .filter { $0.status == "COMPLETED" && $0.conclusion.isEmpty == false }
                    .map(\.name))
                return String(finished.count) + "/" + String(checks.required.count) + " required jobs finished"
            }
            let count = available.counts[.checks] ?? 0
            return count == 0 ? "No required failures" : String(count) + (count == 1 ? " failed job" : " failed jobs")
        }
        let count = source == .githubReview
            ? [.copilot, .codeRabbit, .githubReview].reduce(0) { $0 + (available.counts[$1] ?? 0) }
            : available.counts[source] ?? 0
        return count == 0 ? "No eligible comments" : String(count) + (count == 1 ? " comment" : " comments")
    }

    private func rounds(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(PullRequestAutomation.roundLimits, id: \.self) { limit in
                Text(String(limit) + (limit == 1 ? " round" : " rounds")).tag(limit)
            }
        }
        .labelsHidden()
        .fixedSize()
        .hoverHelp("Maximum fix rounds in this stage when you choose Start loop")
    }
}
