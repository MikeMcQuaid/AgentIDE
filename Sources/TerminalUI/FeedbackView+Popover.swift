import AgentIDEData
import SwiftUI

extension FeedbackView {
    var currentActivity: String {
        if reviewIsBusy {
            "Review in progress"
        } else {
            state.statusSummary
        }
    }

    func popover(onClose: @escaping () -> Void) -> some View {
        PopoverContent(width: localOnly ? Self.localPopoverWidth : Self.popoverWidth) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                HStack {
                    Text("Autofix feedback loop").interfaceFont(.headline)
                    Text(state.loopStatus).interfaceFont(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Close", systemImage: "xmark") { onClose() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .hoverHelp("Close autofix settings; running work continues")
                }
                pushFailure
                configuration
                Divider()
                actions
                FeedbackProgressView(state: state, localOnly: localOnly)
                activity
            }
            .interfaceFont(.body)
            .controlSize(.small)
            .pickerStyle(.menu)
            .toggleStyle(.checkbox)
            .padding(Self.popoverInset)
        }
        .onExitCommand { onClose() }
    }

    var loopActions: some View {
        FlowLayout(spacing: Self.spacing) {
            BusyButton(
                "",
                busy: "",
                systemImage: canStop ? "stop.fill" : "play.fill",
                accessibilityLabel: canStop ? "Stop loop" : "Start loop",
                prominent: true,
                disabled: canStop == false && startUnavailableReason != nil,
            ) {
                if canStop {
                    update { $0.stopLoop() }
                } else {
                    await startLoop()
                }
            }
            .hoverHelp(canStop
                ? "Stop loop; the agent’s current turn continues"
                : startUnavailableReason ?? (localOnly ? "Start loop: review and fix up to the chosen round limit"
                    : "Start loop: run local review rounds, then gather selected GitHub feedback"))
        }
    }

    @ViewBuilder var reviewAction: some View {
        if onReview != nil {
            Button("Review") { openManualReview() }
                .buttonStyle(.glass)
                .disabled(inputsLocked || state.attempt != nil)
                .hoverHelp("Edit the prompt and review the selected changes and commit messages")
        } else {
            BusyButton("Review", busy: "Reviewing", disabled: state.autofixLocalReviews == false || inputsLocked) {
                await review()
            }
            .hoverHelp("Run the chosen local reviewer; inspect findings before copying or fixing")
        }
    }

    @ViewBuilder private var pushFailure: some View {
        if let failure = state.failedPush {
            VStack(alignment: .leading, spacing: Self.spacing) {
                Label("Automatic push failed", systemImage: "exclamationmark.triangle")
                    .interfaceFont(.headline)
                Text("Choose Push to retry. Approve your configured signer if prompted.")
                DisclosureGroup("Error details") {
                    Text(failure.message).textSelection(.enabled)
                }
                BusyButton("Push", busy: "Pushing", disabled: failure.retryRequested || inputsLocked) {
                    update { $0.retryPush() }
                }
            }
            Divider()
        }
    }

    private var canStop: Bool {
        state.isLoopRunning
    }

    private static let popoverWidth: CGFloat = 620
    private static let localPopoverWidth: CGFloat = 440
    private static let popoverInset: CGFloat = 16
}
