import SwiftUI

/// Clearances for content sharing the transparent titlebar band, so
/// top rows flow around the traffic lights instead of sitting below
/// them.
public enum WindowChrome {
    /// Width of the traffic lights at the window's top left.
    public static let trafficLightClearance: CGFloat = 78

    /// The traffic lights plus the floating show-sidebar toggle that
    /// appears when the repository sidebar is hidden.
    public static let hiddenSidebarClearance: CGFloat = 110
}
