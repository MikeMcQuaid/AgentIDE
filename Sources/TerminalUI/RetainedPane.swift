import SwiftUI

/// A collapsible pane whose mounted content owns running processes.
public struct RetainedPane<Content: View>: View {
    // MARK: Lifecycle

    /// Keeps the pane's normal width available while it is collapsed.
    public init(isExpanded: Bool, width: CGFloat, @ViewBuilder content: () -> Content) {
        self.isExpanded = isExpanded
        self.width = width
        self.content = content()
    }

    // MARK: Public

    public var body: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .frame(width: isExpanded ? width : 0, alignment: .trailing)
            .clipped()
            .hidden(isExpanded == false)
    }

    // MARK: Private

    private let isExpanded: Bool
    private let width: CGFloat
    private let content: Content
}
