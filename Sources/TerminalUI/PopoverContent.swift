import AppKit
import SwiftUI

// MARK: - PopoverContent

/// Fits its contents until the current screen requires scrolling.
public struct PopoverContent<Content: View>: View {
    // MARK: Lifecycle

    public init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    // MARK: Public

    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: min(height, screenHeight))
        .background(PopoverScreen { screenHeight = $0 })
    }

    // MARK: Private

    @State private var height: CGFloat = 1
    @State private var screenHeight =
        (NSScreen.main?.visibleFrame.height ?? PopoverLayout.fallbackHeight) - PopoverLayout.margin

    private let width: CGFloat
    private let content: Content
}

// MARK: - PopoverScreen

private struct PopoverScreen: NSViewRepresentable {
    final class ScreenView: NSView {
        // MARK: Lifecycle

        deinit {
            // The screen callback owns nothing beyond the view.
        }

        // MARK: Internal

        var changed: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { @MainActor [weak self] in
                guard let self, let screen = unsafe window?.screen else {
                    return
                }

                changed?(screen.visibleFrame.height - PopoverLayout.margin)
            }
        }
    }

    let changed: (CGFloat) -> Void

    func makeNSView(context _: Context) -> ScreenView {
        let view = ScreenView()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: ScreenView, context _: Context) {
        view.changed = changed
    }
}

// MARK: - PopoverLayout

private enum PopoverLayout {
    static let fallbackHeight: CGFloat = 800
    static let margin: CGFloat = 48
}
