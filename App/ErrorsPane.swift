import AgentIDEDomain
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

    private var log: ErrorLog = .shared

    private var entryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.entrySpacing) {
                // Newest first, from the top down: the message that
                // just happened is the one being looked for, and it
                // arrives where the eye already is.
                ForEach(log.entries.reversed()) { entry in
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
    }

    /// One message as one paragraph: the time in front of it and the
    /// text wrapping after, so a short message takes one line rather
    /// than a line for its stamp and another for itself. Links are
    /// live, and open where every other link in the app does.
    private func row(_ entry: ErrorLog.Entry) -> some View {
        // Failures keep the monospaced command-output look; status
        // notes read as prose.
        let font: Font = entry.isError ? .callout.monospaced() : .callout
        return Text("\(mark(entry))\(stamp(entry.date))\(Text(Self.linked(entry.message)).font(font))")
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The message with its web links made clickable.
    private static func linked(_ message: String) -> AttributedString {
        var text = AttributedString(message)
        for link in MessageLinks.links(in: message) {
            guard let lower = AttributedString.Index(link.range.lowerBound, within: text),
                  let upper = AttributedString.Index(link.range.upperBound, within: text)
            else {
                continue
            }

            text[lower ..< upper].link = link.url
        }
        return text
    }

    /// The failure glyph, in the text so the message wraps under
    /// its own first line rather than beside a column of icon.
    private func mark(_ entry: ErrorLog.Entry) -> Text {
        guard entry.isError else {
            return Text("")
        }

        // The glyph reads as part of the message rather than as an
        // image of its own, so the label goes on the text.
        // swiftlint:disable:next accessibility_label_for_image
        let glyph = Text(Image(systemName: "exclamationmark.triangle.fill"))
            .font(.caption)
            .foregroundStyle(.red)
        return Text("\(glyph) ")
    }

    private func stamp(_ date: Date) -> Text {
        let time = Text(date, format: .dateTime.hour().minute().second())
            .font(.caption)
            .foregroundStyle(.secondary)
        return Text("\(time) ")
    }

    private func copyAll() {
        let text = log.entries
            .lazy
            .map { $0.date.formatted(.dateTime.hour().minute().second()) + " " + $0.message }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
