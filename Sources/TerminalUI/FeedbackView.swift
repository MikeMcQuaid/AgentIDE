import AgentIDEData
import AgentIDEDomain
import AppKit
import SwiftUI

/// The shared workflow lives beside the diff and PR, separate from the local reviewer.
public struct FeedbackView: View {
    // MARK: Lifecycle

    public init(
        service: SessionService,
        repositoryPath: String,
        worktreePath: String?,
        summary: PullRequestSummary? = nil,
        localOnly: Bool = false,
        reviewIsBusy: Bool = false,
        loopUnavailableReason: String? = nil,
        onReview: ((AgentKind) -> Void)? = nil,
    ) {
        self.service = service
        self.repositoryPath = repositoryPath
        self.worktreePath = worktreePath
        self.summary = localOnly ? nil : summary
        self.localOnly = localOnly
        self.reviewIsBusy = reviewIsBusy
        self.loopUnavailableReason = loopUnavailableReason
        self.onReview = onReview
        _initial = State(initialValue: service.feedbackState(
            repositoryPath: repositoryPath, worktreePath: worktreePath, summary: localOnly ? nil : summary,
        ))
    }

    // MARK: Public

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            FeedbackLoopIcon(isRunning: state.isLoopRunning)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityLabel("Autofix feedback loop")
        .accessibilityValue(currentActivity)
        .hoverHelp("Autofix feedback loop · " + currentActivity)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popover { isPresented = false }
        }
        .task(id: refreshID) {
            if isPresented {
                await reload()
            }
        }
    }

    // MARK: Internal

    static let spacing: CGFloat = 8

    let service: SessionService
    let repositoryPath: String
    let worktreePath: String?
    let summary: PullRequestSummary?
    let localOnly: Bool
    let reviewIsBusy: Bool
    let loopUnavailableReason: String?
    let onReview: ((AgentKind) -> Void)?

    var state: PullRequestAutomation {
        _ = generation
        return service.currentFeedback(summary.map { selected in
            service.feedbackState(repositoryPath: repositoryPath, worktreePath: worktreePath, summary: selected)
        } ?? initial)
    }

    var inputsLocked: Bool {
        isCopying || isReviewing || reviewIsBusy || state.isLoopRunning || state.collection?.isPending == true
    }

    var startUnavailableReason: String? {
        if state.isAutomatic {
            "Stop the current loop before starting another."
        } else if state.pushedCommit != nil {
            "Wait for GitHub to confirm the push."
        } else if let loopUnavailableReason {
            loopUnavailableReason
        } else if isCopying || isReviewing || reviewIsBusy || state.collection?.isPending == true {
            "Wait for the current review or copy to finish."
        } else if state.attempt != nil {
            "A fix is outstanding. Stop the loop to cancel this cycle."
        } else if summary?.state == "CLOSED" || summary?.state == "MERGED" {
            "Autofix requires an open PR."
        } else if state.autofixReviews, privateReviewersAvailable == false,
                  state.autofixLocalReviews == false, state.autofixCI == false, state.autofixBots == false
        {
            "Private reviewers require a confirmed private repository."
        } else if state.autofixLocalReviews == false, state.hasRemoteSources == false {
            "Select a feedback source to start a loop."
        } else {
            nil
        }
    }

    @ViewBuilder var configuration: some View {
        if isLoading {
            LaunchProgressView(
                "Loading feedback", waitingOn: localOnly ? "local review findings" : "this branch’s pull request",
            )
        } else {
            VStack(alignment: .leading, spacing: Self.spacing) {
                sourceControls(
                    available: available,
                    localReview: localReview,
                    reviewing: isReviewing,
                    privateReviewersAvailable: privateReviewersAvailable,
                )
                if localOnly == false {
                    Toggle("Push fixes automatically", isOn: binding(\.pushAutomatically))
                        .disabled(state.number <= 0)
                        .hoverHelp("Shared by all sources; pushes wait until local review rounds finish")
                }
                findings
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var actions: some View {
        FlowLayout(spacing: Self.spacing) {
            loopActions
            reviewAction
            BusyButton(
                "Copy all (" + String(available?.itemCount ?? 0) + ")",
                busy: "Copying",
                disabled: available?.canCopy != true || isReading || inputsLocked || loopUnavailableReason != nil,
            ) {
                await copy()
            }
            .hoverHelp(localOnly ? "Copy current local findings as one prompt"
                : "Copy selected ready findings, required job failures and eligible comments as one prompt")
        }
        .disabled(isLoading)
    }

    var activity: some View {
        VStack(alignment: .leading) {
            FeedbackActivityView(state: state)
            if message.isEmpty == false {
                Text(message).textSelection(.enabled)
            }
        }
    }

    var findings: some View {
        DisclosureGroup("Last local review (" + String(localReview?.remaining ?? 0) + ")", isExpanded: $showsFindings) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                LocalReviewDetailsView(review: localReview)
                ForEach(localReview?.threads ?? []) { thread in
                    ReviewThreadRow(thread: thread, localReviewer: localReview?.reviewer)
                }
            }
        }
        .disabled(localReview == nil)
    }

    func update(_ change: (inout PullRequestAutomation) -> Void) {
        do {
            try service.updateFeedback(state, change: change)
            message = ""
            generation += 1
        } catch { message = error.localizedDescription }
    }

    func binding<Value>(_ path: WritableKeyPath<PullRequestAutomation, Value>) -> Binding<Value> {
        Binding(get: { state[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }

    func review() async {
        isReviewing = true
        message = "Reviewing local changes"
        defer { isReviewing = false; generation += 1 }
        do {
            try await service.reviewLocalFeedback(state)
            showsFindings = true
            message = ""
        } catch { message = error.localizedDescription }
    }

    func openManualReview() {
        isPresented = false
        onReview?(state.reviewer ?? .claudeCode)
    }

    // MARK: Private

    @State private var privateReviewersAvailable = false

    @State private var showsFindings = false
    @State private var localReview: LocalReview?

    @State private var initial: PullRequestAutomation
    @State private var message = ""
    @State private var isCopying = false
    @State private var isReviewing = false
    @State private var isPresented = false
    @State private var isLoading = true
    @State private var isReading = false
    @State private var available: FeedbackAvailability?
    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var generation = 0

    private var refreshID: String {
        (summary?.url ?? worktreePath ?? repositoryPath) + "#" + (summary?.headCommit ?? "")
            + "#" + String(generation) + "#" + String(isPresented)
    }

    private var currentActivity: String {
        if reviewIsBusy {
            "Review in progress"
        } else {
            state.statusSummary
        }
    }

    private func copy() async {
        NSPasteboard.general.clearContents()
        isCopying = true
        defer { isCopying = false }
        do {
            try await NSPasteboard.general.setString(service.copyFeedback(state), forType: .string)
            message = "Copied all available feedback"
        } catch { message = error.localizedDescription; available = nil }
    }

    private func reload() async {
        isReading = true
        defer { isLoading = false; isReading = false }
        do {
            if localOnly == false, summary == nil, let worktreePath {
                let found = try await service.feedbackSummary(
                    repositoryPath: repositoryPath, worktreePath: worktreePath,
                )
                initial = service.feedbackState(
                    repositoryPath: repositoryPath, worktreePath: worktreePath, summary: found,
                )
            }
            privateReviewersAvailable = state.number > 0
                ? await service.privateReviewersAvailable(repositoryPath: repositoryPath) : false
            if let path = state.feedbackWorktreePath ?? state.localWorktreePath ?? worktreePath {
                localReview = service.localReview(worktreePath: path)
            }
            try await service.recoverFeedback(state)
            guard isCopying == false, isReviewing == false else {
                return
            }

            let latest = try await service.availableFeedback(state)
            if Task.isCancelled == false {
                available = latest
                if let review = latest.localReview {
                    localReview = review
                }
            }
        } catch {
            if Task.isCancelled == false {
                message = error.localizedDescription
            }
        }
    }
}
