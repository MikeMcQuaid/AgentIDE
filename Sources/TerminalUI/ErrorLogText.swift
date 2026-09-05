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

    /// What an identifier is drawn in: the pane's own size, so a
    /// monospaced run sits on the same line as the prose beside it.
    private static let code: NSFont = .monospacedSystemFont(
        ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
        weight: .regular,
    )

    /// Every message reads as prose, whether it failed or not, with
    /// the identifiers it names monospaced and the repository it
    /// belonged to in bold: one treatment across the pane, so a
    /// branch looks like a branch wherever it is said.
    private static func message(of entry: ErrorLog.Entry) -> NSAttributedString {
        let rendered = MessageMarkup.rendered(entry.message)
        let body = NSMutableAttributedString(string: rendered.text, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: NSColor.textColor,
        ])
        for span in rendered.code {
            body.addAttribute(.font, value: Self.code, range: NSRange(span, in: rendered.text))
        }
        if let repository = entry.repository, rendered.text.hasPrefix(repository + ": ") {
            body.addAttribute(
                .font,
                value: NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize),
                range: NSRange(location: 0, length: repository.count),
            )
        }
        for link in MessageLinks.links(in: rendered.text) {
            body.addAttribute(.link, value: link.url, range: NSRange(link.range, in: rendered.text))
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
