import SwiftUI

/// Lets the user reclaim a terminal controlled on another device.
struct HandedOffPaneOverlay: View {
    // MARK: Internal

    let reattach: () -> Void

    var body: some View {
        VStack(spacing: Self.spacing) {
            Text("This pane is controlled on another device")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
            Button("Take control", action: reattach)
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
