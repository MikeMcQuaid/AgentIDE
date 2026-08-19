// MARK: - PaneLayout

/// How wide the window's panes may be. The stored widths were
/// dragged on whatever display the window was on last, so a window
/// that ends up on a smaller one, by being dragged or by having its
/// display unplugged, has to be told what still fits.
public struct PaneLayout: Hashable, Sendable {
    // MARK: Lifecycle

    /// Fits the stored widths to a window: the utility pane gives
    /// way first, then the sidebar, and a window too narrow for all
    /// three drops the utility pane rather than growing past the
    /// screen. Dropping it is for the layout only: what the user
    /// asked for stays stored, so the pane returns with the room.
    /// The parameters are named apart from the properties so that
    /// assigning them needs no `self`, which the formatter strips.
    public init(width: Double, sidebar stored: Double, utility storedUtility: Double, showsUtility wanted: Bool) {
        guard width > 0 else {
            sidebar = stored
            utility = storedUtility
            showsUtility = wanted
            return
        }

        var fittedSidebar = stored.clamped(to: Self.sidebarRange)
        var fittedUtility = storedUtility.clamped(to: Self.utilityRange)
        var fits = wanted
        if fits {
            let overflow = fittedSidebar + fittedUtility + Self.primaryMinimum - width
            if overflow > 0 {
                fittedUtility = max(fittedUtility - overflow, Self.utilityRange.lowerBound)
            }
            // Not even with the sidebar at its narrowest: the
            // utility pane goes rather than the window overflowing.
            fits = Self.sidebarRange.lowerBound + fittedUtility + Self.primaryMinimum <= width
        }
        // The sidebar takes what is left, which is all of it once
        // the utility pane has gone.
        let occupied = (fits ? fittedUtility : 0) + Self.primaryMinimum
        if fittedSidebar + occupied > width {
            fittedSidebar = max(width - occupied, Self.sidebarRange.lowerBound)
        }
        sidebar = fittedSidebar
        utility = fittedUtility
        showsUtility = fits
    }

    // MARK: Public

    /// Slim enough for icon-and-truncated-text rows while staying
    /// wider than the traffic lights band.
    public static let sidebarRange = 150.0 ... 440.0
    public static let utilityRange = 340.0 ... 1_200.0

    /// What the conversation pane needs to stay readable.
    public static let primaryMinimum = 420.0

    public let sidebar: Double
    public let utility: Double

    /// Whether the utility pane fits beside the others right now.
    public let showsUtility: Bool
}

private extension Double {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
