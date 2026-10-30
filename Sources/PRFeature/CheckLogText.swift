import AppKit
import SanductorData

/// Renders groups in the shared selectable document without interpreting log output as markup.
enum CheckLogText {
    static func attributed(
        _ document: CheckLogDocument,
        showTimestamps: Bool,
        collapsedGroups: Set<Int>,
        font: NSFont,
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (offset, index) in document.visibleIndices(collapsedGroups: collapsedGroups).enumerated() {
            let line = document.lines[index]
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            attributes[.foregroundColor] =
                switch line.level {
                case .error:
                    NSColor.systemRed

                case .warning:
                    NSColor.systemOrange

                case .notice:
                    NSColor.systemBlue

                case .debug:
                    NSColor.secondaryLabelColor

                case nil:
                    NSColor.textColor
                }
            var title = line.displayed(showTimestamps: false)
            if line.isCommand || line.endIndex != nil {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if line.endIndex != nil {
                title = (collapsedGroups.contains(index) ? "▸ " : "▾ ") + title
                attributes[.link] = URL(string: "sanductor-log-group://" + String(index))
                attributes[.toolTip] = (collapsedGroups.contains(index) ? "Expand " : "Collapse ") + line.text
            }
            if offset > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            if showTimestamps, line.timestamp.isEmpty == false,
               let time = line.timestamp.trimmingCharacters(in: .whitespaces).split(separator: "T").last
            {
                result.append(NSAttributedString(
                    string: String(time.dropLast().split(separator: ".")[0]) + "  ",
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .toolTip: line.timestamp.trimmingCharacters(in: .whitespaces),
                    ],
                ))
            }
            result.append(NSAttributedString(string: title, attributes: attributes))
        }
        return result
    }
}
