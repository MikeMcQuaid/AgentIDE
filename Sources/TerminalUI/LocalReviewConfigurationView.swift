import AgentIDEData
import AgentIDEDomain
import SwiftUI

/// The exact preferences the next review will read.
public struct LocalReviewConfigurationView: View {
    // MARK: Lifecycle

    public init(reviewer: AgentKind) {
        _model = AppStorage(wrappedValue: "", AppSettings.reviewModelKey(for: reviewer))
        _effort = AppStorage(wrappedValue: "", AppSettings.reviewEffortKey(for: reviewer))
    }

    // MARK: Public

    public var body: some View {
        FlowLayout(spacing: Self.spacing) {
            Text("Model: " + (model.isEmpty ? "CLI default" : model)
                + " · Effort: " + (effort.isEmpty ? "CLI default" : effort))
                .foregroundStyle(.secondary)
            SettingsPaneLink("Change…", pane: "review")
                .buttonStyle(.glass)
        }
        .interfaceFont(.callout)
        .controlSize(.small)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    @AppStorage private var model: String
    @AppStorage private var effort: String
}
