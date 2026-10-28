import SwiftUI

/// The one pace state changes animate at: quick enough to read as
/// response rather than motion, used only where a change would
/// otherwise jump (a chevron, rows appearing, a bar sliding in, a
/// page fading over a pane). Nothing decorative, nothing slower.
public enum Motion {
    // MARK: Public

    /// The standard quick ease-out.
    public static let quick: Animation = .easeOut(duration: quickSeconds)

    // MARK: Private

    private static let quickSeconds = 0.15
}
