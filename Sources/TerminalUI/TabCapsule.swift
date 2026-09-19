import SwiftUI

// MARK: - TabCapsule

/// Shared spacing and colours for utility bubbles and shell tabs.
public enum TabCapsule {
    // MARK: Public

    /// The room either side of a tab's own contents.
    public static let horizontalPadding: CGFloat = 8

    /// The room above and below them.
    public static let verticalPadding: CGFloat = 3

    /// Between a tab's label and whatever follows it.
    public static let contentSpacing: CGFloat = 4

    /// A tab's background: tinted where it is the selected tab, a
    /// shade of the label colour under the pointer, and nothing at
    /// all otherwise.
    public static func fill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return .accentColor.opacity(selectedOpacity)
        }

        return isHovered ? .primary.opacity(hoverOpacity) : .clear
    }

    // MARK: Private

    private static let selectedOpacity = 0.25
    private static let hoverOpacity = 0.08
}

public extension View {
    /// Fills a tab's capsule behind whatever it holds.
    func tabCapsule(isSelected: Bool, isHovered: Bool) -> some View {
        background(Capsule().fill(TabCapsule.fill(isSelected: isSelected, isHovered: isHovered)))
    }
}
