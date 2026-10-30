import SanductorDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestCheckFilter

struct PullRequestCheckFilter: Equatable {
    var requiredOnly = false
    var unfinishedOnly = false

    func includes(_ check: PullRequestCheck) -> Bool {
        (requiredOnly == false || check.requirement == .required)
            && (unfinishedOnly == false || check.isComplete == false)
    }
}

// MARK: - PullRequestCheckFilterView

struct PullRequestCheckFilterView: View {
    // MARK: Internal

    @Binding var filter: PullRequestCheckFilter

    var body: some View {
        HStack(spacing: Self.spacing) {
            PaneIconButton(
                "asterisk.circle",
                help: filter.requiredOnly ? "Show required and non-required checks" : "Show only required checks",
                isOn: filter.requiredOnly,
            ) { filter.requiredOnly.toggle() }
            PaneIconButton(
                "hourglass",
                help: filter.unfinishedOnly ? "Show finished and unfinished checks" : "Show only unfinished checks",
                isOn: filter.unfinishedOnly,
            ) { filter.unfinishedOnly.toggle() }
        }
        .padding(Self.spacing)
        .background(.thinMaterial, in: Capsule())
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
}
