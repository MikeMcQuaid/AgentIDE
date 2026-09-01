import AgentIDEDomain
import AppKit

/// The messages pane's whole log as one attributed text, newest
/// first, so a drag can select across entries the way it cannot
/// across a stack of texts.
public enum ErrorLogText {
    // MARK: Public

    /// The entries newest first: a failure glyph where one is due,
    /// the time in front, the message wrapping after it, and web
    /// links live.
    public static func attributed(_ entries: [ErrorLog.Entry]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, entry) in entries.reversed().enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n\n"))
            }
            if entry.isError {
                text.append(Self.failureMark())
            }
            text.append(NSAttributedString(string: Self.time(entry.date) + " ", attributes: [
                .font: NSFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            text.append(Self.message(of: entry))
        }
        return text
    }

    // MARK: Private

    /// Failures keep the monospaced command-output look; status
    /// notes read as prose.
    private static func message(of entry: ErrorLog.Entry) -> NSAttributedString {
        let body = NSMutableAttributedString(string: entry.message, attributes: [
            .font: entry.isError
                ? NSFont.monospacedSystemFont(
                    ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
                    weight: .regular,
                )
                : NSFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: NSColor.textColor,
        ])
        for link in MessageLinks.links(in: entry.message) {
            body.addAttribute(.link, value: link.url, range: NSRange(link.range, in: entry.message))
        }
        return body
    }

    /// The failure glyph, part of the text so the message wraps
    /// under its own first line rather than beside a column of icon.
    private static func failureMark() -> NSAttributedString {
        let configured = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "Failure",
        )?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        guard let configured else {
            return NSAttributedString(string: "")
        }

        let attachment = NSTextAttachment()
        attachment.image = configured
        let mark = NSMutableAttributedString(attachment: attachment)
        mark.append(NSAttributedString(string: " "))
        return mark
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}
