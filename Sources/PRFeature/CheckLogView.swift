import AgentIDEData
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
                PaneIconButton("chevron.backward", help: "Back to checks", action: onBack)
                VStack(alignment: .leading) {
                    Text(check.displayName).interfaceFont(.headline)
                    CheckStatusView(check: check)
                }
                Spacer()
                Text("(" + check.requirement.rawValue + ")")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                logActions
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
    private static let controlSpacing: CGFloat = 4

    @State private var log = ""
    @State private var document: CheckLogDocument = .init("")
    @State private var text: NSAttributedString = .init()
    @State private var collapsedGroups: Set<Int> = []
    @State private var showTimestamps = false
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

    private var logActions: some View {
        HStack(spacing: Self.controlSpacing) {
            PaneIconButton(
                "clock",
                help: showTimestamps ? "Hide log timestamps" : "Show log timestamps",
                isOn: showTimestamps,
                disabled: log.isEmpty || isLoading,
            ) {
                showTimestamps.toggle()
                updateText()
            }
            if check.link.isEmpty == false {
                PaneIconButton(
                    LinkOpener.systemImage,
                    help: "Open this check in the Browser tab; Cmd-click for the browser set in Settings",
                ) { LinkOpener.open(check.link) }
            }
            PaneIconButton(
                "doc.on.doc",
                help: "Copy this check's complete log, including collapsed groups",
                disabled: log.isEmpty || isLoading,
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document.plainText(showTimestamps: showTimestamps), forType: .string)
            }
        }
        .padding(Self.controlSpacing)
        .background(.thinMaterial, in: Capsule())
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            LaunchProgressView(spinner: "Loading the check log…")
        } else if log.isEmpty == false {
            SelectableTextView(text: text, onOpenLink: toggleGroup)
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
            document = CheckLogDocument(fetched)
            collapsedGroups = Set(document.lines.indices.filter { document.lines[$0].endIndex != nil })
            updateText()
        } catch {
            guard Task.isCancelled == false else {
                return
            }

            self.error = "Could not read this check's log: " + error.localizedDescription
        }
    }

    private func updateText() {
        text = CheckLogText.attributed(
            document, showTimestamps: showTimestamps, collapsedGroups: collapsedGroups, font: codeStyle.appKitFont,
        )
    }

    private func toggleGroup(_ url: URL) -> Bool {
        guard url.scheme == "agentide-log-group", let host = url.host, let index = Int(host),
              document.lines.indices.contains(index), document.lines[index].endIndex != nil
        else {
            return false
        }

        if collapsedGroups.remove(index) == nil {
            collapsedGroups.insert(index)
        }
        updateText()
        return true
    }
}
