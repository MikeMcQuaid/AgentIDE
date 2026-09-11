import SwiftUI

/// What a pane draws over itself once it has shown nothing through
/// the deadline and a silent reattach: what is wrong in a line, and
/// the one button that puts it right.
struct StalledPaneOverlay: View {
    // MARK: Internal

    let reattach: () -> Void

    var body: some View {
        VStack(spacing: Self.spacing) {
            Text("This pane has drawn nothing from herdr")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Reattach", action: reattach)
                .buttonStyle(.glass)
                .hoverHelp("Discard the herdr client and attach afresh; the session itself keeps running")
        }
        .padding(Self.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.corner))
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 16
    private static let corner: CGFloat = 10
}
