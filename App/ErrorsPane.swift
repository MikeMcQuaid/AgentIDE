import SwiftUI
import TerminalUI

/// The messages tab: every failure and status message this session,
/// in full and selectable, so any of it can be copied straight into
/// a report.
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
            entryList
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let entrySpacing: CGFloat = 10
    private static let lineSpacing: CGFloat = 2
    private static let markSpacing: CGFloat = 4

    private var log: ErrorLog = .shared

    private var entryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.entrySpacing) {
                ForEach(log.entries) { entry in
                    row(entry)
                }
                if log.entries.isEmpty {
                    Text("No messages since the last clear.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
    }

    private func row(_ entry: ErrorLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            HStack(spacing: Self.markSpacing) {
                if entry.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error")
                }
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Failures keep the monospaced command-output look;
            // status notes read as prose.
            Text(entry.message)
                .font(entry.isError ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Straight to the system: the window's link handler only
            // takes web links, and a fix lives in System Settings.
            if let action = entry.action {
                Button(action.label) { NSWorkspace.shared.open(action.url) }
                    .controlSize(.small)
            }
        }
    }

    private func copyAll() {
        let text = log.entries
            .map { $0.date.formatted(.dateTime.hour().minute().second()) + " " + $0.message }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
