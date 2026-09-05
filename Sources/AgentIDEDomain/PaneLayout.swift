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

    /// The lower bound is what the window itself can be dragged to,
    /// since the sidebar holds whatever width it is given, so it is
    /// as mean as the rows allow: a long branch name truncates with
    /// an ellipsis rather than the pane refusing to narrow, and the
    /// badges that say what needs attention keep their room.
    public static let sidebarRange = 200.0 ... 440.0

    /// What Resize Panes gives the sidebar: enough for a repository
    /// and a branch to read without wrapping or ellipsis, which its
    /// bare minimum is not.
    public static let sidebarComfortable = 300.0

    /// How Resize Panes divides what is left: the work in front of
    /// you gets three fifths, the utilities two.
    public static let utilityShare = 0.4
    public static let utilityRange = 260.0 ... 1_200.0

    /// What the conversation pane needs to stay readable. Every
    /// minimum here is deliberately mean: together they are the
    /// smallest the window can be dragged, and a laptop screen
    /// being made room on wants that number low.
    public static let primaryMinimum = 320.0

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
