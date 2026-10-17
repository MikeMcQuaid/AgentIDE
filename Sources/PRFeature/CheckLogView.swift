import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// A single job's complete text, shared by viewing and copying.
struct CheckLogView: View {
    // MARK: Internal

    let check: PullRequestCheck
    let fetchLog: (Int) async throws -> String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to checks", systemImage: "chevron.backward", action: onBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .hoverHelp("Back to checks")
                VStack(alignment: .leading) {
                    Text(check.name).interfaceFont(.headline)
                    Text(check.requirement.rawValue + " · " + check.statusDescription).interfaceFont(.caption)
                }
                Spacer()
                CheckDurationView(check: check)
                if check.link.isEmpty == false {
                    Button("Open check", systemImage: "arrow.up.right") { LinkOpener.open(check.link) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .hoverHelp("Open this check's live log; Cmd-click for your browser")
                }
                Button("Copy log", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(log.isEmpty || isLoading)
                .hoverHelp("Copy only this check's complete log")
            }
            .padding(Self.padding)
            Divider()
            content
        }
        .task(id: check) { await load() }
        .onChange(of: codeStyle.appKitFont) { updateText() }
        .onExitCommand(perform: onBack)
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    @State private var log = ""
    @State private var text: NSAttributedString = .init()
    @State private var isLoading = true
    @State private var error: String?

    private var codeStyle: CodeStyle = .init()

    private var unavailableReason: String {
        if check.status == "EXPECTED" {
            "This required check has not reported yet."
        } else if check.jobID == nil {
            "This check publishes its log on its own site. Open the check to view it."
        } else {
            "GitHub makes this log available here when the job finishes. Open the check to follow its live log."
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            LaunchProgressView(spinner: "Loading the check log…")
        } else if log.isEmpty == false {
            SelectableTextView(text: text)
                .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: Self.padding) {
                Text(error ?? unavailableReason)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                if check.canReadLog {
                    BusyButton("Retry", busy: "Loading") { await load() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        log = ""
        error = nil
        isLoading = true
        defer { isLoading = false }
        guard check.canReadLog, let jobID = check.jobID else {
            return
        }

        do {
            let fetched = try await fetchLog(jobID)
            guard Task.isCancelled == false else {
                return
            }

            log = fetched
            updateText()
        } catch {
            guard Task.isCancelled == false else {
                return
            }

            self.error = "Could not read this check's log: " + error.localizedDescription
        }
    }

    private func updateText() {
        text = NSAttributedString(string: log, attributes: [
            .font: codeStyle.appKitFont,
            .foregroundColor: NSColor.textColor,
        ])
    }
}
