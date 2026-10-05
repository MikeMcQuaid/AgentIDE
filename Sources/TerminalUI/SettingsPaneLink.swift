import SwiftUI

/// Opens a named Settings pane, including repeated requests for the same pane.
public struct SettingsPaneLink: View {
    // MARK: Lifecycle

    public init(_ title: String, pane: String) {
        self.title = title
        self.pane = pane
    }

    // MARK: Public

    public var body: some View {
        Button(title) {
            UserDefaults.standard.set(pane, forKey: "settingsPane")
            openSettings()
        }
    }

    // MARK: Private

    @Environment(\.openSettings)
    private var openSettings

    private let title: String
    private let pane: String
}
