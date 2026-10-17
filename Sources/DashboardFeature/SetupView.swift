import AgentIDEData
import SwiftUI
import TerminalUI

/// Replaces the entire window until setup succeeds; there is no dismiss action.
public struct SetupView: View {
    // MARK: Lifecycle

    public init(model: SetupModel) {
        self.model = model
    }

    // MARK: Public

    public var body: some View {
        VStack(spacing: Self.spacing) {
            if model.isChecking || model.issues.isEmpty {
                if showsProgress {
                    LaunchProgressView(spinner: "Checking AgentIDE setup…")
                } else {
                    Spacer()
                }
            } else {
                instructions
            }
            HStack {
                Spacer()
                Button("Exit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.glass)
                BusyButton("Recheck", busy: "Checking…", prominent: true, disabled: model.isChecking) {
                    await model.recheck()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, ignoresSafeAreaEdges: [])
        .environment(\.openURL, OpenURLAction { _ in .systemAction(prefersInApp: false) })
        .task { await model.recheck() }
        .task(id: model.isChecking) {
            showsProgress = false
            guard model.isChecking else {
                return
            }

            try? await Task.sleep(for: .seconds(Self.progressSeconds))
            if Task.isCancelled == false {
                showsProgress = true
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 20
    private static let issueSpacing: CGFloat = 8
    private static let maximumWidth: CGFloat = 760
    private static let minimumWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 480
    private static let progressSeconds = 0.5

    @State private var showsProgress = false

    private let model: SetupModel
    private var codeStyle: CodeStyle = .init()

    private var instructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.spacing) {
                Text("Set up AgentIDE").interfaceFont(.title, weight: .semibold)
                if let issue = model.currentIssue {
                    Text("Step " + String(issue.step.rawValue) + " of " + String(SetupStep.allCases.count))
                        .interfaceFont(.caption)
                    VStack(alignment: .leading, spacing: Self.issueSpacing) {
                        Text(issue.title).interfaceFont(.headline)
                        Text(.init(issue.explanation)).textSelection(.enabled)
                        ForEach(
                            issue.commands.components(separatedBy: "\n\n").filter { $0.isEmpty == false },
                            id: \.self,
                            content: commandGroup,
                        )
                        if issue.alternative.isEmpty == false {
                            Text(.init(issue.alternative)).textSelection(.enabled)
                        }
                    }
                    Text("Complete this step in Terminal, then choose Recheck to continue.")
                    if model.signingDisabled {
                        Text("Commit signing is off because no usable signer is configured. "
                            + "You can enable it later in Settings → General.")
                            .interfaceFont(.caption)
                    }
                }
            }
            .frame(maxWidth: Self.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func commandGroup(_ commands: String) -> some View {
        HStack(alignment: .top) {
            Text(commands)
                .font(codeStyle.font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy commands", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commands, forType: .string)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .help("Copy commands")
        }
    }
}
