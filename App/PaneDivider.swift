import SwiftUI

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

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -Self.grabSlop))
            .gesture(drag)
            // The system's own pointer for a column edge: pushing an
            // `NSCursor` on hover fought every neighbouring AppKit
            // view, which sets its own as the pointer crosses it, so
            // the arrow stayed an arrow until a drag began.
            .pointerStyle(.columnResize)
    }

    // MARK: Private

    private static let grabSlop: CGFloat = 3

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
