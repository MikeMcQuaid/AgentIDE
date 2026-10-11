import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

@MainActor
struct PopoverContentTests {
    // MARK: Internal

    @Test
    func `popover fits content then caps at the screen and shrinks again`() async {
        let host = NSHostingView(rootView: content(height: 80))
        await settle(host) { abs(host.fittingSize.height - 80) < 1 }
        #expect(abs(host.fittingSize.height - 80) < 1)
        #expect(host.fittingSize.width == 420)

        host.rootView = content(height: 240)
        await settle(host) { abs(host.fittingSize.height - 240) < 1 }
        #expect(abs(host.fittingSize.height - 240) < 1)

        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        host.rootView = content(height: screenHeight * 2)
        await settle(host) { host.fittingSize.height > 240 }
        #expect(host.fittingSize.height > 240)
        #expect(host.fittingSize.height < screenHeight)

        host.rootView = content(height: 80)
        await settle(host) { abs(host.fittingSize.height - 80) < 1 }
        #expect(abs(host.fittingSize.height - 80) < 1)
    }

    // MARK: Private

    private func content(height: CGFloat) -> some View {
        PopoverContent(width: 420) {
            Text("Review findings").frame(height: height)
        }
    }

    private func settle(_ host: some NSView, until ready: () -> Bool) async {
        for _ in 0 ..< 100 {
            host.layoutSubtreeIfNeeded()
            if ready() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
