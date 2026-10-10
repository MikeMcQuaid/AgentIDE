import AgentIDEData
import SwiftUI

extension FeedbackView {
    func popover(onClose: @escaping () -> Void) -> some View {
        PopoverContent(width: Self.popoverWidth) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                HStack {
                    Text("Autofix feedback loop").interfaceFont(.headline)
                    Spacer()
                    Button("Close", systemImage: "xmark") { onClose() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .hoverHelp("Close autofix settings; running work continues")
                }
                configuration
                Divider()
                actions
                FeedbackProgressView(state: state)
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
            BusyButton("Start loop", busy: "Starting", prominent: true, disabled: startUnavailableReason != nil) {
                update { $0.startLoop() }
            }
            .hoverHelp(startUnavailableReason ?? "Run local review rounds, then gather selected GitHub feedback")
            BusyButton(
                "Continue to GitHub",
                busy: "Continuing",
                disabled: startUnavailableReason != nil || state.isPausedForReview == false
                    || state.hasRemoteSources == false || state.number <= 0,
            ) {
                update { $0.continueToGitHub() }
            }
            .hoverHelp("After inspecting local changes, allow the pending push and shared GitHub rounds")
            Button("Stop loop", systemImage: "stop.fill") {
                update { $0.isAutomatic = false; $0.attempt = nil; $0.pending = "" }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .disabled(state.isAutomatic == false && state.attempt == nil)
            .hoverHelp("Stop further rounds and pushes; the agent’s current turn continues")
        }
    }

    private static let popoverWidth: CGFloat = 620
    private static let popoverInset: CGFloat = 16
}
