import SwiftUI
import TerminalUI

/// The messages tab: every failure and status message this session,
/// as one selectable text, so a drag can take several messages
/// straight into a report.
struct ErrorsPane: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Copy all") { copyAll() }
                    .controlSize(.small)
                    .disabled(log.entries.isEmpty)
                    .hoverHelp("Copy every logged message to the clipboard")
                Button("Clear") { log.clear() }
                    .controlSize(.small)
                    .disabled(log.entries.isEmpty)
                    .hoverHelp("Empty the log; the tab stays for this session")
            }
            .padding(Self.padding)
            Divider()
            if log.entries.isEmpty {
                Text("No messages since the last clear.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(Self.padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // One document, newest first: selection crosses
                // entries, Cmd-F finds within it and links open
                // where every other link does.
                SelectableTextView(text: ErrorLogText.attributed(log.entries))
            }
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    private var log: ErrorLog = .shared

    private func copyAll() {
        let text = log.entries
            .lazy
            .map { $0.date.formatted(.dateTime.hour().minute().second()) + " " + $0.message }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
