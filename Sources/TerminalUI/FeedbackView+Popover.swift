import AgentIDEData
import SwiftUI

extension FeedbackView {
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
                    update { $0.startLoop() }
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
                .disabled(state.isAutomatic || state.attempt != nil || state.collection?.isPending == true)
                .hoverHelp("Edit the prompt and review the selected changes and commit messages")
        } else {
            BusyButton("Review", busy: "Reviewing", disabled: state.autofixLocalReviews == false || inputsLocked) {
                await review()
            }
            .hoverHelp("Run the chosen local reviewer; inspect findings before copying or fixing")
        }
    }

    private var canStop: Bool {
        state.isLoopRunning
    }

    private static let popoverWidth: CGFloat = 620
    private static let localPopoverWidth: CGFloat = 440
    private static let popoverInset: CGFloat = 16
}
