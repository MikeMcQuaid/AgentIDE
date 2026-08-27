import SwiftUI

public extension View {
    /// Keeps a pane mounted while it is not the one showing: it
    /// costs a read to rebuild, and a tab switch should not pay it.
    /// Hidden panes take no clicks and no keys.
    func hidden(_ isHidden: Bool) -> some View {
        opacity(isHidden ? 0 : 1)
            .allowsHitTesting(isHidden == false)
    }
}
