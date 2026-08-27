import AppKit

/// What a paste carries, for the agent panes: files, or an image
/// with no file behind it. Split from the view for length.
extension PaneTerminalView {
    /// The files on the pasteboard: file URLs as they are, or an
    /// image with no file behind it (a screenshot copied straight
    /// from the screen) written to a PNG in a temporary directory
    /// first. Empty when the paste is text.
    static func pastedFiles() -> [URL] {
        let pasteboard = NSPasteboard.general
        let urls = (pasteboard.pasteboardItems ?? [])
            .compactMap { $0.string(forType: .fileURL) }
            .compactMap { URL(string: $0) }
            .filter(\.isFileURL)
        if urls.isEmpty == false {
            return urls
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            return []
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agentide-paste")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("pasted-" + UUID().uuidString + ".png")
        guard (try? png.write(to: file)) != nil else {
            return []
        }

        return [file]
    }
}
