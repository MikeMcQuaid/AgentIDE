import AppKit
import SwiftTerm

/// LocalProcess delivers on .main; startup also runs on the main actor.
extension TerminalRepresentable.Coordinator {
    func clipboardCopy(source _: TerminalView, content: Data) {
        guard let view, view.process != nil, let text = String(data: content, encoding: .utf8) else {
            return
        }

        view.copyPasteboard.clearContents()
        view.copyPasteboard.setString(text, forType: .string)
    }

    func clipboardRead(source _: TerminalView) -> Data? {
        guard let view, view.process != nil else {
            return nil
        }

        return view.copyPasteboard.string(forType: .string)?.data(using: .utf8)
    }

    nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { view?.feed(byteArray: slice) }
    }

    nonisolated func processTerminated(_: LocalProcess, exitCode _: Int32?) {
        MainActor.assumeIsolated {
            view?.programStatusProcessExited()
            let callback = onProcessTerminated
            onProcessTerminated = nil
            callback?()
        }
    }

    nonisolated func getWindowSize() -> winsize {
        MainActor.assumeIsolated {
            guard let view else {
                return winsize()
            }

            let dimensions = view.terminalDimensions
            let cell = PaneTerminalView.cellSize(of: view)
            let scale = unsafe view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
            return winsize(
                ws_row: UInt16(clamping: dimensions.rows),
                ws_col: UInt16(clamping: dimensions.cols),
                ws_xpixel: UInt16(clamping: Int(cell.width * CGFloat(dimensions.cols) * scale)),
                ws_ypixel: UInt16(clamping: Int(cell.height * CGFloat(dimensions.rows) * scale)),
            )
        }
    }
}
