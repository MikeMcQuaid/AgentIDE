import AgentIDEDomain
import AppKit
import SwiftTerm

/// A terminal-view delegate that reflows clipboard writes for
/// pasting into prose tools (tmux forwards copy-mode yanks through
/// OSC 52 as clipboard writes) and forwards every other callback to
/// the view's own handling, which stock SwiftTerm provides.
final class ReflowingCopyDelegate: TerminalViewDelegate {
    // MARK: Lifecycle

    /// Creates the delegate over the view whose behaviour it wraps.
    init(base: LocalProcessTerminalView) {
        self.base = base
    }

    deinit {
        // The base view owns every resource.
    }

    // MARK: Internal

    func clipboardCopy(source _: TerminalView, content: Data) {
        guard let text = String(bytes: content, encoding: .utf8) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(PasteableText.reflow(text), forType: .string)
    }

    func clipboardRead(source: TerminalView) -> Data? {
        base?.clipboardRead(source: source)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        base?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        base?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        base?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        base?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        base?.scrolled(source: source, position: position)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        base?.requestOpenLink(source: source, link: link, params: params)
    }

    func bell(source: TerminalView) {
        base?.bell(source: source)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        base?.iTermContent(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        base?.rangeChanged(source: source, startY: startY, endY: endY)
    }

    // MARK: Private

    private weak var base: LocalProcessTerminalView?
}
