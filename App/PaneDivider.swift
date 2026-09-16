import SwiftUI
import TerminalUI

/// A draggable pane divider driving a bound pane width, so split
/// sizes are plain persisted state rather than split view internals
/// that reset every launch.
struct PaneDivider: View {
    // MARK: Internal

    @Binding var width: Double

    let range: ClosedRange<Double>

    /// Whether the controlled pane sits left of the divider; a drag
    /// to the right then grows it rather than shrinking it.
    let controlsLeadingPane: Bool
    let onReset: () -> Void

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .padding(.horizontal, Self.grabSlop)
            .contentShape(Rectangle())
            .gesture(drag)
            .onTapGesture(count: Self.resetClickCount, perform: onReset)
            // Hover and dragging share real bounds; extending only
            // the hit shape left the cursor over a one-point line.
            .pointerStyle(.columnResize)
            .hoverHelp("Drag to resize; double-click to restore the default width")
            .padding(.horizontal, -Self.grabSlop)
            .zIndex(1)
    }

    // MARK: Private

    private static let grabSlop: CGFloat = 5
    private static let resetClickCount = 2

    @State private var widthAtDragStart: Double?

    private var drag: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                let delta = controlsLeadingPane ? value.translation.width : -value.translation.width
                width = min(max(start + delta, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in widthAtDragStart = nil }
    }
}
